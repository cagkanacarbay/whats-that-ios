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
2. Managing hero imagery through a single `HeroSurface` object that can smoothly swap to the high-resolution asset once available.
3. Computing deterministic geometry (`HeroGeometry` and `OverlayLayout`) for every frame of the transition, including interactive drag updates.
4. Driving chrome placement, opacity, and matched-geometry handoffs based on `Phase`.
5. Exposing a single `@Published` `OverlaySnapshot` consumed by `DiscoveryDetailOverlayView`.

`DiscoveriesHomeView` no longer orchestrates animation details. Instead, it:

- Creates a `@StateObject var detailCoordinator`.
- Invokes coordinator methods (`present`, `updateDrag`, `endDrag`, `dismiss`) based on user interactions.
- Renders `DiscoveryDetailOverlayView` only when `coordinator.snapshot.phase.isActive` is true.

```
DiscoveriesHomeView
  └─ DiscoveryDetailTransitionCoordinator
        ├─ HeroSurface (UIImage + metadata)
        ├─ HeroGeometry (start/end frames, corner radius)
        ├─ ChromePlacement (hero or scroll)
        └─ OverlaySnapshot (published)
             ├─ phase
             ├─ layout (hero rect, mask radius, shadow, backdrop opacity)
             ├─ heroSurface (single image reference)
             ├─ chromeConfiguration (placement, opacity, matched-geometry id)
             └─ contentState (markdown + voiceover readiness flags)
```

## 4. Component Breakdown

### 4.1 DiscoveryDetailTransitionCoordinator

**Location:** `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/Transitions/DiscoveryDetailTransitionCoordinator.swift`

**Responsibilities**
- Capture the tapped card snapshot from `DiscoveryDetailImageCache` and build the initial `HeroSurface`.
- Resolve `HeroGeometry` by combining the card's start frame, container metrics, and target layout constants (existing math from `DiscoveryDetailHeroGeometry`).
- Publish `OverlaySnapshot` updates on the main actor.
- Track asynchronous tasks (image loading, markdown parsing if needed) and merge their results into snapshots without flicker.
- Record `closeKeyframe` data when the gesture ends so the closing animation starts from the exact interactive pose.

**Primary API**
```swift
final class DiscoveryDetailTransitionCoordinator: ObservableObject {
    @Published private(set) var snapshot: OverlaySnapshot = .idle

    func present(discovery: DiscoverySummary, cardFrame: CGRect, imageURL: URL?, containerSize: CGSize, safeAreaInsets: EdgeInsets)
    func updateDrag(gesture: DragGesture.Value)
    func endDrag(gesture: DragGesture.Value)
    func dismiss(reason: DismissReason)
    func resetIfNeeded()
}
```

`DismissReason` differentiates between back button and gesture completion so the coordinator can choose appropriate closing keyframes.

### 4.2 OverlaySnapshot

**Structure**
```swift
struct OverlaySnapshot {
    let phase: Phase
    let layout: OverlayLayout
    let hero: HeroSurface
    let chrome: ChromeConfiguration
    let content: ContentState
    let accessibility: AccessibilityState
}
```

- `OverlayLayout`: hero frame, corner radius, scale, shadow, backdrop opacity.
- `HeroSurface`: `UIImage`, preferred content mode (`.fill`/`.fit`), baseline aspect ratio.
- `ChromeConfiguration`: opacity, placement anchor (`.hero`/`.scroll`), matched-geometry id, gradient parameters.
- `ContentState`: markdown readiness, voiceover button visibility (preloaded in `preparing` phase).
- `AccessibilityState`: boolean for VoiceOver adjustments already handled by the current controller.

### 4.3 HeroSurface lifecycle

1. On `present`, the coordinator requests the cached snapshot (`DiscoveryDetailImageCache.shared.image(for:)`). If missing, it uses a synchronous render of the card view fallback.
2. It constructs `HeroSurface(image: snapshot, contentMode: .fill)` and publishes the first snapshot in phase `.preparing`.
3. It triggers `DiscoveryCachedImage` to fetch the signed asset. When the fetch completes, the coordinator replaces `HeroSurface.image` with the high-resolution bitmap using a short crossfade (two successive snapshots to animate opacity). Because the `Image(uiImage:)` identity remains stable, SwiftUI does not flash between two separate views.

### 4.4 Chrome handling

- A new `DiscoveryOverlayChrome` view wraps the existing `DiscoveryHeaderOverlayView` layout. It accepts `ChromeConfiguration` and the discovery data.
- `chrome.anchor` tells the chrome whether to render inside the hero overlay or pinned to the scroll content.
- Matched geometry is handled within this single view using `matchedGeometryEffect(id: chromeNamespaceId, in: namespace, properties: .frame, anchor: .bottom, isSource: chrome.anchor == .hero)`.
- Opacity transitions are driven by the coordinator: `chrome.opacity = coordinator.snapshot.chrome.opacity`. The coordinator ramps this from 0 → 1 during `.animatingIn`, holds at 1 for `.presented`, and fades to 0 when entering `.closing`.

### 4.5 Gesture flow

- `updateDrag` moves the coordinator to `.interactiveDismiss`, recomputes `OverlayLayout` using the drag metrics from `DiscoveryDetailDismissInteractor`.
- `endDrag` decides between `.closing` (if thresholds met) or a spring back to `.presented`. Because the coordinator tracks the hero pose at the moment the gesture ended, the closing animation interpolates smoothly without aspect ratio jumps.
- During `.interactiveDismiss`, `HeroSurface` is not swapped and `OverlayLayout` continues to respect the expanded aspect ratio, preventing the immediate “shorten” effect.

## 5. View Layer Changes

### 5.1 DiscoveriesHomeView

- Replace the existing `@State` collection with:
```swift
@StateObject private var detailCoordinator = DiscoveryDetailTransitionCoordinator()
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
- `detailEdgeDragGesture` delegates to `detailCoordinator.updateDrag` / `endDrag`.
- Overlay presentation reads `detailCoordinator.snapshot` to decide whether to render `DiscoveryDetailOverlayView`.
- Card hiding uses `detailCoordinator.snapshot.activeDiscoveryId` (exposed via `OverlaySnapshot`) instead of separate `HiddenDiscovery`.

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
- Render hero image as:
```swift
Image(uiImage: snapshot.hero.image)
    .resizable()
    .aspectRatio(snapshot.hero.aspectRatio, contentMode: snapshot.hero.contentMode)
```
- Apply `matchedGeometryEffect` for the chrome using `snapshot.chrome`.

### 5.3 DiscoveryDetailView / Content

- Simplify `LayoutConfiguration` to carry only `cardSize`, `heroHeight`, `cornerRadius`, and `containerWidth`.
- Remove `contentOpacity`, `isChromeReady`, `isMarkdownReady`, `preferPlaceholderImage`. Those concepts move to the coordinator.
- `DiscoveryDetailContentView` listens to `snapshot.content` for markdown readiness and voiceover availability (already preloaded by coordinator in `.preparing`). It no longer depends on timers.

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
   - Port existing geometry calculations into coordinator-owned helpers.
   - Define `OverlaySnapshot`, `HeroSurface`, `OverlayLayout`, `ChromeConfiguration`, `ContentState`.

2. **Integrate coordinator into `DiscoveriesHomeView`**
   - Replace state vars with coordinator.
   - Update selection, drag, and dismissal handlers.
   - Introduce `@Namespace` for matched geometry if not already present.

3. **Refactor overlay view hierarchy**
   - Update `DiscoveryDetailOverlayView` to consume snapshots.
   - Simplify `DiscoveryDetailView` and `DiscoveryDetailContentView`; remove gating flags.
   - Add `DiscoveryOverlayChrome` view to unify header overlay rendering.

4. **Consolidate image pipeline**
   - Update `DiscoveryHeroHeaderView` to accept `HeroSurface`.
   - Adjust `DiscoveryCachedImage` usage so the coordinator triggers loading and handles the finished bitmap swap.
   - Ensure snapshot updates are published on the main actor with micro-timed fades (e.g., `withAnimation(.linear(duration: 0.08))` for image crossfade).

5. **QA & polish**
   - Verify tap-to-open, back dismissal, interactive dismissal on iPhone 15 simulator (and plus-size to catch safe-area edge cases).
   - Add logging hooks into coordinator to trace phase transitions (re-using `discoveryDetailHeroLogger` if helpful).
   - Confirm voiceover controller integration: the coordinator sets `voiceoverController.isDetailOverlayActive` in `present` and clears it in `resetting`.

## 8. Testing Strategy

- **Unit tests**: Add tests for `DiscoveryDetailTransitionCoordinator` to verify phase progression, hero geometry outputs given known inputs, and drag threshold decisions (`interactiveDismiss` → `closing` vs. → `presented`).
- **Snapshot/UI tests**: Extend UITest plan (if available) to cover opening/closing animations, ensuring there is no chrome flicker using frame-by-frame assertions if possible.
- **Manual QA**: Record simulator video for both open and gesture dismiss flows to confirm absence of jumps; test with slow network (simulate delayed asset load) to validate image crossfade.

## 9. Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Coordinator becoming a monolith | Keep responsibilities modular: extract `HeroGeometryCalculator`, `ChromeStateReducer`, etc., so coordinator orchestrates them. |
| Crossfade causes noticeable brightness shift | Optionally apply a brief blur or run through `UIView.transition` to soften swap. Guard behind feature flags for tuning. |
| Gesture metrics diverge from existing dismissal behaviour | Reuse `DiscoveryDetailDismissInteractor` logic inside coordinator; add golden tests matching current thresholds. |
| Dependency on cached snapshot | Ensure `DiscoveryCardImageView` caches the bitmap. On cache miss, synchronously render a thumbnail or fall back to the loading gradient with a short delay to avoid blank hero. |

## 10. Follow-up Work (Out of Scope)

- Wiring quick action buttons to creation flows.
- Shared transition infrastructure for other overlays (e.g., future map or collection overlays).
- Persisting voiceover playback progress across launches.

---

**Next Steps:** Implement Step 1 (scaffold coordinator and snapshot models), then iterate with the design team to validate transitions before refactoring the remaining overlay views. Let the team know if you need code sketches for the coordinator API or crossfade helpers.
