# Nearby Places Caching & Prompt Enrichment Plan

## Problem Statement
- iOS needs a deterministic confirm-stage pipeline: as soon as we have coordinates on the confirm image screen, check cache; if not covered, immediately call the `nearby-places` Edge Function; when nearby data is ready (cache or server), call `ask-ai-v7`.
- Nearby-places cache entries are fine to reuse for up to 7 days; we prune entries older than TTL and keep at most 50 snapshots.
- Background live tracking can still prewarm the cache, but confirm-stage behavior must not rely on it.
- Reference RN code lives at `../whats-that`; compare `contexts/LocationContext.tsx` and `components/custom/AskAI*.tsx` for inspiration only.

## Objectives & Success Criteria
- At confirm stage, begin nearby-places preparation immediately once coordinates are available.
- Reuse cached POIs when within reuse distance; otherwise make a server call, then call `ask-ai-v7` with nearby attached.
- Include distance-from-origin context so prompts can reason about proximity.
- Bound network usage with cache re-use; background tracking keeps its debounce.
- Single source of truth for thresholds in `NearbyPlacesConfig.swift`.
- Cache retention: TTL 7 days, max 50 snapshots.

## Reference Implementation Notes
- **RN Location lifecycle**
  - `LocationProvider` kicks in after Supabase session exists and onboarding flags (`hasSeenTeaser`, `hasDonePostOnboard`) are true, otherwise it defers requests (`contexts/LocationContext.tsx:56-90`).
  - Uses `Location.watchPositionAsync` with `accuracy: High`, `distanceInterval: 250`, `timeInterval: 60000` to throttle native updates and writes each fix to `locationEntries` keyed by incrementing IDs (`contexts/LocationContext.tsx:123-188`).
  - On app foreground, it re-runs `startLocationUpdates`; on sign-out it clears state (`contexts/LocationContext.tsx:200-237`).
  - Camera flow reuses last known entry; library flow adds EXIF-derived entries via `addLocationEntry` (`hooks/useInitiateImageFlow.ts:56-99`).
- **RN Nearby fetch path**
  - `fetchNearbyPlaces` invokes Supabase `nearby-places` with `{ latitude, longitude, radius: 250 }`, caches the response on the corresponding entry, and records empty arrays on error to avoid refetch loops (`contexts/LocationContext.tsx:250-324`).
  - Confirm/analysis components check `entry.nearbyPlaces`; absent data triggers a fetch before calling `ask-ai` (`components/custom/AskAI.tsx:327-343`, `components/custom/AskAIStreaming.tsx:722-741`).
- **Prompt payload**
  - RN sends `{ location, nearbyPlaces }` directly to `ask-ai-*` and leaves it to the Edge Function to interpret (`components/custom/AskAI.tsx:369-375`).
- **Observed gaps**
  - No reuse once the user moves beyond the cached entry; no dedupe across previous sessions; distance context is absent. These are the enhancements this document codifies for the iOS port.

## Functional Requirements
- **Configuration**
  - Centralize tunables in `NearbyPlacesConfig` (distance threshold, debounce interval, cache TTL, max entries, Core Location `distanceFilter`, etc.).
  - Support remote overrides in the future (e.g., feature flag) but default to compile-time constants.
- **Location tracking (app‑wide)**
  - Begin sampling as soon as a signed-in session exists and the user completes onboarding.
  - Start (or resume) tracking when the app enters foreground. Immediately request a one‑shot fresh fix on foreground to seed the coordinator and perform an immediate cache check.
  - Maintain continuous tracking while the app is active (independent of the camera flow). Do not tie starting/stopping tracking to the camera flow.
  - Maintain a rolling history of location snapshots (lat/long, timestamp, horizontal accuracy).
  - Snapshot TTL is 7 days; prune entries older than TTL and when exceeding 50 snapshots.
- **Nearby places fetch**
  - For background tracking (pre‑warm): when movement ≥ `distanceThresholdMeters` (default 250 m) from the last fetch centroid, consider invoking `nearby-places`.
  - Debounce rapid movement using a configurable minimum interval between fetches (default 30 s) even if the user crosses the distance threshold.
  - Cache payloads keyed by geohash/centroid; attach metadata (fetch time, radius, source location).
  - Confirm-stage path (just‑in‑time): if coordinates are present and cache lookup misses, initiate the `nearby-places` fetch and wait up to 15 seconds before proceeding to analysis. On failure or timeout, proceed without nearby.
- **Triggering logic**
  - Foreground: when the app enters `active`, request a fresh location (one‑shot) immediately and perform a cache lookup; then continue tracking while the app is active.
  - Continuous updates: rely on `CLLocationManager` updates with a `distanceFilter` (default 100 m) and appropriate `desiredAccuracy`; periodically re‑evaluate based on `fetchDebounceInterval` (default 30 s) to determine fetch eligibility.
  - Confirm-stage deterministic path: as soon as coordinates exist, do cache lookup; on miss, immediately call `nearby-places` and wait (up to 15 s) for response before calling `ask-ai-v7`. If coordinates are unavailable (no EXIF and OS location denied/unavailable), skip nearby and proceed to analysis.
  - Camera flow: when the camera flow begins, request a fresh location fix immediately to reduce confirm‑time latency. This fresh‑fix request is separate from (and does not control) continuous app‑wide tracking.
- **Re-use logic**
  - When preparing confirmation state, choose the cached POI set whose origin/centroid is within the configured reuse distance only (default 250 m) and whose age < 7 days.
  - If multiple caches qualify, select the closest one (minimum distance to the current fix).
  - Persist cache across sessions; evict beyond 50 snapshots or older than 7 days.
- **Prompt packaging**
  - Include `nearbyPlaces` array plus `nearbyPlacesContext` (distance summary already produced by the coordinator) when available.
  - When `nearbyPlaces` are present, coordinates must also be included in the nested `location.coords` payload. Do not send `nearbyPlaces` without coordinates.
  - Expose instrumentation hooks so `ask-ai-v7` payload logging shows cache usage (`hit`, `miss`, `stale`).
- **User privacy & controls**
  - Respect OS permissions; stop tracking on sign-out or revocation.
  - Automatically evaluate availability when the app opens; if no cached snapshot falls within radius, fetch immediately. No manual refresh UI required.

## Proposed Architecture
- **CoreLocation tracking**
  - App lifecycle: on foreground, request a one‑shot fresh fix and start/resume continuous updates.
  - Streams `DiscoveryLocationSample`s; background fetches are governed by movement and debounce rules.
- **NearbyPlacesCacheStore**
  - Disk-backed list of `NearbyPlacesSnapshot`s with TTL (7 days) and max size (50). Best-fit lookup uses reuse distance and snapshot radius.
- **NearbyPlacesFetcher**
  - Calls Supabase `nearby-places` with the fetch radius (server-side search radius).
- **NearbyPlacesCoordinator**
  - Performs cache lookup and, on miss, initiates server fetch. Confirm-stage path always fetches on miss and proceeds to ask‑ai only after nearby is ready (up to the 15 s timeout).
- **Discovery flow integration**
  - Confirm stage triggers nearby‑places preparation as soon as coordinates are available; `DiscoveryAnalysisPayload` includes `location.nearbyPlaces` and `location.nearbyPlacesContext`.
  - Camera flow issues an immediate fresh‑fix request for location (not for nearby places); nearby fetching follows the reuse/distance/debounce rules independently.
- **Telemetry**
  - Emit `cacheHit`, `cacheMiss`, `fetchStarted`, `fetchSucceeded`, `fetchFailed` events for observability.

## Data Flow Summary
1. App enters foreground → request one‑shot fresh fix → immediate cache lookup; start/resume continuous updates.
2. Continuous CL updates while app is active → coordinator may server‑fetch based on movement and debounce; cache updated.
3. Confirm page obtains coordinates → do cache lookup; on miss, immediately call `nearby-places` and wait (up to 15 s).
4. Begin analyzing UI state immediately after the user taps Confirm, but delay the `ask-ai-v7` request until nearby is ready or the timeout elapses.
5. Build nested `location` payload with coords + nearbyPlaces + nearbyPlacesContext when available; otherwise omit nearby and proceed.
6. User sees a single loading stage while nearby (if needed) and ask‑ai complete.
7. Cache prunes entries older than 7 days and trims to 50 snapshots.

## Implementation Tasks
- Introduce domain models (`DiscoveryLocationSample`, `NearbyPlacesSnapshot`, `NearbyPlacesContext`) inside `WhatsThatDomain`.
- Add infrastructure services for location streaming and caching under `WhatsThatInfrastructure/Services/Location`.
- Update dependency container to inject new services into `DiscoveryCreationFlowViewModel`.
- Extend confirmation state (`DiscoveryConfirmationState`) to carry `nearbyPlaces` and context summary.
- Modify Supabase client to serialize additional payload fields and update tests/mocks accordingly.
- Mirror RN behavior for onboarding/on-auth gating while adding enhanced deduplication logic.
- Add diagnostics: debug panel/logging command to inspect cache contents for QA.
 - Adjust cache selection logic to use the configured reuse distance only (ignore snapshot radius for selection).
 - In the confirm flow, if coordinates exist and cache miss occurs, call `prepareNearbyPlaces` and wait up to 15 s before sending `ask-ai-v7`. If fetch fails or times out, proceed without nearby.
 - Ensure payload always includes coordinates alongside `nearbyPlaces` when present.

## Open Questions
None at this time.

## Next Steps
- Review design with domain/infrastructure owners.
- Define telemetry schema and thresholds (fetch radius 500 m, reuse distance 250 m, debounce 30 s, TTL 7 days)—adjust after field testing.
- Prototype `NearbyPlacesCacheStore` with geohash indexing; add unit tests to cover hit/miss scenarios.
- Integrate into discovery flow behind a feature flag for staged rollout.
