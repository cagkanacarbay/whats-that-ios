# Fish Audio TTS Integration Plan

## Goals
- Replace the current webhook + server-hosted TTS model with Fish Audio for all discovery audio generation.
- Trigger TTS via a new Voiceover Edge Function called by the client: auto-generate right after Ask AI v7 returns text when the user has auto enabled (2 credits total), or on-demand later (1 credit).
- Allow per-user defaults and per-discovery override for auto-TTS and preferred voice/model/prosody settings supplied in each call (stored client-side).
- Persist audio and metadata in Supabase storage/DB so the app can stream via signed URLs, expose pending/error states, and respect credit/refund rules aligned with existing analysis flows.

## Current State (app + backend)
- Client playback currently lists storage objects via `SupabaseVoiceoverRepository`; this will be removed in favor of table-driven lookups + Edge Function response. Legacy WAV/kitten assets and min-ID guard will be dropped.
- Discoveries table no longer stores voiceover columns; playback moves to `discovery_voiceovers` + storage with signed URLs.
- App shows a voiceover button only when an asset exists or an error occurred; missing assets hide the control (no pending state today). New UI will surface processing/ready/download/failed-with-retry on the same button.
- Credits: discovery analysis decrements 1 credit on completion; voiceover credit will be 1 (auto/manual) via the Edge Function with refund on failure.
- No user setting for TTS yet; will add a settings sheet for auto toggle + voice/prosody selection.

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
  - `latency`: `balanced` (per decision)
  - `prosody`: `{ speed: 0.5–2.0, volume: -20..20 }`
  - Optional we won’t use now: `temperature`, `top_p`, `references` (for on-the-fly cloning), emotion markers
- Response: binary audio stream in requested format. We upload to storage.
- Streaming/WebSocket exists but out of scope for this flow.

## Proposed Architecture
- **Data model**
  - `discovery_voiceovers` table: `id bigserial PK`, `discovery_id bigint NOT NULL` FK → discoveries ON DELETE CASCADE, `user_id uuid NOT NULL` FK → auth.users, `provider text NOT NULL CHECK (IN ('fish'))`, `tts_model text NOT NULL DEFAULT 's1'`, `voice_model_id text NOT NULL`, `file_name text NOT NULL` (includes extension), `file_extension text NOT NULL DEFAULT 'mp3'`, `status text NOT NULL CHECK (IN ('processing','ready','failed'))`, `error_reason text NULL`, `requested_at timestamptz DEFAULT now()`, `updated_at timestamptz DEFAULT now()`. Unique `(discovery_id, tts_model, voice_model_id)`. Indexes on `(user_id, discovery_id)` and `(status, updated_at)`. RLS: owner read/write; service_role full.
  - `voice_inventory` table: `id uuid PK DEFAULT gen_random_uuid()`, `provider text NOT NULL CHECK (IN ('fish'))`, `tts_model text NOT NULL DEFAULT 's1'`, `voice_model_id text NOT NULL`, `display_name text NOT NULL`, `created_at timestamptz DEFAULT now()`. Unique `(provider, tts_model, voice_model_id)`.
  - No backfill; legacy WAV/kitten assets removed/not supported.
- **Storage layout**
  - Bucket: continue `voiceovers`.
  - Object path: `voiceovers/{discoveryId}/fish-{ttsModel}-{voiceModelId}.mp3` (e.g., `fish-s1-933563... .mp3`).
  - Persist the exact stored `file_name` (with extension) and `file_extension` in `discovery_voiceovers` so the client can fetch deterministically.
  - Once a voiceover is `ready`, never overwrite the stored object for that `(discovery_id, tts_model, voice_model_id)`; subsequent calls return the existing row/object. Failed or stale objects may remain in place until a user-initiated retry creates a new row.
- **Triggers / orchestration**
  - Auto path: after Ask AI v7 emits the `complete` event, the mobile app calls the Voiceover Edge Function (authenticated user JWT) with the chosen voice and prosody; function charges 1 credit, generates audio, refunds on failure.
  - Manual path: user taps the existing detail button; same Voiceover Edge Function and payload; function enforces dedup (one active/completed per discovery).
  - Dedup/state: `discovery_voiceovers` row created/updated to `processing` → `ready`/`failed`; unique constraint prevents duplicates; table is the source of truth to block spam/retries and reconcile crashes.
  - Retry policy on existing rows: if status is `failed`, retry immediately; if `processing` and `updated_at` older than 5 minutes, treat as stale, retry, log stale retry; otherwise return the current row (no client `force`).
  - Function fetches discovery `description` only by `discovery_id` (no client-supplied text, no title/short description).
  - Retries: exponential backoff on Fish Audio 429/5xx; up to ~5 attempts within ~30 seconds. On terminal failure set `failed` and refund credit.
- **Credit accounting**
  - Voiceover Edge Function charges 1 credit per request (auto or manual) with transactional decrement; on failure, refunds the credit and marks `failed`.
  - Discovery creation credit remains in Ask AI v7; voiceover credit is separate.
  - Idempotency via unique constraint + transaction to avoid double-charges.
  - If the Edge Function reports insufficient credits, the client surfaces an alert after completion (not silent).
- **API surface (supabase RPC or Edge Function)**
- `POST /voiceovers/request`: `{ discovery_id, voice_model_id, tts_model? (default s1), prosody?, latency? }` → validates ownership/credits, runs Fish Audio, uploads audio, writes `discovery_voiceovers`, and returns the row payload **plus signed URLs**. No `force` flag; dedup handled by server rules below.
  - `GET /voice-options`: returns available models/voices/options from `voice_inventory` (falls back to seeded list if empty).
  - `GET /discovery-voiceovers`: dedicated RPC to fetch rows for a list of `discovery_id`s (called after each `get_discoveries_with_location`, scoped to currently visible discoveries and any known-failed ones); mirrors the pattern of `get_discoveries_with_location` in structure/ownership checks.
- **Client integration**
  - Settings screen: add a new section (under Theme) opening a sheet with auto-toggle, model/voice picker (sourced from `voice_inventory` with fallback to curated seed), prosody speed/volume sliders; stored client-side. Onboarding flow includes an initial default voice model picker so every user selects a starting voice.
  - Auto flow: after `complete` event, app calls Voiceover Edge Function with selected `reference_id`, `prosody`, `format: mp3`, `latency: balanced`; blocks additional requests while status is generating.
  - Manual flow: reuse the existing detail button; UI shows states “Create audio” (`none`), “Generating…” (`processing` spinner/disabled), “Download & play” (row ready, not cached), “Play audio” (`ready`), and a softer retry copy for `failed`.
  - Discovery fetch: after each `get_discoveries_with_location`, call `get_discovery_voiceovers` for currently visible discoveries and any known-failed ones to refresh cache. Cache includes `updated_at`.
  - Failure expiry: if status is `failed` and `updated_at` is older than 1 hour, surface the default “Create audio” state (stop showing failed).
  - Status semantics: `none` (no row yet), `processing` (Edge Function in-flight; retry if stale), `ready` (audio available), `failed` (Edge Function marked failed and will retry on new request); `download` is a client-only state meaning `ready` but not yet cached locally.
  - Playback: only support `.mp3` with naming `fish-{modelId}-{voiceId}.mp3`. Remove WAV/legacy kitten support and the min-ID guard. Signed URLs come from the Edge Function response (happy path) or the voiceovers RPC.
  - Legacy timing artifacts existed but were unused; with Fish we do not create or look for any timing assets. Client needs to stop attempting to load timings entirely.
- **Content generation**
- Text: discovery `description` only. Input is assumed clean as provided (we do not reformat beyond what the client already supplies). Send with `normalize=true`, `chunk_length=200`, `latency=balanced`, `format=mp3`, `tts_model=s1`.
  - Locale/voice: map discovery locale when possible; fallback to user default; block incompatible pairs.
- **Resilience & observability**
  - Timeouts and retries on Fish Audio calls with exponential backoff (up to ~5 attempts within ~30 seconds); keep total runtime within the Supabase Edge Function request budget (≈60s). If cumulative backoff plus Fish latency approaches the limit, abort, mark failed, refund.
  - Logging/alerting for auth/quota/text failures using the existing Edge Function logger (no Logflare forwarding).
  - No backfill; legacy assets are not supported.
  - Client polling fallback: only if the Edge Function fails to return a result, poll `get_discovery_voiceovers` for that discovery for up to ~1 minute with 5-second spacing.

## Decisions Baked
- Failure cutoff/backoff: 5 attempts with backoff 0/1/2/4/8s (≈15s plus request time); retry on 429/5xx/network, fail fast on other 4xx.
- Stale processing handling: if an existing row is `processing` and `updated_at` >5 minutes, Edge Function retries; otherwise returns the existing row.
- Failed handling: if status is `failed`, a new request retries automatically.
- Status model: `none` (no row yet), `processing`, `ready`, `failed`, `missing` (legacy placeholder only until table path is universal).

## Rollout Plan (high level)
1) Acquire Fish Audio API details and keys; define minimal model/voice catalog.  
2) Add schema for `discovery_voiceovers` (with filename/ext/updated_at) and `voice_inventory`; bucket layout `fish-{modelId}-{voiceId}.mp3`; seed `voice_inventory` via one-time SQL migration.  
3) Build Voiceover Edge Function: charges/refunds credits, fetches discovery description by id, validates voice/model against `voice_inventory`, calls Fish, retries per policy (failed or stale processing >5m), uploads audio, writes row, returns row + signed URLs.  
4) Add `GET /discovery-voiceovers` RPC and client integration after `get_discoveries_with_location` (visible + known-failed IDs).  
5) Replace storage-listing client path with table-driven repo; add status-aware single button + player, failure expiry (1h), mp3-only; include `none` state for never-requested items; ensure client no longer expects timings assets.  
6) Settings sheet: auto toggle, voice/prosody selection; onboarding includes initial default voice model picker; fetch options from `voice_inventory` with fallback seed.  
7) QA: credit flows (auto 2 credits total with analysis, manual 1), refunds on failure, retries/poll fallback (1 min, 5s backoff if function response missing), offline handling.  
8) Remove legacy WAV/kitten support and min-ID guard; no backfill; stop looking for timing assets.

## Voice Inventory
- Table `voice_inventory` with `id UUID PK`, `provider`, `tts_model`, `voice_model_id`, `display_name`, `created_at` default `now()`, unique `(provider, tts_model, voice_model_id)`.
- Provider fixed to `fish`, `tts_model` fixed to `s1` for v1, `voice_model_id` is the Fish “model” ID (voice model) like Sarah/Adrian/Ethan/Laura, `display_name` = Fish `title`.
- Seed with curated Fish voices via a one-time SQL migration; settings UI fetches from this table (fallback to baked list if empty) so new voices appear without app update. Snapshot for reference: `docs/fish-voice-inventory-snapshot.json`.
- Edge Function validates requested `tts_model/voice_model_id` against inventory; reject unknown pairs with 422.

## Deduplication & Retry Rules
- No `force` parameter. On request, Edge Function checks `discovery_voiceovers`:
  - If status `failed`: retry immediately.
  - If status `processing` and `updated_at` older than 5 minutes: treat as stale, retry, update timestamps, log stale retry.
  - If status `ready`: return existing row + signed URLs; do not re-render or overwrite storage.
  - Otherwise, return existing row + signed URLs.
  - Unique `(discovery_id, tts_model, voice_model_id)` enforces one active/completed row; transaction handles credit charge/refund. No background cleanup; failed/processing rows may persist until a user-initiated call triggers a retry.

## Status Semantics
- `none`: no row yet; UI shows “Create audio”.
- `processing`: Edge Function in-flight (retry if stale >5m).
- `ready`: audio available; may be client-local “download” substate.
- `failed`: failed; new request retries automatically.
- `missing`: legacy placeholder (should not occur once table/RPC path used).

## Edge Function Contract (draft)
- `POST /voiceovers/request` (auth required, same credit flow as ask-ai-v7):
  - Body: `{ discovery_id: number, voice_model_id: string, tts_model?: string, prosody?: { speed?: number, volume?: number }, latency?: string }
  - Success 200: row fields plus `audio_url` and `audio_url_expires_at` (TTL 7d). If a `processing` row exists and is fresh (<5m), return 200 with existing row and a flag `existing:true` (no new Fish call). If `ready`, always return existing row (no rerun). Returned fields include `provider`, `tts_model`, `voice_model_id`, `file_name`, `file_extension`, status/error timestamps.
  - Errors: 401/403 auth failure; 402 insufficient credits (match ask-ai-v7 handling/message); 404 discovery not found/unauthorized; 422 invalid voice/model; 429 upstream throttle; 500 generic; 502/503 upstream Fish failure.
  - Logging: use shared logger; mask IDs; include Fish error bodies in masked logs only.

## RPC: get_discovery_voiceovers (mirror get_discoveries_with_location pattern)
- Signature: `get_discovery_voiceovers(p_discovery_ids bigint[])` SECURITY DEFINER.
- Filters by `user_id = auth.uid()` and `discovery_id IN (...)`.
- Returns: `id, discovery_id, user_id, provider, tts_model, voice_model_id, file_name, file_extension, status, error_reason, requested_at, updated_at, audio_url (signed, 7d TTL), audio_url_expires_at`.
- Ownership and structure mirror `get_discoveries_with_location`; invoked with the visible + known-failed IDs set.

## Policies and Bucket Access
- `discovery_voiceovers` RLS: enable; policy allowing owners (auth.uid() = user_id) to select/insert/update; service_role full access. Storage bucket `voiceovers` remains private; access via signed URLs only.

## Edge Function Limits
- Supabase Edge Functions run with an HTTP timeout of roughly 60 seconds end-to-end. Our retry plan (5 attempts with 0/1/2/4/8s backoff ≈15s plus Fish latency and upload) must complete well within that window.
- If cumulative Fish latency + upload time approaches the timeout, short-circuit: stop retrying, mark the row `failed`, and refund to avoid request termination mid-flight.
- Storage upload time counts toward the timeout; mp3 objects are small, but avoid adding extra waits after upload.

## Text Normalization & Best Practices (Fish)
- Always send `normalize: true`, `chunk_length: 200`, `latency: balanced`, `format: mp3`, `tts_model: s1`.
- No extra length/emptiness checks; discovery descriptions are already ~300 words and treated as valid.
- Strip emojis before sending to Fish; otherwise pass text through unchanged.
- Emotions/advanced controls: leave at Fish defaults for v1 (no emotions/temperature/top_p toggles yet).

## Settings Storage
- Store auto-toggle, selected voice/model, and prosody ranges in `UserDefaults` under a namespaced key (non-sensitive; aligns with existing onboarding/credits caching pattern). Seed defaults via onboarding voice picker.

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

CREATE UNIQUE INDEX discovery_voiceovers_discovery_model_voice_idx
  ON public.discovery_voiceovers (discovery_id, tts_model, voice_model_id);
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

## Next Inputs Needed
- Decide which advanced controls to expose in v1 vs later (emotions, temperature/top_p, etc.).

## Fish default voices (Adrian, Sarah, Laura, Ethan)
- Minimal fields to store: `provider: fish`, `tts_model: s1`, `voice_model_id`, `display_name` (see `docs/fish-voice-inventory-snapshot.json`).

## Notes on bitrate
- Fish offers mp3 bitrates (commonly 64/128/192 kbps). Higher bitrate improves fidelity and reduces artifacts but increases file size and download time; lower bitrate saves bandwidth at the cost of quality. We will use Fish defaults unless a later product decision requests a specific tradeoff.
