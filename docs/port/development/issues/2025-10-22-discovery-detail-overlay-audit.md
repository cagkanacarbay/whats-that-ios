# Discovery Detail Overlay Architecture Audit (2025-10-22 15:33:55 UTC)

> **Validity:** Snapshot of the iOS port at 2025-10-22 15:33:55 UTC. Reconfirm before acting if newer changes landed.

## Overview

The discovery detail overlay is a SwiftUI presentation layered on top of the feed. `DiscoveriesHomeView` owns the entire transition state machine, while a cluster of overlay-specific views (`DiscoveryDetailOverlayView`, `DiscoveryDetailView`, and companions) render the hero image, header chrome, and scrollable body. State is split across animation progress, gesture metrics, and readiness flags, with image data flowing through a bespoke cache to keep the opening hero in sync with the tapped card.

## Component Inventory

- `DiscoveriesHomeView` (`native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DiscoveriesHomeView.swift:295-525`)  
  Creates `DiscoveryDetailContext`, tracks `detailProgress`, `detailIsSettled`, closing/gesture metrics, and drives open/close animations via `DiscoveryDetailHeroAnimator`. It also hides the tapped card and holds onto the cached snapshot.
- `DiscoveryDetailOverlayView` (`.../DetailOverlay/DiscoveryDetailOverlayView.swift`)  
  Converts the high-level state into layout primitives (corner radius, shadow, hero height) and applies `DiscoveryDetailUniformCloseTransform` during dismissals. Bridges between the opening hero and the internal scroll view through a matched-geometry namespace.
- `DiscoveryDetailView` (`.../DetailOverlay/DiscoveryDetailView.swift`)  
  Renders the hero, header overlay, and scrollable body. Uses a pair of `DiscoveryHeaderOverlayView` instances that swap roles once the chrome is “ready”.
- `DiscoveryHeroHeaderView` (`.../DetailOverlay/DiscoveryHeroHeaderView.swift`)  
  Wraps `DiscoveryCachedImage` and decides whether to show the cached card snapshot or the freshly loaded asset.
- `DiscoveryDetailDismissInteractor` (`.../DetailOverlay/DiscoveryDetailDismissInteractor.swift`)  
  Computes the gesture-driven transform (translation/scale/rotation) and dismissal thresholds.
- `DiscoveryDetailImageCache` + `DiscoveryCardImageView` (`.../DetailOverlay/DiscoveryDetailImageCache.swift`, `.../Grid/DiscoveryCardImageView.swift`)  
  `DiscoveryCardImageView` captures the rendered `UIImage` of the grid card hero and stashes it in a per-discovery cache for use during overlay presentation.

## Image Lifecycle

1. **Grid card load** – `DiscoveryCardImageView` displays `DiscoveryCachedImage`, and on success caches the `UIImage` (`DiscoveryCardImageView.swift:22-43`). This snapshot is the exact cropped card rendition (card aspect ratio, gradient, possible scaling artifacts).
2. **Overlay instantiation** – When a card is tapped, `handleDiscoverySelection` retrieves the cached snapshot (`DiscoveriesHomeView.swift:317-327`) and seeds `DiscoveryDetailContext.placeholderImage`.
3. **Overlay hero rendering** – `DiscoveryHeroHeaderView` decides between the cached snapshot and the freshly loaded asset based on `LayoutConfiguration.preferPlaceholderImage` (`DiscoveryDetailOverlayView.swift:204` and `DiscoveryDetailView.swift:75-104`). Before chrome is ready—or whenever a gesture is active—the overlay sticks to the cached snapshot.
4. **Scroll content** – Once `layout.isChromeReady` flips, `DiscoveryDetailContentView` becomes authoritative for the header overlay and body; it still depends on the same `DiscoveryCachedImage` pipeline to resolve the remote asset for long-form display.

The result is effectively two hero image sources (cached snapshot + live asset) that swap based on readiness/interaction flags, plus two copies of the header overlay (hero overlay vs. scroll overlay) coordinated by a matched geometry effect.

## Opening Sequence (Tap → Settled)

1. **State setup** – `handleDiscoverySelection` seeds the context, hides the source card, resets interaction state, and kicks off a 0→1 animation on `detailProgress` (`DiscoveriesHomeView.swift:320-342`).
2. **Hero expansion** – `DiscoveryDetailOverlayView` lerps the hero’s frame using `DiscoveryDetailHeroGeometry`, ensuring the hero fills the screen while the overlay background fades (`DiscoveryDetailHeroAnimator.swift` + `DiscoveryDetailOverlayView.swift:121-203`).
3. **Chrome gating** – The hero overlay (title/date/short description gradient) shows immediately via `heroOverlayOpacity`. Scroll chrome (`DiscoveryDetailContentView`) stays hidden until `detailIsSettled` flips true.
4. **Readiness delay** – `scheduleDetailSettled` waits `heroAnimator.openDuration` (0.5 s) before toggling `detailIsSettled` and animating `detailContentOpacity` to 1 (`DiscoveriesHomeView.swift:417-427`). Until that flag flips, `DiscoveryDetailOverlayView` sets `isChromeReady = false`, forcing the hero to use the cached placeholder and deferring the scroll body.
5. **Overlay swap** – When `isChromeReady` becomes true, the matched-geometry effect hands ownership of the header overlay to the scroll view (`DiscoveryDetailView.swift:95-123`), and `preferPlaceholderImage` switches to false so the live asset can display.

## Closing Sequence (Back Button vs. Edge Gesture)

- **Back button** – `handleDetailDismissal` resets interaction metrics, flags `detailIsClosing = true`, and animates `detailProgress` back to 0 using the bezier configured in `DiscoveryDetailHeroAnimator.closeAnimation()` (`DiscoveriesHomeView.swift:484-524`). Because `detailCloseStartScale` is forced to 1, the uniform close transform handles a symmetric collapse.
- **Edge gesture** – `DiscoveryDetailDismissInteractor` produces translation/scale/rotation as the user drags (`DiscoveriesHomeView.swift:431-473`). If the gesture crosses the threshold, these values are frozen into `detailCloseStart*` and `isClosing` begins from the partially transformed pose. During the closing phase, `DiscoveryDetailOverlayView` enforces the card aspect ratio and drives the uniform transform back to the card’s destination frame (`DiscoveryDetailOverlayView.swift:182-214`).
- In both cases, `detailIsSettled` is toggled false immediately, `isChromeReady` collapses, and the overlay returns to the placeholder snapshot while the hero animates home.

## Observed Issues & Root Causes

### 1. Opening overlay flicker when the animation settles

- The flicker lines up with the moment `detailIsSettled` flips true and `layout.isChromeReady` becomes true (`DiscoveriesHomeView.swift:424-427` → `DiscoveryDetailOverlayView.swift:153-176`).  
- At that instant:
  - `DiscoveryDetailView`’s hero overlay stops being the matched-geometry source (`DiscoveryDetailView.swift:95-103`), and the scroll overlay takes over (`DiscoveryDetailContentView` around lines 205-233).
  - `preferPlaceholderImage` flips to false (`DiscoveryDetailOverlayView.swift:204`), causing `DiscoveryHeroHeaderView` to swap from the cached snapshot to the live asset. If the asset has already loaded with a slightly different crop/scale, the swap is visible. If the asset is still loading, the hero briefly shows the gradient placeholder before the real image arrives, which reads as a flash.
- Because both the overlay hand-off and image swap happen in the same frame with opacity transitions (`detailContentOpacity` easing over 0.18s), any mismatch in alpha curves or load timing manifests as a perceptible jump.

### 2. Closing gesture jump as the user lifts their finger

- When the gesture ends and `detailIsClosing` toggles true (`DiscoveriesHomeView.swift:469-499`), the overlay immediately forces `isChromeReady = false`, which in turn re-enables `preferPlaceholderImage = true`. The hero therefore swaps back to the cached card snapshot before the closing transform begins (`DiscoveryDetailOverlayView.swift:182-206`).
- The cached snapshot is already cropped to card dimensions, so the aspect ratio changes instantly: the tall expanded hero becomes the shorter card crop, producing the “shorter image” pop noted during release.
- Simultaneously, `DiscoveryDetailHeroGeometry` switches to `enforceAspectForImage = true` while `progress` is still near 1 (`DiscoveryDetailOverlayView.swift:134-189`). That forces the calculated hero height to snap to the card ratio in the same frame, amplifying the perceived jump.

### 3. Detail body content appears ~1 s late

- The scrollable content and narration button are gated by `detailIsSettled` → `isContentReady` → `isChromeReady` (`DiscoveryDetailOverlayView.swift:153-175`).  
- `scheduleDetailSettled` waits the full open animation duration before toggling the flag, regardless of actual progress or the matched-geometry state (`DiscoveriesHomeView.swift:417-427`). With the bezier ease-out (`openDuration = 0.5s`) plus the 0.18s opacity animation on `detailContentOpacity`, the body routinely arrives 600‑700 ms after the hero settles. If the device is under load, the async-after delay can drift closer to a second, matching the observed lag.
- Until the flag flips, the markdown body is also prevented from rendering (`DiscoveryDetailView.LayoutConfiguration.isMarkdownReady` is tied to `isChromeReady`), so there is no opportunity to stage content early off-screen.

## Additional Fragility

- `closeBaselineImageHeight` is updated asynchronously via `DispatchQueue.main.async` (`DiscoveryDetailOverlayView.swift:225-241`), which means rapid consecutive presentations may reuse stale heights.
- The overlay depends on global coordinate space measurements from `GeometryReader` and `UIScreen.main.bounds`. Any safe-area or multi-window changes require additional reconciliation logic, increasing the likelihood of desynchronisation.
- Multiple state gates (`detailIsSettled`, `detailContentOpacity`, `isChromeReady`, `isMarkdownReady`) must align perfectly. Divergence (for example, due to gesture cancellation or animation interruption) leaves the overlay showing the wrong asset or hides the chrome entirely.

## Takeaways

- The current architecture relies on placeholder swapping and manual readiness gates to mask loading seams. These swaps are exactly what produce the observed flickers and jumps.
- Tight coupling between the animation controller (`DiscoveriesHomeView`) and the rendering view (`DiscoveryDetailOverlayView`) makes it difficult to reason about state—in particular when gestures interrupt the open/close curves.
- A smoother architecture should unify hero image ownership (single source of truth for the bitmap), decouple chrome readiness from animation timers, and treat matched-geometry handoffs as part of a dedicated transition coordinator rather than ad-hoc flag flips.
