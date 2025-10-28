# Nearby Places Caching & Prompt Enrichment Plan

## Problem Statement
- iOS port currently captures a single `DiscoveryLocation` per flow and never enriches it with nearby POIs before calling `ask-ai-v7` (`native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/DiscoveryCreationFlowViewModel.swift:223`, `native/WhatsThatIOSPackage/Sources/WhatsThatInfrastructure/Services/Analysis/SupabaseDiscoveryAnalysisClient.swift:126`).
- React Native reference keeps a rolling map of location entries, lazily fetches `nearby-places`, and sends `{ location, nearbyPlaces }` with each request (`contexts/LocationContext.tsx`, `components/custom/AskAI.tsx:327`).
- We need a smarter system that: (1) prewarms POI data before the user confirms, (2) avoids redundant edge-function calls, and (3) surfaces distance between current fix and the cached POI cluster in the analysis payload.
- Reference RN code lives at `../whats-that` relative to this repo root; compare especially `contexts/LocationContext.tsx` and `components/custom/AskAI*.tsx`.

## Objectives & Success Criteria
- Always have either a fresh or cached `nearbyPlaces` payload ready by the time the confirmation screen appears.
- Reuse previously fetched POI batches when the user remains within a configurable radius (default 500 m) or revisits an area.
- When dispatching to `ask-ai-v7`, include both the cached POIs and an explicit “distance from fetch origin” hint so the prompt can clarify proximity.
- Bound network usage: no duplicate `nearby-places` invocation for the same area unless the cache is expired or the user has moved beyond the radius threshold.
- Provide observable metrics (logging/telemetry hooks) so we can monitor cache hit/miss ratios and fetch latency.
- All thresholds (distance, debounce timing, TTL, max cache size) should live in a single configuration source of truth (e.g., `NearbyPlacesConfig.swift`) to make tuning straightforward.

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
- **Location tracking**
  - Begin sampling as soon as a signed-in session exists and user completes onboarding.
  - Maintain a rolling history of location snapshots (lat/long, timestamp, horizontal accuracy).
  - Mark snapshots as stale after configurable TTL (default 15 min) to prevent outdated context.
- **Nearby places fetch**
  - For any new snapshot ≥ `distanceThresholdMeters` (default 500 m) from the nearest cached fetch centroid, enqueue an invocation to `nearby-places`.
  - Debounce rapid movement using a configurable minimum interval between fetches (default 30 s) even if the user crosses the distance threshold.
  - Cache payloads keyed by geohash/centroid; attach metadata (fetch time, radius, source location).
- **Triggering logic**
  - On app launch and every transition to `active`, request a fresh location sample once permissions allow.
  - Rely on `CLLocationManager` updates with a `distanceFilter` (default 100 m) and `desiredAccuracy` tuned for the use case; evaluate the fetch decision only when a new sample arrives.
  - Skip repeated evaluations if neither distance nor TTL nor debounce thresholds are exceeded to avoid tight polling loops.
- **Re-use logic**
  - When preparing confirmation state, choose the cached POI set whose centroid is within radius `R` and whose age < TTL.
  - If multiple caches qualify, select the smallest distance between current fix and cache origin.
  - Persist cache across sessions (allow growth to bounded size, evict LRU entries beyond limit, e.g., last 50).
- **Prompt packaging**
  - Include `nearbyPlaces` array plus a `nearbyPlacesContext` string summarizing distance only (e.g., “User is ~180 m from cached nearby places gathered earlier.”).
  - Expose instrumentation hooks so `ask-ai-v7` payload logging shows cache usage (`hit`, `miss`, `stale`).
- **User privacy & controls**
  - Respect OS permissions; stop tracking on sign-out or revocation.
  - Automatically evaluate availability when the app opens; if no cached snapshot falls within radius, fetch immediately. No manual refresh UI required.

## Proposed Architecture
- **LocationTrackingController**
  - Wrapper around `CoreLocation` that exposes async stream of `DiscoveryLocationSample` (`coordinate`, `timestamp`, `horizontalAccuracy`, `source`).
  - Handles permission gating, accuracy filtering, and radius threshold calculations.
- **NearbyPlacesCacheStore**
  - Persistence layer (in-memory + disk) storing `NearbyPlacesSnapshot` entries: `{ id, centroid, radius, fetchedAt, places, sourceLocationId }`.
  - Implements geospatial lookup: given current coordinate, return best-fit snapshot if `distance <= radius`.
  - Supports eviction policy and TTL checks.
- **NearbyPlacesFetcher**
  - Service responsible for invoking Supabase `nearby-places`, with exponential backoff and error classification.
  - Accepts `FetchRequest` metadata (coordinate, radius, reason) and records metrics.
- **LocationContextCoordinator**
  - Orchestrates tracking + cache: subscribes to location samples, computes when to fetch, updates store.
- **DiscoveryFlow Integration**
  - `DiscoveryCreationFlowViewModel` requests `NearbyPlacesContext` during `prepareConfirmation`.
  - `SupabaseDiscoveryAnalysisClient` serializes extra fields on the payload (`nearbyPlaces`, `nearbyPlacesContext`, `distanceMeters`).
- **Telemetry**
  - Emit structured logs for `fetchTriggered`, `cacheHit`, `cacheMiss`, `cacheStale`, `fetchFailed`.
  - Optional hooks for future analytics dashboards (e.g., share via `WhatsThatShared/Logging`).

## Data Flow Summary
1. User signs in, onboarding complete → `LocationTrackingController` starts streaming samples.
2. Coordinator evaluates each sample:
   - If `distanceToNearestSnapshot > 500 m` or snapshot stale → enqueue fetch.
   - Otherwise tag sample with nearest snapshot ID for quick reuse.
3. Fetcher calls `nearby-places`; cache store saves snapshot with metadata (including fetch radius and origin coordinate).
4. When capture/selection occurs, confirmation screen queries coordinator for latest sample plus associated snapshot.
5. View model stores both the raw location and `NearbyPlacesContext` in `DiscoveryConfirmationState`.
6. On analysis start, payload includes:
   ```json
   {
     "location": { ... },
     "nearbyPlaces": [...],
     "nearbyPlacesContext": {
       "distanceMeters": 180,
       "sourceSummary": "Cached near Piazza Navona"
     }
   }
   ```
7. After analysis completes, cache remains available for future shots; eviction trims old entries as needed.

## Implementation Tasks
- Introduce domain models (`DiscoveryLocationSample`, `NearbyPlacesSnapshot`, `NearbyPlacesContext`) inside `WhatsThatDomain`.
- Add infrastructure services for location streaming and caching under `WhatsThatInfrastructure/Services/Location`.
- Update dependency container to inject new services into `DiscoveryCreationFlowViewModel`.
- Extend confirmation state (`DiscoveryConfirmationState`) to carry `nearbyPlaces` and context summary.
- Modify Supabase client to serialize additional payload fields and update tests/mocks accordingly.
- Mirror RN behavior for onboarding/on-auth gating while adding enhanced deduplication logic.
- Add diagnostics: debug panel/logging command to inspect cache contents for QA.

## Open Questions
- Do we need an upper bound on cached POI age beyond TTL (e.g., force refresh daily even if user stationary)?
- Should we persist cache to disk using `FileManager` or rely on `UserDefaults`/SQLite via `CacheLibrary`?
- How should we represent `distanceMeters` when horizontal accuracy is low (< confidence threshold)?
- What API contract changes (if any) are required on `nearby-places` to return metadata useful for summaries (e.g., cluster name)?

## Next Steps
- Review design with domain/infrastructure owners.
- Define telemetry schema and thresholds (500 m radius, 30 s debounce, 15 min TTL)—adjust after field testing.
- Prototype `NearbyPlacesCacheStore` with geohash indexing; add unit tests to cover hit/miss scenarios.
- Integrate into discovery flow behind a feature flag for staged rollout.
