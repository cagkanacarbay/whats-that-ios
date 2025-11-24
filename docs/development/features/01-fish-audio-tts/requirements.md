# Fish Audio TTS – Requirements (consolidated)

## Scope & Goals
- [ ] Replace the current webhook + server-hosted TTS with Fish Audio for all discovery audio generation.
- [ ] Use a new Voiceover Edge Function called by the client: auto-run after Ask AI v7 completes when auto is enabled (2 credits total with analysis) or on-demand later (1 credit).
- [ ] Support per-user defaults and per-discovery overrides for auto-TTS, preferred voice/model, and prosody stored client-side.
- [ ] Persist audio plus metadata in Supabase (tables + storage) so the client streams via signed URLs, surfaces pending/error states, and follows the existing credit/refund pattern.

## Fish Audio API Usage
- [x] Endpoint: `POST https://api.fish.audio/v1/tts`; headers: `Authorization: Bearer FISH_AUDIO_API_KEY`, `Content-Type: application/msgpack`, `model: s1` (fixed for v1).
- [ ] Request body (MessagePack): `text` = discovery `description` only, `reference_id` = curated voice/model id, `format` = `mp3`, `chunk_length` 100–300 (default 200), `normalize` = true, `prosody` speed 0.5–2.0 and volume -20..20. (partial)
  - [x] Sends description only, reference_id, format mp3, normalize true, chunk_length 200, tts_model `s1` default.
  - [ ] Does not validate or clamp prosody speed/volume to 0.5–2.0 and -20..20.
- [x] Exclude advanced controls (temperature/top_p/references/emotion markers) for v1.
- [x] Use Fish default mp3 bitrate (64/128/192 available; stick to defaults unless product changes).
- [ ] Strip emojis before sending; otherwise send text as-is. Prosody is not persisted server-side and does not affect the storage path. (partial)
  - [x] Emojis stripped before sending; prosody not persisted and does not affect storage path.
  - [ ] Additional formatting/length check present: text is trimmed and rejected when empty, contrary to “treat description as already valid”.
- [x] Streaming/WebSocket Fish APIs are out of scope.

## Data Model & Storage
- [x] Create `discovery_voiceovers` table with: `id bigserial PK`, `discovery_id bigint` FK → discoveries ON DELETE CASCADE, `user_id uuid` FK → auth.users, `provider text CHECK IN ('fish')`, `tts_model text DEFAULT 's1'`, `voice_model_id text`, `file_name text`, `file_extension text DEFAULT 'mp3'`, `status text CHECK IN ('processing','ready','failed')`, `error_reason text NULL`, `requested_at timestamptz DEFAULT now()`, `updated_at timestamptz DEFAULT now()`, unique on `discovery_id`, indexes `(user_id, discovery_id)` and `(status, updated_at)`, trigger to keep `updated_at` fresh.
- [x] Create `voice_inventory` table with: `id uuid PK DEFAULT gen_random_uuid()`, `provider text CHECK IN ('fish')`, `tts_model text DEFAULT 's1'`, `voice_model_id text`, `display_name text`, `created_at timestamptz DEFAULT now()`, unique `(provider, tts_model, voice_model_id)`.
- [x] Enable RLS: `discovery_voiceovers` owners can select/insert/update; service_role full. `voice_inventory` selectable by all; service_role full.
- [x] Storage bucket `voiceovers`; object path `voiceovers/{discoveryId}/fish-{ttsModel}-{voiceModelId}.mp3`; persist `file_name` and `file_extension`; never create or overwrite a second asset per discovery; bucket stays private with signed URL access only.
- [ ] No backfill; remove legacy WAV/kitten assets, timing artifacts, and min-ID guard. (not done)
  - [ ] Legacy kitten/timing/timing tests remain (see `native/WhatsThatIOSPackage/Tests/WhatsThatDataTests/SupabaseVoiceoverRepositoryTests.swift`); cleanup not applied.

## Credit & Accounting Functions
- [x] Implement `consume_credit_for_voiceover(p_user_id uuid, p_credits_to_consume integer = 1)` with transactional decrement, guards for missing user (`User not found`) or `insufficient_credits`, credit transaction insert, returns updated balance; security definer; service_role only.
- [x] Implement `refund_credit_for_voiceover(p_user_id uuid, p_credits_to_refund integer = 1)` to increment balance, record refund transaction, return updated balance; security definer; service_role only.
- [x] Keep voiceover credit separate from discovery creation; refund on failures; surface insufficient credits to the client (alert).

## RPCs & Helpers
- [x] Implement `start_voiceover_request(p_user_id uuid, p_discovery_id bigint, p_tts_model text, p_voice_model_id text)`: verify discovery ownership; return existing row if present (FOR UPDATE); otherwise insert `processing` row with provider `fish`, `file_name` `fish-{tts_model}-{voice_model_id}.mp3`, `file_extension` `mp3`, `status` `processing`, `error_reason` NULL, `requested_at` now; consume credit immediately after insert; rely on unique `discovery_id`.
- [x] Run helper functions as `SECURITY DEFINER` with empty `search_path`, revoke from PUBLIC, and grant only to service/auth roles; `start_voiceover_request` and credit consumption happen in the same transaction so a credit failure rolls back the insert (no stuck processing rows).
- [x] Implement `get_discovery_voiceovers(p_discovery_ids bigint[])` SECURITY DEFINER: filter by `user_id = auth.uid()` and ids; return row fields plus `audio_url`/`audio_url_expires_at` (signed URL TTL 7d) only when status is `ready`; URLs null otherwise.
- [x] Implement `get_voice_options()` returning all `voice_inventory` rows; no client fallback/seed.

## Edge Function: `generate-voiceover`
- [x] Create Edge Function package under `supabase/functions/generate-voiceover/` with `deno.json` start task and `index.ts` using `msgpackr`, shared logger, and shared CORS helpers (match `ask-ai-v7` scaffolding).
- [x] Enforce environment guards: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `FISH_AUDIO_API_KEY`.
- [x] Authenticate via Bearer JWT → `supabaseAdmin.auth.getUser`; 401/403 on failure.
- [x] Validate voice via `get_voice_options`; reject unknown `tts_model`/`voice_model_id` with 422; require seeded inventory (no fallback).
- [x] Fetch discovery `description` by `discovery_id` for the authenticated user; 404 if not found/owned; do not accept client-supplied text/title.
- [x] Apply dedup/state rules (single row per discovery): ready → return; processing updated_at ≤ 1m → return; processing stale >1m → set processing + bump updated_at, re-run Fish (no new credit); failed → set processing + bump updated_at, charge new credit, re-run Fish with stored voice/model; no row → `start_voiceover_request` to insert processing and charge atomically; always reuse stored `file_name`/path; no overwrite and no `force`.
- [x] Call Fish with MessagePack body `{ text, reference_id: voiceModelId, format:'mp3', normalize:true, chunk_length:200, tts_model }`; headers include `Authorization`, `Content-Type`, `model`; use `AbortSignal.timeout(~50s)` within ~60s Edge budget.
- [x] Retry on Fish 429/5xx/network with backoff [0,1,2,4,8] (~15s plus request time), primarily on the first run of a new row; abort near ~50s cumulative to mark failed and refund to avoid stuck processing.
- [x] Upload to `voiceovers/{discoveryId}/{file_name}` with `contentType: audio/mpeg`, `upsert: false`; if object exists, skip upload and reuse.
- [x] On success: update row to `ready`, clear `error_reason`, sign URL (TTL 7d), return row fields + `audio_url`, `audio_url_expires_at`, `credit_balance` (from consume), `was_refunded: false`.
- [x] On failure: update row to `failed` with `error_reason`, call `refund_credit_for_voiceover`, return `audio_url: null`, `credit_balance` after refund, `was_refunded: true`.
- [x] Error mapping: 401/403 auth failure; 402 insufficient credits; 404 discovery not found/unauthorized; 422 invalid voice/model; 429/502/503 upstream Fish failure; 500 generic. CORS same as `ask-ai-v7`.
- [x] Logging/observability: use shared logger, mask IDs, include Fish error bodies only in masked logs; no Logflare forwarding.
- [ ] On HTTP timeout/network error, client performs a single `get_discovery_voiceovers` refresh; no long polling. (client behavior pending)

## Voice Inventory Requirements
- [x] Fix provider to `fish` and `tts_model` to `s1` for v1.
- [x] Seed values (no fallback): Adrian `bf322df2096a46f18c579d0baa36f41d`; Sarah `933563129e564b19a115bedd57b7406a`; Ethan `536d3a5e000945adb7038665781a4aca`; Laura `e3cd384158934cc9a01029cd7d278634`.
- [x] Edge validation must reject unknown pairs with 422; client must not bundle static seeds.

## Status Model & Semantics
- [x] Support statuses: `none` (no row/RPC record), `processing`, `ready`, `failed`, `missing` (legacy placeholder); client has `download` substate when `ready` but not cached locally.
- [x] Apply failure expiry: if status `failed` and `updated_at` older than 1 hour, UI reverts to `none` (“Create audio”).
- [x] Once a voiceover exists for a discovery, never create/overwrite another; subsequent requests return the existing row/object regardless of requested voice/model.
- [x] No background cleanup jobs; `processing`/`failed` rows persist until retried via the dedup/stale/failed rules.

## Client Data & Repository Requirements
- [x] Supabase voiceover repository builds `generate-voiceover` URL from `SupabaseDiscoveryAnalysisClient.functionsBaseURL`.
- [ ] Remove legacy storage listing/timing paths; rely solely on RPC + Edge responses and signed URLs (mp3 only) for playback. (partial)
  - [x] Legacy storage listing/timing code removed; mp3-only path used.
  - [ ] Repository does not use `get_discovery_voiceovers` RPC; it queries the table directly and signs URLs client-side.
- [ ] `fetchVoiceovers(for:)` calls `get_discovery_voiceovers`; map statuses (`ready/processing/failed` → enum; otherwise `.missing`); when RPC returns no row emit `.none`; keep `audio_url` null as non-ready; set `wasExistingResponse = true`, `wasRefunded = false`. (not done; selects table directly and returns `.missing` on error)
- [x] `requestVoiceover` POSTs `{ discovery_id, voice_model_id, tts_model, prosody }` with bearer token; map HTTP 402 to status `.failed` with `errorReason = "insufficient_credits"`; carry `wasExistingResponse`/`wasRefunded` flags from response; keep payload status when `audio_url` is null; cache by `(discoveryId, updatedAt)` and honor `audio_url_expires_at` TTL.
- [x] Voice inventory repository fetches `get_voice_options` only; no local fallback or bundled inventory.
- [x] Preferences store (UserDefaults): keys `voiceover.autoEnabled`, `voiceover.voiceModelId`, `voiceover.ttsModel`, `voiceover.prosody.speed`, `voiceover.prosody.volume`; defaults auto off, `ttsModel = s1`, speed 1.0, volume 0, voice from onboarding/first inventory; provide load/save/reset.

## Client UX & Playback Requirements
- [x] Settings: add “Voiceover” section under Theme with auto-toggle, voice/model picker (from `voice_inventory`), prosody speed/volume sliders; no fallback options if inventory fetch fails.
- [ ] Onboarding: add a third slide (after the second, before location request) with the same voice picker so every user selects an initial voice. (not present)
- [ ] Auto flow: after discovery creation `complete` event, if auto is enabled, call Edge with selected `reference_id`, `prosody`, `format mp3`; block additional requests while generating. (partial)
  - [x] Auto flow triggers `requestVoiceover` after `.complete` when preferences.autoEnabled and voice set.
  - [ ] Does not refresh credit balance from Edge response or coordinate with playback controller; concurrent request blocking relies only on UI state.
- [x] Manual flow/button states: detail button supports `.none` “Create audio” (tap), `.processing` “Generating…” (spinner/disabled), `.ready` play/pause/resume, `.ready` not cached “Download & play”, `.failed` “Retry audio” (tap); insufficient credits shows existing credit alert pattern.
- [x] Visibility: `shouldShowVoiceoverButton` true for `.none/.processing/.ready/.failed` (and playback failed); remove hide-on-missing behavior.
- [x] Prefetch: after each `get_discoveries_with_location` (initial, refresh, pagination), call `get_discovery_voiceovers` for visible discoveries and known-failed IDs; on discovery detail appear, prefetch for that discovery.
- [ ] Playback controller supports `.none/.processing/.ready/.failed/.missing`; `prefetch(for:)` populates state; `requestVoiceover(for:preferences:)` sets `processing`, calls repository, updates state, auto-plays when ready; on Edge timeout/network error, do one RPC refresh then wait for user retry; track `download` substate for uncached ready assets; `togglePlayback` triggers request when `.none` or `.failed`, plays only when ready with URL; treat failed older than 1h as none. (partial)
  - [x] Supports statuses, prefetch, request flow, download substate, failure expiry (1h), triggers playback when ready.
  - [ ] No special handling for Edge timeout/network errors (no single RPC refresh); `prefetch` uses table query instead of RPC.
- [ ] Format: mp3 only with naming `fish-{modelId}-{voiceId}.mp3`; remove WAV, kitten models, min-ID guard, timing asset lookups, and timing metadata expectations. (partial)
  - [x] mp3-only path and naming are used via file_name from server.
  - [ ] Legacy kitten/timing artifacts remain in tests; removal not completed.
- [ ] Cache downloaded audio locally for reuse; avoid re-downloading ready assets once cached.
- [ ] Playback UX while generating another voiceover:
  - [ ] If a new voiceover finishes while a different one is playing, do not auto-switch playback; keep the current audio playing.
  - [ ] When user switches, audio player UI must reflect the currently playing discovery/voiceover (titles/state/icons) and not show stale state from the previous asset.
- [x] Dependency wiring: `AppDependencyContainer` builds voice inventory repository and preferences store with the voiceover repository, feeds them into `VoiceoverPlaybackController` factories, and injects voiceover dependencies into `DiscoveryCreationDependencyProvider` so creation flow can auto-request TTS.
- [ ] Confirm image selection stage shows an auto-voiceover toggle with credit awareness:
  - [ ] Visual toggle present at confirm stage to enable/disable auto voiceover.
  - [ ] UI copy indicates voiceover consumes 1 credit in addition to discovery creation.
  - [ ] If user has only 1 credit (needed for discovery), disable toggle and on attempt show an alert: “You only have one credit; it will be used for discovery creation. Purchase more credits to enable auto voiceover.”
  - [ ] Alert action navigates to/presents the credits sheet/section so user can buy more credits.

## Credit & Auto-TTS Client Handling
- [x] Auto-TTS runs after Ask AI v7 completes; total cost 2 credits (analysis + voice). Manual TTS costs 1 credit. Rerunning failed consumes a new credit; rerunning stale processing does not.
- [ ] Client refreshes credits from `credit_balance` returned by the voiceover Edge Function; `was_refunded` only signals a refund in the current call. (not done; response credit balance is ignored)
- [x] Prevent concurrent client requests per discovery while a call is in flight. (UI disables during `.processing`)
- [ ] When the Edge Function reports insufficient credits (auto or manual), surface the existing credit alert rather than failing silently. (partial)
  - [x] Manual flow shows alert on `insufficient_credits` error reason.
  - [ ] Auto flow does not surface the alert; voiceover request failure is silent in creation flow.

## Testing & Rollout
- [ ] Acquire Fish Audio API keys/details and confirm the minimal voice catalog before enabling flows. (not verified)
- [x] Add migrations `2025110904_create_voiceover_tables.sql` and `2025110905_seed_voice_inventory.sql` after `2025110903_drop_validation_status_from_credit_transactions.sql`. (implemented as `2025112301_create_voiceover_tables.sql` and `2025112302_seed_voice_inventory.sql` with follow-up fixes)
- [ ] Run build/test: `swift package resolve --package-path native/WhatsThatIOSPackage`; `USE_REMOTE_DEPS=1 xcodebuild -workspace native/WhatsThatIOS.xcworkspace -scheme WhatsThatIOS -destination 'platform=iOS Simulator,name=iPhone 15' build`. (not recorded)
- [ ] Manual Edge tests: 200 happy path; 402 insufficient credits; 422 invalid voice; 404 unauthorized discovery; 429/502/503 Fish failure → status `failed` + refund; uploads never overwrite existing ready objects and reruns return existing rows. (not recorded)
- [ ] Client QA: auto flow (2 credits total), manual create/play, non-ready rows return null URL, failure expiry (1h), timeout/network error followed by single RPC refresh, mp3-only playback, settings persistence, offline handling. (not recorded)
- [ ] Unit/UI tests: status mapping + failure expiry, repository mapping of `audio_url = null` and 402 errors, preferences store persistence/defaults, detail button label/icon enablement per status. (not recorded)

## Cleanup & Removal Requirements
- [ ] Delete legacy artifacts: `VoiceoverAssetResolver`, timing extension lookups, WAV/kitten model arrays, `minVoiceoverDiscoveryId`, and any timing asset loading paths. (not done; tests still reference kitten models and `VoiceoverAssetResolver`)
- [x] Remove status cases `.available/.error`; migrate call sites to `.ready/.failed/.processing/.none/.missing`.
