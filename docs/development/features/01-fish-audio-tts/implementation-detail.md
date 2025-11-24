# Fish Audio TTS – Implementation Plan (code-level, corrected)

Concrete, no-more-decisions instructions aligned with the updated plan:
- Single canonical asset per `discovery_id` (first request wins voice/model); retries reuse the stored voice/model only.
- No prosody controls anywhere; Fish defaults are always used (speed 1.0, volume 0 dB) and nothing is stored or sent.
- Edge Function must return existing rows immediately when ready or processing <1m; re-run Fish for `processing` rows older than 1 minute (no extra credit) and charge a new credit to re-run `failed` rows (prior attempt already refunded).
- Voice inventory must be seeded (no client fallback).
- Credit ordering is transactionally safe: insert the `processing` row first, then consume credit; failures roll back the insert. Unique constraint + transaction prevent double-spend; the client also blocks concurrent requests per discovery while a call is in flight.

## 1) Database migrations (Supabase)
Create two migrations after `2025110903_drop_validation_status_from_credit_transactions.sql`:

**2025110904_create_voiceover_tables.sql**
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

CREATE UNIQUE INDEX discovery_voiceovers_dedup_idx
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

-- Keep updated_at fresh
CREATE OR REPLACE FUNCTION public.set_discovery_voiceovers_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;
CREATE TRIGGER discovery_voiceovers_set_updated_at
  BEFORE UPDATE ON public.discovery_voiceovers
  FOR EACH ROW EXECUTE FUNCTION public.set_discovery_voiceovers_updated_at();

-- RLS
ALTER TABLE public.discovery_voiceovers ENABLE ROW LEVEL SECURITY;
CREATE POLICY discovery_voiceovers_select_own ON public.discovery_voiceovers
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY discovery_voiceovers_insert_own ON public.discovery_voiceovers
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY discovery_voiceovers_update_own ON public.discovery_voiceovers
  FOR UPDATE USING (auth.uid() = user_id);

ALTER TABLE public.voice_inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY voice_inventory_select_all ON public.voice_inventory
  FOR SELECT USING (true);

-- Credits (mirror consume_credit_for_discovery guard behavior)
DROP FUNCTION IF EXISTS public.consume_credit_for_voiceover(uuid, integer);
CREATE OR REPLACE FUNCTION public.consume_credit_for_voiceover(
  p_user_id uuid,
  p_credits_to_consume integer DEFAULT 1
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_current_balance INTEGER; BEGIN
  UPDATE public.user_credits
    SET credit_balance = credit_balance - p_credits_to_consume,
        updated_at = now()
    WHERE user_id = p_user_id AND credit_balance >= p_credits_to_consume
    RETURNING credit_balance INTO v_current_balance;

  IF v_current_balance IS NULL THEN
    SELECT uc.credit_balance INTO v_current_balance FROM public.user_credits uc WHERE uc.user_id = p_user_id;
    IF v_current_balance IS NULL THEN
      RAISE EXCEPTION 'User not found: %', p_user_id;
    ELSE
      RAISE EXCEPTION 'insufficient_credits';
    END IF;
  END IF;

  INSERT INTO public.credit_transactions (user_id, transaction_type, amount, description)
    VALUES (p_user_id, 'USAGE', -p_credits_to_consume, 'Credit used for voiceover');

  RETURN v_current_balance;
END; $$;
REVOKE ALL ON FUNCTION public.consume_credit_for_voiceover(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_credit_for_voiceover(uuid, integer) TO service_role;

DROP FUNCTION IF EXISTS public.refund_credit_for_voiceover(uuid, integer);
CREATE OR REPLACE FUNCTION public.refund_credit_for_voiceover(
  p_user_id uuid,
  p_credits_to_refund integer DEFAULT 1
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_current_balance INTEGER; BEGIN
  UPDATE public.user_credits
    SET credit_balance = credit_balance + p_credits_to_refund,
        updated_at = now()
    WHERE user_id = p_user_id
    RETURNING credit_balance INTO v_current_balance;

  INSERT INTO public.credit_transactions (user_id, transaction_type, amount, description)
    VALUES (p_user_id, 'REFUND', p_credits_to_refund, 'Refund after failed voiceover');

  RETURN v_current_balance;
END; $$;
REVOKE ALL ON FUNCTION public.refund_credit_for_voiceover(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refund_credit_for_voiceover(uuid, integer) TO service_role;

-- Atomic start (insert only if absent; never updates existing rows)
DROP FUNCTION IF EXISTS public.start_voiceover_request(uuid, bigint, text, text);
CREATE OR REPLACE FUNCTION public.start_voiceover_request(
  p_user_id uuid,
  p_discovery_id bigint,
  p_tts_model text,
  p_voice_model_id text
) RETURNS public.discovery_voiceovers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_existing public.discovery_voiceovers;
  v_now timestamptz := now();
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.discoveries d
    WHERE d.id = p_discovery_id AND d.user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'discovery_not_found_or_unauthorized';
  END IF;

  SELECT * INTO v_existing
  FROM public.discovery_voiceovers
  WHERE discovery_id = p_discovery_id
  FOR UPDATE;

  IF FOUND THEN
    RETURN v_existing;
  END IF;

  INSERT INTO public.discovery_voiceovers (
    discovery_id, user_id, provider, tts_model, voice_model_id,
    file_name, file_extension,
    status, error_reason, requested_at
  )
  VALUES (
    p_discovery_id, p_user_id, 'fish', p_tts_model, p_voice_model_id,
    format('fish-%s-%s.mp3', p_tts_model, p_voice_model_id),
    'mp3', 'processing', NULL, v_now
  )
  RETURNING * INTO v_existing;

  -- Credit consumption happens after insert; if it fails, the transaction rolls back and removes the row.
  PERFORM public.consume_credit_for_voiceover(p_user_id);

  RETURN v_existing;
END;
$$;
REVOKE ALL ON FUNCTION public.start_voiceover_request(uuid, bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_voiceover_request(uuid, bigint, text, text) TO service_role;

-- RPC: get_discovery_voiceovers (audio_url only for ready rows)
DROP FUNCTION IF EXISTS public.get_discovery_voiceovers(bigint[]);
CREATE OR REPLACE FUNCTION public.get_discovery_voiceovers(p_discovery_ids bigint[])
RETURNS TABLE (
  id bigint,
  discovery_id bigint,
  user_id uuid,
  provider text,
  tts_model text,
  voice_model_id text,
  file_name text,
  file_extension text,
  status text,
  error_reason text,
  requested_at timestamptz,
  updated_at timestamptz,
  audio_url text,
  audio_url_expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_ttl_seconds integer := 604800; -- 7d
BEGIN
  RETURN QUERY
  SELECT
    dv.id, dv.discovery_id, dv.user_id, dv.provider, dv.tts_model,
    dv.voice_model_id, dv.file_name, dv.file_extension,
    dv.status, dv.error_reason, dv.requested_at, dv.updated_at,
    CASE WHEN dv.status = 'ready' THEN su.signed_url ELSE NULL END AS audio_url,
    CASE WHEN dv.status = 'ready' THEN su.expires_at ELSE NULL END AS audio_url_expires_at
  FROM public.discovery_voiceovers dv
  LEFT JOIN LATERAL storage.create_signed_url(
    'voiceovers',
    format('%s/%s', dv.discovery_id, dv.file_name),
    v_ttl_seconds
  ) AS su(signed_url text, expires_at timestamptz) ON dv.status = 'ready'
  WHERE dv.user_id = auth.uid()
    AND dv.discovery_id = ANY(p_discovery_ids);
END;
$$;
REVOKE ALL ON FUNCTION public.get_discovery_voiceovers(bigint[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_discovery_voiceovers(bigint[]) TO authenticated;

-- RPC: get_voice_options (no fallback)
DROP FUNCTION IF EXISTS public.get_voice_options();
CREATE OR REPLACE FUNCTION public.get_voice_options()
RETURNS SETOF public.voice_inventory
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT * FROM public.voice_inventory;
$$;
REVOKE ALL ON FUNCTION public.get_voice_options() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_voice_options() TO authenticated;
```

**2025110905_seed_voice_inventory.sql**
```sql
INSERT INTO public.voice_inventory (provider, tts_model, voice_model_id, display_name) VALUES
  ('fish','s1','bf322df2096a46f18c579d0baa36f41d','Adrian'),
  ('fish','s1','933563129e564b19a115bedd57b7406a','Sarah'),
  ('fish','s1','536d3a5e000945adb7038665781a4aca','Ethan'),
  ('fish','s1','e3cd384158934cc9a01029cd7d278634','Laura')
ON CONFLICT DO NOTHING;
```

## 2) Edge Function: `supabase/functions/generate-voiceover`
- Create folder `supabase/functions/generate-voiceover/` with `deno.json`:
  ```json
  {"tasks":{"start":"deno run --allow-net --allow-env --allow-read index.ts"},"compilerOptions":{"jsx":"react-jsx"}}
  ```
- `index.ts` structure (mirror `ask-ai-v7/index.ts` for logger/CORS/auth and credit error handling):
  1. Imports: `msgpackr` for MessagePack encoding, `createLogger` and `buildCorsHeaders` from `_shared`, `createClient` from supabase-js, `AbortSignal.timeout(50000)`.
  2. Env guard: require `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `FISH_AUDIO_API_KEY`.
  3. Auth: Bearer JWT → `supabaseAdmin.auth.getUser`. 401/403 on failure.
  4. Voice validation: call `rpc('get_voice_options')`, match `tts_model`/`voice_model_id`; 422 on unknown.
  5. Fetch discovery text: `select description from public.discoveries where id = $1 and user_id = $auth` (fail 404 if not found/owned). Use only `description` (no title/short description). Strip emojis before sending to Fish.
6. Dedup + retry window: call `rpc('start_voiceover_request', { p_user_id: user.id, p_discovery_id, p_tts_model: ttsModel, p_voice_model_id: voiceModelId })` (insert `processing` row then charge credit in one transaction behind the unique index on `discovery_id`). If the row already exists: `ready` → return immediately; `processing` and `updated_at` ≤ 1 minute → return immediately; `processing` but stale (>1 minute) → set `status = processing`, bump `updated_at`, and re-run Fish with the stored voice/model without charging another credit; `failed` → set `status = processing`, bump `updated_at`, charge a new credit (previous attempt was refunded), then re-run Fish with stored voice/model. In all cases reuse the stored file name/path.
7. Fish call MessagePack body `{ text, reference_id: voiceModelId, format:'mp3', normalize:true, chunk_length:200, tts_model }`, headers `Content-Type: application/msgpack`, `Authorization: Bearer ...`, `model: ttsModel`. Retry on 429/5xx with backoff `[0,1,2,4,8]` seconds; keep total work within the ~60s Edge budget (stop around 50s to avoid termination).
   - Supabase Edge Functions have ~60s total budget; if cumulative backoff + Fish/upload time approaches ~50s, abort, mark `failed`, and refund to avoid leaving a stuck `processing` row. If the client times out or hits a network error, it should perform a single `get_discovery_voiceovers` call to refresh status, then rely on user retry.
  8. Upload: `voiceovers/{discoveryId}/{file_name}` with `contentType: audio/mpeg`, `upsert: false`; if the object already exists, skip upload and reuse.
9. On success: update row to `ready`, null `error_reason`, sign URL via `createSignedUrl` (7d), return payload + `audio_url`, `audio_url_expires_at`, `credit_balance` (from `consume_credit_for_voiceover`), `was_refunded:false`.
10. On Fish/upload failure: update row to `failed` with `error_reason`, call `rpc('refund_credit_for_voiceover', { p_user_id: user.id, p_credits_to_refund: 1 })` (returns updated balance), return `was_refunded:true`, `audio_url:null`, `credit_balance` (after refund).
11. Response fields: `credit_balance` always included so client can refresh credits without relying on `existing`; `was_refunded` indicates a refund occurred in this call (false otherwise), mirroring ask-ai-v7 patterns but with balance returned inline.
  11. Errors: map 402 for `insufficient_credits`, 404 for missing discovery/ownership, 422 invalid voice, 429/502/503 bubble with `failed`, otherwise 500. CORS headers same as ask-ai-v7.

## 3) Domain models (WhatsThatDomain)
File `native/WhatsThatIOSPackage/Sources/WhatsThatDomain/Discovery/DiscoveryVoiceoverModels.swift`:
- Replace contents (lines 1–40) with:
```swift
public enum DiscoveryVoiceoverStatus: Equatable, Sendable {
    case none
    case processing
    case ready
    case failed
    case missing
}

public struct DiscoveryVoiceoverAsset: Equatable, Sendable {
    public let discoveryId: Int64
    public let status: DiscoveryVoiceoverStatus
    public let audioURL: URL?
    public let provider: String?
    public let ttsModel: String?
    public let voiceModelId: String?
    public let fileName: String?
    public let fileExtension: String?
    public let requestedAt: Date?
    public let updatedAt: Date?
    public let errorReason: String?
    public let wasExistingResponse: Bool
    public let wasRefunded: Bool
}

public protocol DiscoveryVoiceoverRepository: Sendable {
    func fetchVoiceovers(for discoveryIds: [Int64]) async -> [DiscoveryVoiceoverAsset]
    func requestVoiceover(for discoveryId: Int64,
                         voiceModelId: String,
                         ttsModel: String) async -> DiscoveryVoiceoverAsset
}

public struct VoiceModelOption: Equatable, Sendable { public let voiceModelId: String; public let displayName: String; public let ttsModel: String }
public struct VoiceoverPreferences: Equatable, Sendable { public var autoEnabled: Bool; public var voiceModelId: String; public var ttsModel: String }
```

## 4) Data layer: Supabase voiceover repository
File `native/WhatsThatIOSPackage/Sources/WhatsThatData/Repositories/Voiceover/SupabaseVoiceoverRepository.swift`:
- Replace the entire implementation with a client that:
  - Uses the functions base URL helper from `SupabaseDiscoveryAnalysisClient.functionsBaseURL` to build `generate-voiceover` URL.
  - Removes storage listing, timing files, min-ID guard, kitten model arrays.
  - `fetchVoiceovers(for:)` calls RPC `get_discovery_voiceovers` and maps rows → `DiscoveryVoiceoverAsset` with `audioURL` only when not null; set `status` from `status` string (`ready`, `processing`, `failed` → `.ready/.processing/.failed`, otherwise `.missing`), `wasExistingResponse = true`, `wasRefunded = false`. If the RPC returns no row for an ID, emit `.none` for that discovery.
  - `requestVoiceover` POSTs JSON `{ discovery_id, voice_model_id, tts_model }` to `generate-voiceover` with bearer token; maps HTTP 402 to `status = .failed` and `errorReason = "insufficient_credits"` (so UI can surface the credit alert); sets `wasExistingResponse` and `wasRefunded` flags from response; if `audio_url` is null, keep `status` from payload.
  - Caches by `(discoveryId, updatedAt)`; signed URL TTL from response `audio_url_expires_at`.
Update tests in `native/WhatsThatIOSPackage/Tests/WhatsThatDataTests/SupabaseVoiceoverRepositoryTests.swift` to drop WAV/timing cases and assert mapping of `audio_url = null` → `.processing/.failed`.

## 5) Voice inventory + preferences
- Add `VoiceInventoryRepository` (new file under `WhatsThatData`) that calls `get_voice_options` and returns `[VoiceModelOption]`; no fallback seed or bundled resource.
- Add `VoiceoverPreferencesStore` (UserDefaults) storing: `autoEnabled` (Bool), `voiceModelId`, `ttsModel` (default `s1`). Provide `load/save/reset` APIs; prosody is fixed to Fish defaults and not stored.
  - Keys (namespaced): `voiceover.autoEnabled`, `voiceover.voiceModelId`, `voiceover.ttsModel`. Defaults: auto off, ttsModel `s1`, voice seeded from onboarding/first inventory option.

## 6) Playback controller
File `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Shared/Controllers/VoiceoverPlaybackController.swift`:
- Update `PlaybackState` handling to accept `.none/.processing/.ready/.failed/.missing` statuses.
- Add methods:
  - `prefetch(for discoveryIds: [Int64]) async` → `fetchVoiceovers` and populate `assetStates`.
  - `requestVoiceover(for discovery: DiscoverySummary, preferences: VoiceoverPreferences)` that sets state to `.processing`, calls repository `requestVoiceover`, updates `assetStates`, then triggers playback when ready.
- On HTTP timeout/network error from the Edge Function, perform a single `fetchVoiceovers` refresh for the target ID to pick up any late state, then wait for user retry.
- Track a client-only `download` substate when status is `ready` but the file is not cached locally; surface “Download & play” until the first fetch completes.
- In `togglePlayback`, if status is `.none` or `.failed`, call `requestVoiceover`; only play when `.ready` with URL (download-and-play when first fetching).
- Remove timing/min-ID logic and WAV fallbacks. Honor failure expiry: if `status == .failed` and `updatedAt < now - 1h`, treat as `.none` in UI helpers.

## 7) UI updates
- `VoiceoverDetailButton.swift` (around lines 1–110):
  - Allow taps when status is `.none` or `.failed` to trigger `controller.requestVoiceover`.
  - Title/icon mapping: `.none` → “Create audio”/play icon, `.processing` → “Generating…”/spinner, `.ready` → play/pause/resume, `.ready` but not cached → “Download & play”/download icon, `.failed` → “Retry audio”/arrow.clockwise. Disable only while a new request is in-flight.
  - If the request fails with `insufficient_credits`, show the existing credit alert pattern (match ask-ai-v7).
- `DiscoveryDetailView.swift` (lines ~380–470):
  - `shouldShowVoiceoverButton` should return true for `.none/.processing/.ready/.failed` (and when playback failed). Remove the “hide when missing” guard.
  - On `.onAppear`, call `voiceoverController.prefetch(for: [discovery.id])` instead of `ensureMetadata`.
- `DiscoveriesHomeView.swift`: after `viewModel.loadInitialIfNeeded()` and after refresh/pagination, call `voiceoverController.prefetch(for: visibleIds)` where `visibleIds` are the discoveries shown in the grid and any known-failed IDs.
- Post-onboarding: add a third slide (after the second slide, before location request) that shows the same voice model picker as Settings so users choose an initial voice.

## 8) Settings & DI wiring
- `AppDependencyContainer.swift`:
  - Construct `VoiceInventoryRepository` and `VoiceoverPreferencesStore` alongside `SupabaseVoiceoverRepository`.
  - Pass the preferences store and voiceover repository into `VoiceoverPlaybackController` factory (`makeVoiceoverPlaybackController`).
  - Inject the same dependencies into `DiscoveryCreationDependencyProvider` so creation flow can auto-request TTS.
- `SettingsView.swift`: add a “Voiceover” section under Theme that shows current voice model and auto-toggle (no prosody sliders). Use `VoiceInventoryRepository` data (no fallback).

## 9) Auto-TTS after analysis
- In `DiscoveryCreationFlowViewModel.handle(event:)` when handling `.complete` (current lines ~675–705): after optimistic credit decrement, if `VoiceoverPreferences.autoEnabled` is true, call `voiceoverPlaybackController.requestVoiceover` with the new discovery id and preferences.
- Credit handling: mirror `ask-ai-v7` logic—refresh client-side credits from the `credit_balance` returned by the voiceover Edge Function; `was_refunded` only signals a refund occurred in this call.

## 10) Tests
- Add coverage for:
  - `DiscoveryVoiceoverStatus` mapping and failure expiry logic.
  - `SupabaseVoiceoverRepository` mapping of `audio_url = null` to non-ready states and 402 errors.
  - `VoiceoverPreferencesStore` persistence/defaults.
  - `VoiceoverDetailButton` label/icon enablement per status.

## 11) Cleanup
- Delete legacy artifacts: `VoiceoverAssetResolver`, timing extension lookups, WAV/kitten model arrays, `minVoiceoverDiscoveryId`, and any timing asset loading paths.
- Remove status cases `.available/.error` usages; migrate call sites to `.ready/.failed/.processing/.none/.missing`.

## 12) Rollout checklist
- `swift package resolve --package-path native/WhatsThatIOSPackage`
- `USE_REMOTE_DEPS=1 xcodebuild -workspace native/WhatsThatIOS.xcworkspace -scheme WhatsThatIOS -destination 'platform=iOS Simulator,name=iPhone 15' build`
- Manual Edge tests: 200 happy path, 402 insufficient credits (matches ask-ai-v7), 422 invalid voice, 404 unauthorized discovery, 429/502/503 Fish error → status `failed` + refund.
- Client: auto flow (2 credits total with analysis + voice), manual create/play, non-ready rows return null URL, failure expiry (1h); on Edge timeout/network error perform a single RPC `get_discovery_voiceovers` check, otherwise rely on user retry. mp3-only playback, settings persistence.
- Ensure storage upload never overwrites existing ready objects; reruns return existing row.
