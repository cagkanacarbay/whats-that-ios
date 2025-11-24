# Fish Audio TTS Integration Plan

## Goals
- Replace the current webhook + server-hosted TTS model with Fish Audio for all discovery audio generation.
- Trigger TTS via a new Voiceover Edge Function called by the client: auto-generate right after Ask AI v7 returns text when the user has auto enabled (2 credits total), or on-demand later (1 credit).
- Allow per-user defaults and per-discovery override for auto-TTS and preferred voice/model settings supplied in each call (stored client-side); no prosody controls (always Fish defaults speed 1.0, volume 0 dB).
- Persist audio and metadata in Supabase storage/DB so the app can stream via signed URLs, expose pending/error states, and respect credit/refund rules aligned with existing analysis flows.

## Current State (app + backend)
- Client playback currently lists storage objects via `SupabaseVoiceoverRepository`; this will be removed in favor of table-driven lookups + Edge Function response. Legacy WAV/kitten assets and min-ID guard will be dropped.
- Discoveries table no longer stores voiceover columns; playback moves to `discovery_voiceovers` + storage with signed URLs.
- App shows a voiceover button only when an asset exists or an error occurred; missing assets hide the control (no pending state today). New UI will surface processing/ready/download/failed-with-retry on the same button.
- Credits: discovery analysis decrements 1 credit on completion; voiceover credit will be 1 (auto/manual) via the Edge Function with refund on failure.
- No user setting for TTS yet; will add a settings sheet for auto toggle + voice selection (no prosody controls).

## Fish Audio API (baseline we will use)
- Endpoint: `POST https://api.fish.audio/v1/tts`
- Auth: `Authorization: Bearer FISH_AUDIO_API_KEY` (secret in Supabase)
- Headers: `Content-Type: application/msgpack`; optional `model: s1` (default backend); we’ll stick to `s1`.
- Request fields we’ll send:
  - `text`: discovery `description` only (no title/short description)
  - `reference_id`: voice/model ID (from curated list)
  - `format`: `mp3` (Fish defaults; mp3 bitrates 64/128/192 are available—see bitrate notes)
  - `chunk_length`: 100–300 (default 200) optional
  - `normalize`: default true
  - Advanced controls (temperature/top_p/references/emotion markers) are out of scope for v1.
- Response: binary audio stream in requested format. We upload to storage.
- Streaming/WebSocket exists but out of scope for this flow.

## Proposed Architecture
- **Data model**
  - `discovery_voiceovers` table: `id bigserial PK`, `discovery_id bigint NOT NULL` FK → discoveries ON DELETE CASCADE, `user_id uuid NOT NULL` FK → auth.users, `provider text NOT NULL CHECK (IN ('fish'))`, `tts_model text NOT NULL DEFAULT 's1'`, `voice_model_id text NOT NULL`, `file_name text NOT NULL` (includes extension), `file_extension text NOT NULL DEFAULT 'mp3'`, `status text NOT NULL CHECK (IN ('processing','ready','failed'))`, `error_reason text NULL`, `requested_at timestamptz DEFAULT now()`, `updated_at timestamptz DEFAULT now()`. **Unique on `discovery_id` only** (one voiceover per discovery, regardless of requested model/voice). Indexes on `(user_id, discovery_id)` and `(status, updated_at)`. RLS: owner read/write; service_role full.
  - `voice_inventory` table: `id uuid PK DEFAULT gen_random_uuid()`, `provider text NOT NULL CHECK (IN ('fish'))`, `tts_model text NOT NULL DEFAULT 's1'`, `voice_model_id text NOT NULL`, `display_name text NOT NULL`, `created_at timestamptz DEFAULT now()`. Unique `(provider, tts_model, voice_model_id)`.
  - No backfill; legacy WAV/kitten assets removed/not supported.
- **Storage layout**
  - Bucket: continue `voiceovers`.
  - Object path: `voiceovers/{discoveryId}/fish-{ttsModel}-{voiceModelId}.mp3` (path chosen on the first request; subsequent requests return the existing object even if they specify a different voice/model).
  - Persist the exact stored `file_name` (with extension) and `file_extension` in `discovery_voiceovers` so the client can fetch deterministically.
  - Once a voiceover exists for a `discovery_id`, never create or overwrite another object; the Edge Function must return the existing row/object for all future calls regardless of requested voice/model.
- **Triggers / orchestration**
  - Auto path: after Ask AI v7 emits the `complete` event, the mobile app calls the Voiceover Edge Function (authenticated user JWT) with the chosen voice; function charges 1 credit, generates audio, refunds on failure. The very first request locks in the stored `tts_model`/`voice_model_id`; later requests return the existing row even if they ask for a different voice/model.
  - Manual path: user taps the existing detail button; same Voiceover Edge Function and payload; function enforces one row per discovery (ignoring voice/model on subsequent calls).
  - Dedup/state: enforce a single row per `discovery_id` (DB unique index plus Edge check). Edge logic: if `ready`, return; if `processing` and `updated_at` ≤1m, return; if `processing` stale (>1m), re-run Fish using the stored voice/model without charging another credit; if `failed`, charge a new credit (previous attempt already refunded) and re-run Fish with the stored voice/model.
  - Function fetches discovery `description` only by `discovery_id` (no client-supplied text, no title/short description).
  - Retries: exponential backoff on Fish Audio 429/5xx only for the first run of a new row. On terminal failure set `failed` and refund credit.
- **Credit accounting**
  - Voiceover Edge Function charges 1 credit per request (auto or manual) with transactional decrement; on failure, refunds the credit and marks `failed`, mirroring ask-ai-v7 refund semantics.
  - Re-running a `failed` row consumes a new credit (prior attempt was refunded); re-running a stale `processing` row does not consume a new credit. The first insert path is transactional: insert `processing` row → consume credit → commit; if credit fails, the insert rolls back (no stuck `processing` row, no charge). Unique constraint + transaction avoid double-charges; the client also prevents concurrent requests for the same discovery while a call is in flight.
  - Discovery creation credit remains in Ask AI v7; voiceover credit is separate.
  - Idempotency via unique constraint + transaction to avoid double-charges; subsequent calls against an existing row follow the stale/failed rules above.
  - Voiceover credit RPCs mirror ask-ai-v7 patterns but return the updated `credit_balance` directly (`consume_credit_for_voiceover` and `refund_credit_for_voiceover` return integer balance) so the Edge Function can include it without an extra query.
  - Credit RPC should mirror `consume_credit_for_discovery` semantics (guard missing `user_credits`, raise `insufficient_credits` consistently) and use a matching refund helper for failures.
  - If the Edge Function reports insufficient credits, the client surfaces an alert after completion (not silent).
- **API surface (supabase RPC or Edge Function)**
- `POST /generate-voiceover`: `{ discovery_id, voice_model_id, tts_model? (default s1) }` → validates ownership/credits, runs Fish Audio once if no row exists for the discovery, uploads audio, writes `discovery_voiceovers`, and returns the row payload **plus signed URLs**. No `force` flag; if a row already exists for the discovery, return it and do not create/overwrite anything (ignore new voice/model inputs).
  - `GET /voice-options`: returns available models/voices/options from `voice_inventory` (no fallback; the table must be seeded).
- `GET /discovery-voiceovers`: dedicated RPC to fetch rows for a list of `discovery_id`s (called after each `get_discoveries_with_location`, scoped to currently visible discoveries and any known-failed ones); mirrors the pattern of `get_discoveries_with_location` in structure/ownership checks. For non-ready rows, signed URLs are `null`.
- If an ID has no row, the RPC returns no record; client maps that to status `none`.
- **Client integration**
  - Settings screen: add a new section (under Theme) opening a sheet with auto-toggle and model/voice picker (sourced from `voice_inventory`); stored client-side. Post-onboarding: add a third slide (after the second slide, before location request) with the same voice model picker so every user selects an initial voice.
  - Auto flow: after `complete` event, app calls Voiceover Edge Function with selected `reference_id`, `format: mp3`; blocks additional requests while status is generating.
  - Manual flow: reuse the existing detail button; UI shows states “Create audio” (`none`), “Generating…” (`processing` spinner/disabled), “Download & play” (row ready, not cached), “Play audio” (`ready`), and a softer retry copy for `failed`.
  - Discovery fetch: after each `get_discoveries_with_location`, call `get_discovery_voiceovers` for currently visible discoveries and any known-failed ones to refresh cache. Cache includes `updated_at`; `audio_url` is `null` unless status is `ready`.
  - Failure expiry: if status is `failed` and `updated_at` is older than 1 hour, surface the default “Create audio” state (stop showing failed).
  - Status semantics: `none` (no row yet), `processing` (Edge Function in-flight; retry if stale), `ready` (audio available), `failed` (Edge Function marked failed and will retry on new request); `download` is a client-only state meaning `ready` but not yet cached locally.
  - Playback: only support `.mp3` with naming `fish-{modelId}-{voiceId}.mp3`. Remove WAV/legacy kitten support and the min-ID guard. Signed URLs come from the Edge Function response (happy path) or the voiceovers RPC.
  - Legacy timing artifacts existed but were unused; with Fish we do not create or look for any timing assets. Client needs to stop attempting to load timings entirely.
- **Content generation**
- Text: discovery `description` only. Input is assumed clean as provided (we do not reformat beyond what the client already supplies). Send with `normalize=true`, `chunk_length=200`, `format=mp3`, `tts_model=s1`, relying on Fish defaults for speed/volume (no overrides sent).
- **Resilience & observability**
  - Timeouts and retries on Fish Audio calls with exponential backoff (up to ~5 attempts within ~30 seconds); keep total runtime within the Supabase Edge Function request budget (≈60s). If cumulative backoff plus Fish latency approaches the limit, abort, mark failed, refund.
  - Logging/alerting for auth/quota/text failures using the existing Edge Function logger (no Logflare forwarding).
  - No backfill; legacy assets are not supported.
- Edge timeout/network errors: perform a single RPC `get_discovery_voiceovers` check after the failure; otherwise rely on user retry (no long polling loop).

## Decisions Baked
- Failure cutoff/backoff: 5 attempts with backoff 0/1/2/4/8s (≈15s plus request time); retry on 429/5xx/network, fail fast on other 4xx.
- Stale processing handling: if an existing row is `processing` and `updated_at` >1 minute, Edge Function retries; otherwise returns the existing row.
- Failed handling: if status is `failed`, a new request retries automatically.
- Status model: `none` (no row yet), `processing`, `ready`, `failed`, `missing` (legacy placeholder only until table path is universal).

## Rollout Plan (high level)
1) Acquire Fish Audio API details and keys; define minimal model/voice catalog.  
2) Add schema for `discovery_voiceovers` (with filename/ext/updated_at) and `voice_inventory`; bucket layout `fish-{modelId}-{voiceId}.mp3`; seed `voice_inventory` via one-time SQL migration.  
3) Build Voiceover Edge Function: charges/refunds credits, fetches discovery description by id, validates voice/model against `voice_inventory`, calls Fish, retries per policy (failed or stale processing >1m), uploads audio, writes row, returns row + signed URLs.  
4) Add `GET /discovery-voiceovers` RPC and client integration after `get_discoveries_with_location` (visible + known-failed IDs).  
5) Replace storage-listing client path with table-driven repo; add status-aware single button + player, failure expiry (1h), mp3-only; include `none` state for never-requested items; ensure client no longer expects timings assets.  
6) Settings sheet: auto toggle, voice selection; onboarding includes initial default voice model picker; fetch options from `voice_inventory` (no fallback seed).  
7) QA: credit flows (auto 2 credits total with analysis, manual 1), refunds on failure; single RPC check after timeout/network errors; offline handling.  
8) Remove legacy WAV/kitten support and min-ID guard; no backfill; stop looking for timing assets.

## Voice Inventory
- Table `voice_inventory` with `id UUID PK`, `provider`, `tts_model`, `voice_model_id`, `display_name`, `created_at` default `now()`, unique `(provider, tts_model, voice_model_id)`.
- Provider fixed to `fish`, `tts_model` fixed to `s1` for v1.
- Seed (no fallback):
  - Adrian → `bf322df2096a46f18c579d0baa36f41d`
  - Sarah → `933563129e564b19a115bedd57b7406a`
  - Ethan → `536d3a5e000945adb7038665781a4aca`
  - Laura → `e3cd384158934cc9a01029cd7d278634`
- Edge Function validates requested `tts_model/voice_model_id` against inventory; reject unknown pairs with 422.

## Deduplication & Retry Rules
- No `force` parameter. On request, the Edge Function must check `discovery_voiceovers` before doing any work:
  - If any row exists for the `discovery_id` and is `ready`, return it (no new credit).
  - If row is `processing` and `updated_at` ≤1m, return it (no new credit).
  - If row is `processing` but stale (>1m), mark it `processing` again (bump `updated_at`) and re-run Fish with the stored voice/model (no new credit).
  - If row is `failed`, mark it `processing` again, charge a new credit (previous attempt was refunded), and re-run Fish with the stored voice/model.
  - If no row exists, insert a `processing` row, charge a credit, run Fish, and update to `ready`/`failed`. Unique `discovery_id` enforces the single-row rule. No background cleanup; failed/processing rows persist until explicitly handled later.

## Status Semantics
- `none`: no row yet (RPC returns no record); UI shows “Create audio”.
- `processing`: Edge Function in-flight (initial or re-run of stale/failed).
- `ready`: audio available; may be client-local “download” substate.
- `failed`: failed; subsequent requests re-run with credit (after refund) using stored voice/model.
- `missing`: legacy placeholder (should not occur once table/RPC path used).

## Edge Function Contract (draft)
- `POST /generate-voiceover` (auth required, same credit flow as ask-ai-v7):
  - Body: `{ discovery_id: number, voice_model_id: string, tts_model?: string }`
  - Success 200: row fields plus `audio_url`, `audio_url_expires_at` (TTL 7d; `audio_url = null` unless status is `ready`), and the current `credit_balance`. Dedup/retry rules: single row per `discovery_id` enforced by DB unique index. If row is `ready`, return; if `processing` and `updated_at` ≤1m, return; if `processing` stale (>1m), mark `processing` and re-run Fish (no new credit); if `failed`, mark `processing`, charge a new credit, and re-run Fish using stored voice/model; reuse existing storage key.
  - Errors: 401/403 auth failure; 402 insufficient credits (match ask-ai-v7 handling/message); 404 discovery not found/unauthorized; 422 invalid voice/model; 429 upstream throttle; 500 generic; 502/503 upstream Fish failure.
  - Logging: use shared logger; mask IDs; include Fish error bodies in masked logs only; no prosody inputs accepted.
- Response signals: include `credit_balance` so the client can refresh credits without `existing/was_refunded`. Keep `was_refunded` only when a refund occurred in this call (else false) for clarity; `existing` is no longer required.

## RPC: get_discovery_voiceovers (mirror get_discoveries_with_location pattern)
- Signature: `get_discovery_voiceovers(p_discovery_ids bigint[])` SECURITY DEFINER.
- Filters by `user_id = auth.uid()` and `discovery_id IN (...)`.
- Returns: `id, discovery_id, user_id, provider, tts_model, voice_model_id, file_name, file_extension, status, error_reason, requested_at, updated_at, audio_url (signed, 7d TTL or null if not ready), audio_url_expires_at`.
- Ownership and structure mirror `get_discoveries_with_location`; invoked with the visible + known-failed IDs set.

## Policies and Bucket Access
- `discovery_voiceovers` RLS: enable; policy allowing owners (auth.uid() = user_id) to select/insert/update; service_role full access. Storage bucket `voiceovers` remains private; access via signed URLs only.

## Edge Function Limits
- Supabase Edge Functions run with an HTTP timeout of roughly 60 seconds end-to-end. Our retry plan (5 attempts with 0/1/2/4/8s backoff ≈15s plus Fish latency and upload) must complete well within that window.
- If cumulative Fish latency + upload time approaches ~50 seconds, short-circuit: stop retrying, mark the row `failed`, and refund to avoid request termination mid-flight. Fish call timeout should stay within this budget so rows do not remain `processing` beyond ~1 minute. If the client hits an HTTP timeout/network error, it should issue a single `get_discovery_voiceovers` call to refresh status, then rely on user retry.
- Storage upload time counts toward the timeout; mp3 objects are small, but avoid adding extra waits after upload.

## Text Normalization & Best Practices (Fish)
- Always send `normalize: true`, `chunk_length: 200`, `format: mp3`, `tts_model: s1`.
- No extra length/emptiness checks; discovery descriptions are already ~300 words and treated as valid.
- Strip emojis before sending to Fish; otherwise pass text through unchanged. No prosody input is accepted; Fish defaults apply.
- Advanced controls (emotions/temperature/top_p) are not used in v1.

## Settings Storage
- Store auto-toggle and selected voice/model in `UserDefaults` under a namespaced key (non-sensitive; aligns with existing onboarding/credits caching pattern). Seed defaults via onboarding voice picker.
  - Keys: `voiceover.autoEnabled` (Bool, default false), `voiceover.voiceModelId` (String, default first from inventory/onboarding pick), `voiceover.ttsModel` (String, default `s1`). Prefix `voiceover.` to avoid collisions. Prosody is fixed to Fish defaults (speed 1.0, volume 0 dB) and not configurable.

## SQL Sketch
```sql
-- discovery_voiceovers
CREATE TABLE public.discovery_voiceovers (
  id bigserial PRIMARY KEY,
  discovery_id bigint NOT NULL REFERENCES public.discoveries(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  provider text NOT NULL CHECK (provider IN ('fish')),
  tts_model text NOT NULL DEFAULT 's1',
  voice_model_id text NOT NULL,
  file_name text NOT NULL,
  file_extension text NOT NULL DEFAULT 'mp3',
  status text NOT NULL CHECK (status IN ('processing','ready','failed')),
  error_reason text NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX discovery_voiceovers_discovery_idx
  ON public.discovery_voiceovers (discovery_id);
CREATE INDEX discovery_voiceovers_user_discovery_idx
  ON public.discovery_voiceovers (user_id, discovery_id);
CREATE INDEX discovery_voiceovers_status_updated_idx
  ON public.discovery_voiceovers (status, updated_at);

-- voice_inventory
CREATE TABLE public.voice_inventory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL CHECK (provider IN ('fish')),
  tts_model text NOT NULL DEFAULT 's1',
  voice_model_id text NOT NULL,
  display_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX voice_inventory_provider_model_voice_idx
  ON public.voice_inventory (provider, tts_model, voice_model_id);
```

## Fish default voices (Adrian, Sarah, Laura, Ethan)
- Minimal fields to store: `provider: fish`, `tts_model: s1`, `voice_model_id`, `display_name` (see `docs/fish-voice-inventory-snapshot.json`).

## Notes on bitrate
- Fish offers mp3 bitrates (commonly 64/128/192 kbps). Higher bitrate improves fidelity and reduces artifacts but increases file size and download time; lower bitrate saves bandwidth at the cost of quality. We will use Fish defaults unless a later product decision requests a specific tradeoff.
