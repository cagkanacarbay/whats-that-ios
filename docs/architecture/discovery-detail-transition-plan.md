# Discovery Detail Transition Architecture

> **Status:** Proposed  
> **Author:** Codex agent (2025-10-22)  
> **Scope:** Replace the current discovery detail overlay orchestration with a coordinator-driven state machine that eliminates image flicker, chrome delays, and dismissal jumps.

---

## 1. Goals

- Deliver a seamless hero transition when opening and closing a discovery detail overlay, with no bitmap swaps or chrome flicker visible to the user.
- Centralise state so animation, gesture interactivity, chrome placement, and image loading are coordinated by one object.
- Simplify `DiscoveriesHomeView` by removing the dozen `@State` flags used to track progress, dismissal metrics, content readiness, and image placeholders.
- Preserve existing behaviours (tap to open, back button dismiss, left-edge drag dismissal, card hiding while overlay is active) while paving the way for future enhancements (quick actions, global player).

## 2. Current Pain Points (Summary)

| Issue | Root Cause |
| --- | --- |
| Opening flicker in title/gradient | Placeholder snapshot swapped for live asset when `detailIsSettled` toggles true. Matched geometry handoff and opacity animations happen in the same frame. |
| Gesture-dismiss jump | As soon as the gesture ends, the overlay forces the placeholder snapshot and re-applies card aspect ratio, producing a sudden height change before animation kicks in. |
| Detail content arrives ~600-1000 ms late | `scheduleDetailSettled` gates chrome visibility with a delayed `DispatchQueue.main.asyncAfter`, then animates opacity. |
| Fragile state | `DiscoveriesHomeView` owns many flags that must stay in sync; interrupts can leave overlay mid-state. |

These issues stem from having multiple sources of truth (image pipeline, opacity flags, gesture metrics) spread across views and view models.

## 3. Proposed Architecture Overview

Introduce a dedicated `DiscoveryDetailTransitionCoordinator`, responsible for:

1. Owning transition state via a `Phase` enum (`idle`, `preparing`, `animatingIn`, `presented`, `interactiveDismiss`, `closing`, `resetting`).
2. Managing hero imagery through a single `HeroSurface` object that carries crop metadata and can smoothly swap to the high-resolution asset once available without revealing a different aspect mid-transition.
3. Computing deterministic geometry (`HeroGeometry` and `OverlayLayout`) for every frame of the transition, including interactive drag updates, and easing the hero aspect ratio during close-outs instead of snapping.
4. Driving chrome placement, opacity, and matched-geometry handoffs based on `Phase`.
5. Absorbing live layout measurements (size + origin) and scroll feedback from the host view so safe-area shifts, parallax, and pull-down elasticity stay in sync mid-animation.
6. Exposing a single throttled `@Published` `OverlaySnapshot` consumed by `DiscoveryDetailOverlayView`.

`DiscoveriesHomeView` no longer orchestrates animation details. Instead, it:

- Creates a `@StateObject var detailCoordinator`.
- Invokes coordinator methods (`present`, `updateDrag`, `endDrag`, `dismiss`) based on user interactions.
- Renders `DiscoveryDetailOverlayView` only when `coordinator.snapshot.phase.isActive` is true.

```
DiscoveriesHomeView
  └─ DiscoveryDetailTransitionCoordinator
        ├─ HeroSurface (bitmaps + crop descriptor)
        ├─ HeroGeometry (start/end frames, corner radius)
        ├─ ChromePlacement (hero or scroll)
        └─ OverlaySnapshot (published)
             ├─ phase
             ├─ layout (hero rect, mask radius, shadow, backdrop opacity)
             ├─ heroSurface (primary/transition textures, fade progress)
             ├─ chromeConfiguration (placement, opacity, matched-geometry semantics)
             ├─ contentState (markdown + voiceover readiness flags)
             └─ scrollState (pull-down offset, parallax coefficients)
```

## 4. Component Breakdown

### 4.1 DiscoveryDetailTransitionCoordinator

**Location:** `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/Transitions/DiscoveryDetailTransitionCoordinator.swift`

**Responsibilities**
- Capture the tapped card snapshot from `DiscoveryDetailImageCache` and build the initial `HeroSurface`, including the exact crop rect visible in the grid card.
- Resolve `HeroGeometry` by combining the card's start frame, container metrics, safe-area origin, and target layout constants (existing math from `DiscoveryDetailHeroGeometry`).
- Continuously absorb live layout measurements (container size + origin, safe-area insets) and feed in scroll offset so rotations, split-screen adjustments, and parallax effects stay aligned.
- Persist the card’s destination frame immediately on presentation (before the grid hides the view) and reuse it during dismissal so rotations do not rely on live `GeometryReader` updates from a hidden card.
- Publish `OverlaySnapshot` updates on the main actor while coalescing redundant frames to avoid render/measure loops.
- Track asynchronous tasks (image loading, markdown parsing if needed) and merge their results into snapshots without flicker.
- Record `closeKeyframe` data when the gesture ends so the closing animation starts from the exact interactive pose and eases the aspect ratio back to the card footprint.
- Delegate domain-specific logic to dedicated collaborators:
  - `HeroSurfaceManager` for bitmap acquisition, cross-fades, and crop math (§4.3).
  - `ChromeStateReducer` for matched-geometry orchestration and opacity timelines (§4.4).
  - `GeometryPipeline` for measurement coalescing, aspect timelines, and drag transforms (§4.6–4.8).
  - `AccessibilityBridge` for voiceover signalling and metadata preloading (§4.10).

**Primary API**
```swift
final class DiscoveryDetailTransitionCoordinator: ObservableObject {
    @Published private(set) var snapshot: OverlaySnapshot = .idle

    func present(discovery: DiscoverySummary, cardFrame: CGRect, imageURL: URL?, containerSize: CGSize, safeAreaInsets: EdgeInsets)
    func updateMeasurements(_ measurements: OverlayMeasurements)
    func updateScroll(offset: CGFloat, baseline: CGFloat)
    func updateDrag(gesture: DragGesture.Value)
    func endDrag(gesture: DragGesture.Value)
    func dismiss(reason: DismissReason)
    func resetIfNeeded()
}
```

`OverlayMeasurements` is emitted every time the overlay’s geometry changes (via `GeometryReader`) and contains container size, global origin, safe-area insets, and the latest resolved destination card frame. `updateScroll` receives the hero scroll preference (offset + baseline) so the coordinator can maintain parallax and pull-down behaviour. `DismissReason` differentiates between back button and gesture completion so the coordinator can choose appropriate closing keyframes.

### 4.2 OverlaySnapshot

**Structure**
```swift
struct OverlaySnapshot {
    let phase: Phase
    let layout: OverlayLayout
    let hero: HeroSurface
    let chrome: ChromeConfiguration
    let content: ContentState
    let scroll: ScrollState
    let accessibility: AccessibilityState
}
```

- `OverlayLayout`: hero frame, corner radius, scale, shadow, backdrop opacity, and the final transform (scale/offset/rotation) the view should apply.
- `HeroSurface`: composite textures (primary, optional transition), fade progress, content mode, baseline aspect ratio, plus normalized `cardCrop`/`visibleCrop` describing what portion of the bitmap should be shown at the current progress.
- `ChromeConfiguration`: opacity, placement anchor (`.hero`/`.scroll`), matched-geometry namespace/id, and `isSource` flag for matched-geometry semantics.
- `ContentState`: markdown readiness, voiceover button visibility (preloaded in `preparing` phase).
- `ScrollState`: pull-down offset, baseline, and derived parallax coefficients for hero height and chrome opacity.
- `AccessibilityState`: voiceover activation flags and any additional accessibility cues.

### 4.3 HeroSurface lifecycle

1. On `present`, the coordinator first attempts to read the cached snapshot from `DiscoveryDetailImageCache`. If the cache misses, it starts the hero animation immediately using the existing gradient/placeholder surface and schedules a high-priority render for the card snapshot. Because SwiftUI view construction must occur on the main actor, the render runs inside `MainActor.run` (after the current runloop tick) via `ImageRenderer` and uses the lightweight `DiscoveryCardView` template so work stays brief. When rendering completes, `HeroSurfaceManager` cross-fades the new snapshot into place, mirroring the remote image swap, so fidelity converges without the tap ever stalling.
2. The coordinator computes the card’s visible crop by comparing the card aspect ratio with the source image aspect. The result is stored as a normalized `CGRect` (`visibleCropCard`) representing the portion of the bitmap that was on-screen in the grid card. If the cached snapshot was already rendered with `.scaledToFill().clipped()`, we treat that snapshot as fully cropped and set `visibleCropCard = .unit`.
3. To guarantee the high-res swap matches the card exactly, the coordinator pre-rasterizes a card-sized bitmap from the full-resolution asset using `CGImageCreateWithImageInRect` (or `UIGraphicsImageRenderer`). When rasterizing, it reuses the same gradient + title compositing helper that `DiscoveryCardView` employs so the lighting/contrast stays identical during the cross-fade. This produces a `CroppedImage` (bitmap + scale) that mirrors the card framing pixel-for-pixel.
4. It constructs a composite `HeroSurface`:
   ```swift
   struct HeroSurface {
       var primary: UIImage          // currently visible texture
       var transition: UIImage?      // optional incoming texture
       var transitionProgress: Double // 0 → 1 cross-fade factor
       var contentMode: ContentMode
       var baselineAspect: CGFloat
       var visibleCrop: CGRect       // normalized (0-1) crop rect used after hero expansion begins
       var cardCrop: CGRect          // normalized crop matching the card framing
   }
   ```
   The overlay renders both `primary` and `transition` inside a dedicated `HeroSurfaceView` (SwiftUI wrapper around a `CALayer` hierarchy) that applies the `cardCrop` while `transitionProgress < 1`. Once the fade completes and the hero begins expanding, the view animates the mask toward `visibleCrop`, revealing more of the high-resolution texture.
- `DiscoveryHeroHeaderView` is rewritten to host `HeroSurfaceView` and accept a `HeroSurface` binding instead of spinning up its own `DiscoveryCachedImage`. This keeps image ownership inside the coordinator and prevents double-fetching. `DiscoveryCardImageView` continues caching snapshots eagerly on appearance so the asynchronous fallback path above remains rare in practice.
- The CALayer-backed `HeroSurfaceView` sits inside a `HeroSurfaceContainer` SwiftUI wrapper that preserves the existing `matchedGeometryEffect`. The container owns the namespace identifiers, wraps the UIKit view, and reports measured size back to the coordinator so the hero-to-card handoff continues to use SwiftUI’s layout engine while still benefiting from the layer-backed masking.
- `HeroSurfaceContainer` exposes a feature flag that lets us fall back to the existing pure SwiftUI rendering path during rollout/testing, protecting us from regressions if layout forwarding ever drifts.
- Before rolling the CALayer path into production, we will run a dedicated spike that mounts `HeroSurfaceView` inside the current overlay hierarchy and exercises the open/close animations plus interactive dismissal. The spike explicitly checks for: (1) coordinate drift between the layer tree and SwiftUI’s matched-geometry frames, (2) opacity or transform mismatches that could reintroduce flickers, and (3) gesture/input quirks where the UIKit container might swallow drag events. If any issue surfaces, the feature flag keeps the SwiftUI-only renderer available while we resolve the gap.
5. The coordinator calls into the non-view image loader (`DiscoveryImageLoader`) or `DiscoveryAssetCache` directly to ensure the high-resolution bitmap is cached. Once the file exists, it loads the data on a background task, instantiates `UIImage`, and invokes `preparingForDisplay()` (or an explicit CoreGraphics draw) to pre-decode the bitmap before hopping back to the main actor.
6. Before publishing the transition state, the coordinator rasterizes the card crop using the decoded bitmap and stores both the cropped and original variants. The cropped image becomes `transition`, ensuring the crossfade never reveals a different aspect.
7. After the decoded bitmap is ready, the coordinator updates the snapshot with `transition` set, `transitionProgress = 0`, `visibleCrop = cardCrop`, and retains the full bitmap for future expansions.
8. Using `withAnimation(.linear(duration: 0.12))`, the coordinator ramps `transitionProgress` to 1 while compositing the placeholder + incoming image inside the same layer tree to avoid brightness pops. Once the animation completes, it promotes the cropped bitmap into `primary`, clears `transition`, and begins animating `visibleCrop` toward the expanded hero crop prescribed by `HeroGeometry`. If additional area is needed, the coordinator lazily rasterizes new slices from the pre-decoded original so there is no hitch.
9. When the overlay dismisses, the coordinator cancels any outstanding loader tasks and releases the pre-decoded bitmaps so repeated presentations start from a clean slate without leaking memory.

### 4.4 Chrome handling

- A new `DiscoveryOverlayChrome` view wraps the existing `DiscoveryHeaderOverlayView` layout. It accepts `ChromeConfiguration` and the discovery data.
- `ChromeConfiguration` carries `anchor` (`.hero` / `.scroll`), `matchedGeometryId`, `namespace`, `isSource`, and `opacity`.
- Matched geometry is handled inside `DiscoveryOverlayChrome` via:
  ```swift
  .matchedGeometryEffect(
      id: configuration.matchedGeometryId,
      in: configuration.namespace,
      properties: .frame,
      anchor: .bottom,
      isSource: configuration.isSource
  )
  ```
  The coordinator flips `isSource` in sync with phase changes so ownership transitions without the one-frame pop.
- Opacity transitions are driven purely by `configuration.opacity`. The coordinator ramps this from 0 → 1 during `.animatingIn`, holds at 1 for `.presented`, and fades to 0 while closing or during active drag.
- We retain separate hero and scroll chrome instances. During the swap, both remain in the view hierarchy; the coordinator sets one’s opacity to 1 and the other to 0 while flipping matched-geometry roles to eliminate any one-frame pop.

### 4.5 Gesture flow

- `updateDrag` moves the coordinator to `.interactiveDismiss`, recomputes `OverlayLayout` using the drag metrics from `DiscoveryDetailDismissInteractor`.
- `endDrag` decides between `.closing` (if thresholds met) or a spring back to `.presented`. Because the coordinator tracks the hero pose at the moment the gesture ended, the closing animation interpolates smoothly without aspect ratio jumps.
- During `.interactiveDismiss`, `HeroSurface` is not swapped and `OverlayLayout` continues to respect the expanded aspect ratio, preventing the immediate “shorten” effect.

### 4.6 Closing geometry easing

- When the coordinator enters `.closing`, it captures a `CloseKeyframe` containing the current hero frame, scale, rotation, and `visibleCrop`.
- Instead of toggling to the card aspect immediately, the coordinator derives an `AspectTimeline`:
  ```swift
  struct AspectTimeline {
      let startAspect: CGFloat      // expanded hero aspect at release
      let endAspect: CGFloat        // card aspect ratio
      let duration: TimeInterval    // equals close animation duration
      func aspect(at progress: CGFloat) -> CGFloat
  }
  ```
- `aspect(progress:)` uses a cubic ease (matching the close animation timing curve) so the hero height interpolates smoothly toward the card while preserving the release pose.
- `visibleCrop` animates alongside the aspect: until `progress` exceeds a configurable threshold (e.g., 0.35) the crop stays locked to the card, guaranteeing no exposed letterboxing. After that, the crop expands toward `.unit` to reveal additional image area as the card footprint shrinks.
- The coordinator reuses the math from `DiscoveryDetailUniformCloseTransform` by extracting it into a pure helper (`UniformCloseTransformCalculator`). The helper takes the recorded keyframe (scale, offset, rotation), target destination frame, and the eased `aspect(progress)`, returning the correct transform for the current tick.
- `OverlayLayout` consumes the interpolated aspect and helper output (which produces the exact scale/offset/rotation tuple). `DiscoveryDetailOverlayView` stops applying `DiscoveryDetailUniformCloseTransform` directly and instead reads the precomputed transform from the snapshot, ensuring there is a single source of truth for motion.

### 4.7 Continuous geometry updates

- `OverlayMeasurements` encapsulates the container size, global origin, safe-area insets, and destination frame for the card. `DiscoveryDetailOverlayView` emits this structure when its `GeometryReader` changes **and** the overlay is actually visible; preference writes use `Transaction(animation: nil)` so they never trigger measurement → animation feedback loops.
- The coordinator merges each measurement into the active `HeroGeometry`, recomputing offsets, scale, and corner radius while preserving current phase progress. Measurements are coalesced: the coordinator retains the last measurement and only recomputes when any dimension differs by more than a 0.5pt tolerance (size or origin) or 0.5° for rotations, or when the phase transitions into/out of `.interactiveDismiss`. The display link simply reads the most recent measurement; it never schedules new geometry reads.
- When a significant change is detected mid-animation, the coordinator re-derives the `AspectTimeline` using the updated destination frame so the closing path stays consistent.
- If the underlying card view is hidden, the coordinator continues using the frozen destination frame captured during `present`; measurement updates remain optional but any late-arriving frames (e.g., when the card reappears) refresh the stored rect.

### 4.8 Scroll offset ingestion

- `DiscoveryDetailContentView` continues publishing `HeroScrollOffsetPreferenceKey`. Instead of binding to local `@State`, it forwards changes to the coordinator via a lightweight bridge (`ScrollBridge`) that invokes `detailCoordinator.updateScroll(offset:baseline:)` **once the coordinator has entered `.animatingIn`**. Before that, scroll updates are ignored so we never run parallax math on a zeroed hero.
- The coordinator transforms the raw offset into a `ScrollState` containing:
  - `pullDownOffset` (positive-only value used for elasticity)
  - `parallaxOffset` (clamped negative offsets for hero lift)
  - `chromeOpacity` (derived from the existing easing formula in `DiscoveryDetailOverlayView` line ~162)
  - `isScrollDisabled` flag mirrored into `ContentState`
- These values are embedded in `OverlaySnapshot.scroll`, and `DiscoveryDetailOverlayView` reads them instead of recalculating hero layout locally, preserving the existing visual choreography.

### 4.9 Snapshot publishing & throttling

- `OverlaySnapshot` publishes are event-driven by default (`present`, gesture callbacks, scroll bridge, async image milestones). A lightweight `DisplayLinkScheduler` is activated only during interactive dismissal (when gesture deltas change every frame) and shuts down as soon as the gesture resolves. This avoids a blanket 60 Hz publish while still giving the coordinator fine control during scrubs.
- Before publishing, the coordinator compares the new snapshot with the previous one using tolerances: layout delta < 0.5pt, scroll delta < 0.25pt, opacity delta < 0.01, rotation delta < 0.5°. If no values exceed the threshold the publish is skipped. Interactive phases coalesce multiple gesture updates into a single publish per runloop turn.
- `HeroSurface` payloads are reference-wrapped (`class HeroSurfacePayload`) so snapshot structs remain light; only metadata changes on each publish, avoiding heavy UIImage copying.
- For scroll input specifically, the coordinator applies a low-pass filter (e.g., exponential moving average with alpha 0.25) to `pullDownOffset` so minute bounce noise doesn’t ping-pong the overlay opacity. At the same time, the raw offset is retained for gesture thresholds and dismissal metrics so responsiveness is unaffected.
- Open and close remain powered by SwiftUI animations (`heroAnimator.openAnimation/closeAnimation`); the coordinator mutates discrete state at phase boundaries and lets SwiftUI interpolate, keeping diffing work minimal outside of true interactive gestures.

### 4.10 Host view side effects

- `OverlaySnapshot` exposes `activeDiscoveryId` so `DiscoveriesHomeView` can hide the source card without maintaining separate state. When `snapshot.phase` returns to `.idle`, this id becomes `nil` and the grid automatically unhides the card.
- Voiceover signalling moves into the coordinator: `present` sets `voiceoverController.isDetailOverlayActive = true`, while `resetIfNeeded` clears it. The host view injects its existing `VoiceoverPlaybackController` when constructing the coordinator so the coordinator can also call `ensureMetadata` at the appropriate times.
- Presentation begins immediately using the best-known frame (tap-provided start frame or `resolveStartFrame` fallback) so taps never feel ignored. When the first precise `OverlayMeasurements` arrives, the coordinator eases any delta over a few frames (using the same easing as closing geometry) to slide the hero into its true destination without popping.

## 5. View Layer Changes

### 5.1 DiscoveriesHomeView

- Replace the existing `@State` collection with:
```swift
@StateObject private var detailCoordinator = DiscoveryDetailTransitionCoordinator(
    voiceoverController: voiceoverController
)
```
- `handleDiscoverySelection` becomes:
```swift
detailCoordinator.present(
    discovery: discovery,
    cardFrame: resolvedFrame,
    imageURL: resolvedImageURL,
    containerSize: overlayContainerSize,
    safeAreaInsets: safeArea
)
```
- Pipe geometry updates to the coordinator:
```swift
DiscoveryDetailOverlayView(
    snapshot: snapshot,
    namespace: overlayNamespace,
    onDismiss: { detailCoordinator.dismiss(reason: .backButton) },
    onOptions: onShowOptions
)
.background(
    GeometryReader { proxy in
        Color.clear
            .onAppear { detailCoordinator.updateMeasurements(makeMeasurements(proxy)) }
            .onChange(of: proxy.frame(in: .global)) { _ in detailCoordinator.updateMeasurements(makeMeasurements(proxy)) }
    }
)
```
  where `makeMeasurements` packages container size, origin, safe-area, and the latest destination card frame.
- `detailCoordinator.updateMeasurements` performs tolerance-based equality checks (0.5pt / 0.01 scale / 0.5° rotation) before mutating state, so incremental scroll offset noise does not trigger a publish loop.
- Selection events fire immediately using the resolved tap frame; if a more accurate measurement lands later, the coordinator interpolates to the new geometry rather than snapping, matching the behaviour described in §4.7.
- `detailEdgeDragGesture` delegates to `detailCoordinator.updateDrag` / `endDrag`.
- Overlay presentation reads `detailCoordinator.snapshot` to decide whether to render `DiscoveryDetailOverlayView`.
- Card hiding uses `detailCoordinator.snapshot.activeDiscoveryId` (exposed via `OverlaySnapshot`) instead of separate `HiddenDiscovery`.
- Voiceover activation relies on `detailCoordinator.snapshot.accessibility.isVoiceoverActive`; the host view no longer toggles the controller directly.

### 5.2 DiscoveryDetailOverlayView

- Accept a single `OverlaySnapshot` plus callbacks:
```swift
struct DiscoveryDetailOverlayView: View {
    let snapshot: OverlaySnapshot
    let namespace: Namespace.ID
    let onDismiss: () -> Void
    let onOptions: (() -> Void)?
}
```
- Remove inline calculations (`closeBaselineImageHeight`, `preferPlaceholder`, `resolvedOverlayOpacities`, etc.). All required numbers arrive inside `snapshot.layout`.
- Render hero imagery via `HeroSurfaceContainer(surface: snapshot.hero, namespace: snapshot.chrome.namespace)` — a SwiftUI wrapper that embeds the CALayer-backed renderer while preserving the matched-geometry relationship already established in the grid.
- Gate the container behind an environment flag during rollout so QA can switch between layer-backed and SwiftUI-only implementations if alignment anomalies surface.
- Apply `matchedGeometryEffect` using the values embedded in `snapshot.chrome` and respect `snapshot.layout` for offsets, scale, mask radius, and backdrop opacity. The previous `DiscoveryDetailUniformCloseTransform` modifier is removed; instead the view reads `snapshot.layout.transform` (scale/offset/rotation) supplied by the coordinator and applies it directly, avoiding double transforms.

### 5.3 DiscoveryDetailView / Content

- Simplify `LayoutConfiguration` to carry only `cardSize`, `heroHeight`, `cornerRadius`, and `containerWidth`.
- Remove `contentOpacity`, `isChromeReady`, `isMarkdownReady`, `preferPlaceholderImage`. Those concepts move to the coordinator.
- `DiscoveryDetailContentView` listens to `snapshot.content` for markdown readiness and voiceover availability (already preloaded by coordinator in `.preparing`). It no longer depends on timers.
- Replace duplicated overlay stacks with `DiscoveryOverlayChrome`, parameterised by `snapshot.chrome`.
- Keep both hero and scroll chrome views mounted; `snapshot.chrome` provides separate payloads (e.g., `heroChrome` and `scrollChrome`) so opacity hand-offs stay smooth during matched-geometry swaps.
- Bridge `HeroScrollOffsetPreferenceKey` updates to the coordinator via a closure:
  ```swift
  .onPreferenceChange(HeroScrollOffsetPreferenceKey.self) { value in
      scrollBridge.update(offset: value)
  }
  ```
  ensuring scroll-driven hero elasticity continues to function.

## 6. State Machine Timeline

```
idle ──present──► preparing ──after first frame──► animatingIn
animatingIn ──openAnimation completion──► presented
presented ──drag begins──► interactiveDismiss ──release + threshold met──► closing ──animation end──► resetting ──cleanup──► idle
interactiveDismiss ──release + threshold not met──► presented
presented ──back button──► closing
```

- `preparing`: capture snapshot, compute baseline geometry, preload markdown + voiceover state.
- `animatingIn`: apply easing curve (`DiscoveryDetailHeroAnimator.openAnimation`), gradually raise overlay backdrop and chrome opacity.
- `presented`: hero at full size, chrome anchored to scroll.
- `interactiveDismiss`: hero follows drag metrics, chrome fades as needed.
- `closing`: run closing animation using recorded keyframe; hero image stays consistent until it reaches the card frame.
- `resetting`: remove overlay from view hierarchy, reveal hidden card, clear caches if needed.

## 7. Implementation Roadmap

1. **Scaffold coordinator module**
   - Create `Transitions` folder and add coordinator file.
   - Introduce foundational collaborators: `HeroSurfaceManager`, `ChromeStateReducer`, `GeometryPipeline`, and `AccessibilityBridge`. Each owns a focused slice of logic so the coordinator stays orchestration-focused.
   - Port existing geometry calculations into `GeometryPipeline` and its value types.
   - Define `OverlaySnapshot`, `HeroSurface`, `OverlayLayout`, `ChromeConfiguration`, `ContentState`, `ScrollState`, and `OverlayMeasurements`.
   - Model `HeroSurface.visibleCrop`, `cardCrop`, and `AspectTimeline` so crop/aspect easing is explicit in the API (implemented inside `HeroSurfaceManager`).
   - Extract `DiscoveryDetailUniformCloseTransform` math into a reusable helper consumed by `GeometryPipeline` (without changing behaviour yet).
   - Inject `VoiceoverPlaybackController` via the coordinator initializer so voiceover signalling lives in one place.

2. **Integrate coordinator into `DiscoveriesHomeView`**
   - Replace state vars with coordinator.
   - Update selection, drag, and dismissal handlers.
    - Introduce `@Namespace` for matched geometry if not already present and pass it through the coordinator.
    - Emit continuous geometry updates (`OverlayMeasurements`) from the host view.
    - Forward `HeroScrollOffsetPreferenceKey` updates into `detailCoordinator.updateScroll`.
    - Remove legacy `hiddenDiscovery` and voiceover toggles in favour of coordinator-driven snapshot data.
    - Capture the card’s frame (global CGRect) before hiding it via `hiddenDiscovery` and pass it to `detailCoordinator.present`; the coordinator freezes this rect until dismissal completes.

3. **Refactor overlay view hierarchy**
   - Update `DiscoveryDetailOverlayView` to consume snapshots.
- Simplify `DiscoveryDetailView` and `DiscoveryDetailContentView`; remove gating flags.
    - Add `DiscoveryOverlayChrome` view to unify header overlay rendering and bind matched-geometry roles to `ChromeConfiguration`. We retain two chrome instances (hero + scroll) but hand their opacities and matched-geometry roles to the coordinator so the swap occurs without a pop.
    - Add a `ScrollBridge` environment value or closure to route `HeroScrollOffsetPreferenceKey` changes to the coordinator.
    - Ensure the bridge ignores scroll updates until the coordinator snapshot reports `phase.isAnimatingInOrBeyond` to avoid early parallax calculations.

4. **Consolidate image pipeline**
   - Update `DiscoveryHeroHeaderView` to accept `HeroSurface`.
    - Move `DiscoveryImageLoader` ownership into the coordinator and share the same loader instance with any other views that need the asset; remove `DiscoveryCachedImage` usage inside the overlay hierarchy so images are only fetched once.
    - Decode images off the main thread using `preparingForDisplay()` / CoreGraphics blits before publishing to avoid animation hitches.
    - Ensure snapshot updates are published on the main actor with micro-timed fades (e.g., `withAnimation(.linear(duration: 0.12))` for image crossfade) and promotion of the new bitmap once the fade completes.
    - Apply normalized crop rects to both cached and high-res bitmaps so the crossfade never exposes a different aspect until the coordinator intentionally expands it.
    - Prototype `HeroSurfaceView` (CALayer-backed) to validate mask stability; fall back to pure SwiftUI only if the prototype proves unnecessary.
    - Run the `HeroSurfaceView` spike described in §4.3: integrate the CALayer renderer behind the feature flag, profile coordinate alignment, opacity/transform parity, and gesture handling, then decide whether to ship the CALayer path or keep the SwiftUI renderer for this iteration.
    - On dismissal or coordinator deinit, cancel outstanding loader tasks and release cached bitmaps that are no longer needed.

5. **QA & polish**
   - Verify tap-to-open, back dismissal, interactive dismissal on iPhone 15 simulator (and plus-size to catch safe-area edge cases).
    - Simulate rotation and split-view resizing to confirm `OverlayMeasurements` keep the hero aligned.
    - Exercise pull-down elasticity and parallax interactions to confirm `ScrollState` mirrors the prior experience.
    - Add logging hooks into coordinator to trace phase transitions (re-using `discoveryDetailHeroLogger` if helpful).
    - Confirm voiceover controller integration: the coordinator sets `voiceoverController.isDetailOverlayActive` in `present` and clears it in `resetting`.

## 8. Testing Strategy

- **Unit tests**: Add tests for `DiscoveryDetailTransitionCoordinator` to verify phase progression, hero geometry outputs given known inputs, drag threshold decisions (`interactiveDismiss` → `closing` vs. → `presented`), scroll-to-parallax mapping, and measurement coalescing.
- **Snapshot/UI tests**: Extend UITest plan (if available) to cover opening/closing animations, ensuring there is no chrome flicker using frame-by-frame assertions if possible. Add rotation & split-view test cases to confirm live measurements keep the hero aligned, plus a pull-down elasticity test to confirm chrome opacity matches expectations.
- **Manual QA**: Record simulator video for both open and gesture dismiss flows to confirm absence of jumps; test with slow network (simulate delayed asset load) to validate image crossfade; repeat under split-view/rotation and during aggressive scroll interactions to confirm geometry and parallax stability; profile with Instruments’ Core Animation to ensure the display link throttling behaves as intended.

## 9. Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Coordinator becoming a monolith | Keep responsibilities modular: extract `HeroGeometryCalculator`, `ChromeStateReducer`, etc., so coordinator orchestrates them. |
| Crossfade causes noticeable brightness shift | Optionally apply a brief blur or run through `UIView.transition` to soften swap. Guard behind feature flags for tuning. |
| Gesture metrics diverge from existing dismissal behaviour | Reuse `DiscoveryDetailDismissInteractor` logic inside coordinator; add golden tests matching current thresholds. |
| Dependency on cached snapshot | Continue eager caching in `DiscoveryCardImageView`. If a cache miss occurs, kick off the main-actor render described in §4.3 via `HeroSurfaceManager` while keeping the placeholder visible, then cross-fade the rendered snapshot when ready. Profile the render duration early and keep the off-screen card view lightweight to avoid jank. |
| HeroSurfaceView layer bridging regresses animation | Execute the spike in §4.3 / Step 4 to verify alignment, opacity, and gesture parity. If regressions appear, fall back to the SwiftUI renderer via the feature flag while addressing the gaps. |
| Geometry drift during rotations | Feed `OverlayMeasurements` on every `GeometryReader` change; add unit tests that simulate mid-animation size changes to ensure continuity. |
| Crop rendering regresses to flicker | Prototype `HeroSurfaceView` early; if SwiftUI-only cropping flickers, keep the CALayer-backed implementation. Add snapshot tests comparing card-aligned and expanded crops. |
| Snapshot publish loop overloads main thread | Enforce display-link throttling and tolerance checks; add diagnostics to log publish frequency during UI testing. |

## 10. Follow-up Work (Out of Scope)

- Wiring quick action buttons to creation flows.
- Shared transition infrastructure for other overlays (e.g., future map or collection overlays).
- Persisting voiceover playback progress across launches.
- Prototype `HeroSurfaceView` rendering path (CALayer masks vs. SwiftUI-only) to confirm crop stability before committing to implementation.

---

**Next Steps:** Implement Step 1 (scaffold coordinator and snapshot models), then iterate with the design team to validate transitions before refactoring the remaining overlay views. Let the team know if you need code sketches for the coordinator API or crossfade helpers.
