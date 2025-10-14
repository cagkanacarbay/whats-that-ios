# Data & Integration Map

The native iOS implementation will continue to use the existing Supabase backend, storage buckets, and third-party services. This document summarizes the current contracts that must be preserved.

---

## Supabase Database Tables

### `discoveries`
- **Purpose:** Stores each AI analysis result.
- **Key Columns:** `id`, `user_id`, `image_url`, `title`, `short_description`, `description`, `analysis` (full streamed body), `model`, `location` (PostGIS Point), `country`, `locality`, `street_name`, `closest_place`, `system_prompt_version`, `user_prompt_version`, `created_at`.
- **Source:** Populated exclusively by Edge Function `ask-ai-v7` after successful AI run.
- **Clients:** Discovery list/detail, voiceover scheduler, audio player, share/deep-link surfaces.

### `user_credits`
- **Purpose:** Tracks current available “Discovery Credits” per user.
- **Key Columns:** `user_id` (PK / FK to `auth.users`), `credit_balance`, timestamps.
- **Clients:** CreditContext, backend RPCs (`grant_initial_credits`, `consume_credit_for_discovery`, `refund_credit`).

### `credit_transactions`
- **Purpose:** Audit log for credit balance changes.
- **Key Columns:** `id`, `user_id`, `amount`, `transaction_type` (`INITIAL`, `PURCHASE`, `USAGE`, `ADJUSTMENT`), `description`, `platform`, `product_id`, `store_transaction_id`, `validation_status`, `discovery_id`, `created_at`.
- **Clients:** Edge Function `validate-receipt`, RPCs invoked during AI runs, refund logic, potential analytics.

### `push_tokens`
- **Purpose:** Stores Expo push tokens per user/device.
- **Key Columns:** `user_id`, `token`, `platform`, `device_id`, `updated_at`, `last_active`.
- **Clients:** `registerForPushNotificationsAsync` (client), `ask-ai-v7` (server) for completion notifications.

### Auth Metadata
- Supabase Auth stores email/password and OAuth identities. The app relies on user metadata to differentiate email-provider accounts before enabling password reset.

---

## Supabase Edge Functions

| Function | Responsibility | Inputs | Outputs / Side Effects |
|----------|----------------|--------|------------------------|
| `ask-ai-v7` | Primary discovery pipeline: validates session, consumes credits, enriches prompt with location & history, streams OpenAI GPT-5-mini response, uploads image to storage, inserts discovery, triggers push notification | Bearer auth header, `base64Image`, optional `location`, optional `nearbyPlaces`, optional `pushToken`, optional `customContext` | SSE stream (`status`, `token`, `metadata`, `complete`, `error`). Inserts into `discoveries`, updates credits, stores image, optionally refunds credit on error |
| `ask-ai-v6`, `ask-ai-v5` | Legacy pipelines kept for fallback/testing | Similar payload to v7 | Non-streaming JSON responses; not used by current client |
| `nearby-places` | Wraps Google Places API to fetch POIs around coordinates and caches results | Bearer auth, `{ latitude, longitude, radius }` | JSON list of places used to supply AI context |
| `validate-receipt` | iOS receipt verification: posts to Apple endpoints, checks `credit_transactions` idempotency, grants credits via RPC | Bearer auth, `{ platform, receiptData, productId, storeTransactionId }` | `{ success, message }`, inserts credit transactions, updates balance |
| `reset-password` | Handles Supabase password recovery deep links (legacy) | Query parameters from Supabase | Issues redirects to app scheme |

Edge functions expect Supabase service role environment variables (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`) and, for AI, `OPENAI_API_KEY`, plus Google Maps & Apple secrets where applicable.

---

## Storage Buckets

| Bucket | Purpose | Access Pattern |
|--------|---------|----------------|
| `discovery_images` | Stores uploaded photos tied to discoveries. Files keyed by `userId/timestamp.jpg`. | Client generates signed URLs via Supabase Storage API (`DiscoveryContext` caching). `ask-ai-v7` uploads directly during processing. |
| `voiceovers` | Stores AI narration audio (`.wav`) and timing JSON (`.json`) keyed by `discoveryId/model`. | Client downloads via signed URLs, caches locally (`DiscoveryContext.ensureVoiceoverAsset`). |

Signed URLs generally expire after 7 days (`STORAGE_CONSTANTS.SIGNED_URL_EXPIRY_SECONDS`), so the iOS app must refresh or prefetch as needed.

---

## RPCs & Database Functions

- `grant_initial_credits(p_user_id, p_amount)` – idempotent setup granting starter credits.
- `add_credits_after_validation(...)` – used by receipt validation to issue credits and log transactions.
- `consume_credit_for_discovery(p_user_id, p_credits_to_consume)` – atomic decrement with insufficient-credit guard.
- `refund_credit(p_user_id, p_credits_to_refund)` – used by `ask-ai-v7` when analysis fails after consumption.
- `get_discoveries_with_location(p_limit, p_last_id)` – paginated fetch used by discovery list (and future map view).

All RPCs are invoked via Supabase REST interface with session-based authorization.

---

## External Services & APIs

- **OpenAI Responses API** (`gpt-5-mini` streaming) – provides narrative analysis; invoked server-side from `ask-ai-v7`.
- **Google Places API** – called server-side (service role) for context enrichment.
- **Expo Push API** – called server-side to notify users when a discovery finishes.
- **Apple IAP verification endpoints** – used in `validate-receipt` Edge Function.
- **Supabase Swift client** (planned) – the native app should reuse Supabase auth/storage/REST endpoints. For SSE streaming, `URLSession` + manual parser will hit `https://<project>.functions.supabase.co/ask-ai-v7`.

---

## Environment & Configuration Requirements

Client-side (Expo) configuration currently uses:
- `EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_ANON_KEY`
- `EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID` for Google auth
- `EXPO_PUBLIC_VALIDATE_RECEIPT_FUNCTION` (implicit through Supabase functions)
- `IOS_BUNDLE_ID`, `APPLE_SHARED_SECRET` (server-side)
- `GOOGLE_MAPS_API_KEY`, `OPENAI_API_KEY`

For the Swift project:
- Store secrets in xcconfigs / Build Settings (never in source).
- Bundle IDs must match existing receipt validation expectations.
- Push notifications require APNs certificates and device token exchange to Supabase (replace Expo push with APNs once running on device; simulator plan uses debug tokens or mocked completion events).
- StoreKit 2 product IDs must match current Supabase product mapping in `_shared/Products.ts`.

---

## Data Compatibility Considerations

- Legacy discoveries (< ID 868) lack voiceover assets; current client short-circuits. Native app must provide similar UX (graceful missing-state).
- `analysis` field contains full streamed Markdown plus metadata JSON sections—important for future features (e.g., feedback). Maintain parsing logic or server-provided metadata.
- Credit transactions rely on `store_transaction_id` for idempotency; the iOS implementation must persist and pass Apple’s `original_transaction_id`.
- Push token lifecycle: ensure stale tokens are cleaned up if APNs rejects them; current implementation logs but does not delete invalid tokens.

Maintaining these contracts ensures the new iOS client can launch without backend changes and avoids data migrations.
