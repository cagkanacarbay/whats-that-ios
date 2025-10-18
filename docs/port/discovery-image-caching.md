# Discovery Image Caching Architecture (iOS Native Port)

Last updated: {{DATE}}

## Overview

The native port persists both discovery images and their signed URLs so every surface can display the same asset without repeatedly hitting Supabase. The system is split into three layers:

1. **Persistence (`DiscoveryAssetCache`)** – an `actor` in `WhatsThatShared` that manages metadata, signed URLs, and on-disk image files.
2. **Presentation loader (`DiscoveryImageLoader` + `DiscoveryCachedImage`)** – a reusable SwiftUI-friendly wrapper that reads/writes through the cache and exposes load states.
3. **Feature integrations** – feed, hero overlay, detail view, voiceover bar, and creation flow all consume the presentation layer so a single cached payload fuels the entire app.

This mirrors the behaviour that existed in the React Native reference app (`lib/imageCache.ts`), but is tailored to Swift actors and structured concurrency.

## Core Components

### `DiscoveryAssetCache` (`native/WhatsThatIOSPackage/Sources/WhatsThatShared/DiscoveryAssetCache.swift`)

| Responsibility | Key APIs |
| --- | --- |
| Signed URL caching | `storeSignedURL(_:expiresAt:discoveryId:storagePath:)`, `cachedSignedURL(for:storagePath:tolerance:)`, `invalidateSignedURL(for:)` |
| Image persistence | `storeImageData(_:discoveryId:)`, `cachedImageURL(for:)`, `ensureImageCached(for:signedURL:session:)` |
| Maintenance | `purgeExpiredEntries(referenceDate:)`, `clearAll()` |

* Stores metadata in `metadata.json` inside `~/Library/Caches/DiscoveryAssets/`.
* Each entry tracks storage path, signed URL, expiry, last access, and the optional file name for the cached image.
* `ensureImageCached` downloads binary data via `URLSession.data(from:)` only when the file is missing.

### `DiscoveryImageLoader` (`native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/DiscoveryImageLoader.swift`)

* `ObservableObject` that:
  * Attempts to load the cached file first (`loadCachedImage`).
  * Falls back to `DiscoveryAssetCache.ensureImageCached` when a disk copy is missing.
  * Publishes `image`, `isLoading`, and `didFail` for UI bindings.
* `DiscoveryCachedImage` view wrapper simplifies consumption:
  * Accepts a `discoveryId` and optional remote URL.
  * Emits `DiscoveryImageLoadPhase` (`empty`, `loading`, `success`, `failure`).
  * Handles `onAppear` / `onChange` to drive the loader.

## Data Flow

### Fetching from Supabase

* `SupabaseDiscoveryRepository.loadSignedImageURL`:
  1. Checks `DiscoveryAssetCache.cachedSignedURL`.
  2. Creates a new signed URL via Supabase `createSignedURL`.
  3. Stores the signed URL + expiry in the cache for future calls.

### Displaying in the UI

All discovery imagery now routes through `DiscoveryCachedImage`:

| Surface | File | Notes |
| --- | --- | --- |
| Feed grid | `DiscoveriesHomeView.swift` (`DiscoveryCardImage`) | Seeds `DiscoveryHeroImageCache` with the decoded bitmap to keep the hero transition instant. |
| Hero overlay | `DiscoveriesHomeView.swift` (`DiscoveryHeroImageView`) | Uses the cached loader; falls back to gradient + placeholder snapshot. |
| Detail screen | `DiscoveryDetailView.swift` | Reuses the loader that used to be embedded locally; keeps signed-URL fallback for error states. |
| Voiceover player | `DiscoveriesHomeView.swift` (`VoiceoverPlayerBar`) | Shows the cached artwork or a waveform icon. |
| Share sheet | `DiscoveriesHomeView.makeShareAction` | Prefers the cached `file://` URL; falls back to signed URLs only when the file is missing. |
| Creation flow completion | `DiscoveryCreationFlowView.swift` | Displays the summary using the cached image once the feed summary is hydrated. |

### Creation Flow → Feed Sync

1. `DiscoveryCreationFlowViewModel` stores the raw capture data (`storeImageData`) as soon as Supabase confirms completion.
2. The same view model fetches the latest discovery summary (`fetchRecentDiscoveries`) and passes it to listeners via `onDiscoverySummaryReady`.
3. `MainTabView` pushes the summary into the feed (`DiscoveryFeedViewModel.upsert`) and cancels the fallback refresh timer.
4. The feed already has the file path on disk, so `DiscoveryCachedImage` resolves immediately without waiting for network fetches.

### Lifecycle Maintenance

* App boot (`AppRootViewModel.init`) launches a background `purgeExpiredEntries` so stale files are trimmed.
* Sign-out (`AppRootViewModel.signOut`) calls `clearAll` to prevent cross-account leakage.
* Settings reset/sign-out paths call into the same clear logic indirectly.

## Usage Guidelines

1. **Always go through `DiscoveryCachedImage`.** Do not call `DiscoveryAssetCache` directly from UI code unless you are adding a new reusable loader.
2. **Provide stable `discoveryId`s.** The loader relies on the id to locate cached metadata and the on-disk file. For non-discovery images (e.g., auxiliary assets), create a dedicated cache if needed.
3. **Forward remote URLs when available.** The loader requires either a cached file or a remote URL to hydrate the cache. Pass the signed URL you received from Supabase; it will only be used when the file is missing.
4. **Keep capture data short-lived.** `DiscoveryCreationFlowViewModel` clears `currentMedia` after the cache write to avoid storing large blobs in memory longer than necessary.
5. **Handle fallbacks gracefully.** For UX parity, every consumer renders gradients/placeholders when the cache is empty or the download fails.
6. **Avoid manual refreshes.** The feed automatically injects newly created summaries; only trigger `refresh()` when you need a server authoritative view (e.g., pull-to-refresh).

## Extending the System

* To cache additional discovery-related assets (audio, thumbnails), follow the same pattern: central `actor` for metadata, shared loader, and view wrapper.
* For advanced eviction policies (size-based limits, background pruning), expand `DiscoveryAssetCache.cleanupIfNeeded`.
* When adding new discovery-consuming screens, prefer injecting the already-loaded `DiscoverySummary` so both data and imagery reuse the same cache entries.

## Testing & Validation

* Unit coverage lives in `DiscoveryAssetCacheTests` (`WhatsThatSharedTests`).
* Manual smoke checklist:
  - Create a discovery, navigate to the feed without network – image should display instantly.
  - Open hero overlay + detail; both should reuse the same bitmap without flicker.
  - Trigger share sheet offline to verify `file://` URLs work.
  - Sign out and sign back in with another account to ensure previous images are gone.

## Future Ideas

* Add diagnostic logging/toggle to inspect cache size and contents from Settings.
* Instrument cache hit/miss metrics once analytics plumbing is available.
* Consider prewarming newly fetched feed pages by calling `DiscoveryImageLoader.ensureImageCached` off the main thread.

