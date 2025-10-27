# Discovery Detail Animation Issues

## Flash At End Of Hero Transition (Resolved)

- **Symptom:** Opening a discovery or beginning/cancelling the close gesture produced a bright white flash over the hero image just as the animation settled.
- **Root Cause:** `DiscoveryDetailOverlayView` forced the hero to prefer the cached card placeholder whenever chrome wasn’t “ready” or a gesture started. That placeholder includes a light gradient, so every state change briefly swapped the hero from the real image back to the placeholder, causing the flash.
- **Fix:** Removed the placeholder preference plumbing (`preferPlaceholderImage`) so the hero continues displaying the resolved remote image throughout the animation. The placeholder still appears only if the image genuinely fails or hasn’t loaded yet.

## Notes

- If new animation artifacts appear, revisit the remaining suspects we identified earlier (card background opacity, collapse bookkeeping, corner masking) and test them individually.

## Overlay Chrome Late Reveal (Done)

- **Symptom:** The discovery title/metadata and gradient overlay still appear only after the hero card finishes its open animation, even though we now schedule the chrome reveal 70% into the timeline.
- **Desired Outcome:** The header chrome should begin animating in while the hero is still expanding so the user can read the title/description by the time the card settles, without rendering duplicate overlays.
- **What We Observed:** Coordinator logs show the `scheduleDetailSettled` work item firing 280 ms into the hero animation (`openDuration * 0.7`). Inside that closure `isContentReady` flips and `updateContentVisibility()` animates `contentOpacity`. However, because the hero animation is driven via `withAnimation`, `snapshot.progress` already equals 1.0 when the closure runs, and the chrome views that fade in live underneath the hero image.
- **What We Tried:** Reintroducing the hero overlay directly above the image did make the fade visible earlier, but it caused flicker because both the hero-level and scroll-level overlays rendered simultaneously during the handoff.
- **Suggested Next Step:** Keep a single overlay, but host it above the hero image (e.g., `.overlay` on `DiscoveryHeroHeaderView`) while the hero is animating, then hand it off to the scroll container once `isChromeReady` stabilizes—preserving the matched-geometry transition without double rendering. This would let the gradient/title become visible during the tail of the hero animation while staying a single source of truth.

## Header Overlay Drift During Open (Done)

- Issue summary (original)

  - When opening a discovery from the grid, the header overlay (gradient + title/date/short description) is not pinned to the bottom of the hero image during the expansion. The image appears to "slide under" the gradient and only lines up at the very end of the animation.
  - Setting `chromeRevealFraction = 1` (reveal at the very end) hides the problem because the overlay only appears after the hero has fully expanded. Any earlier reveal makes the drift visible.
- What we tried (and what happened)

  - Parallax/headerOffset: Verified `headerOffset` is 0 during open by design. Enabling parallax during open made things worse; leaving it at 0 is correct. No fix.
  - Height alignment in Scroll header: Made the overlay header height equal to `imageHeight` (removed `+ safeAreaTopInset`). Drift persisted.
  - One-overlay approach in hero ZStack: Rendered a single overlay alongside `DiscoveryHeroHeaderView` (same ZStack, same `headerOffset`, `frame(height: heroImageHeight)`). Removed the ScrollView overlay and disabled crossfade. We still observed either (a) overlay not visible due to gating, or (b) perceived drift when shown earlier. No conclusive fix.
  - Crossfade removal: Forced `(hero: baseOpacity, scroll: 0)` in `resolvedOverlayOpacities` to eliminate flicker; this avoided handoff artifacts but did not solve alignment.
- Key learnings / hypotheses

  1. Layout pipeline mismatch is real: The grid-to-detail transition computes hero geometry in `DiscoveryDetailOverlayView` from `snapshot.progress`, safe-area, and container frames. The scroll header used a separate subtree and could drift; moving the overlay to the hero ZStack reduces, but did not eliminate, the symptom. That suggests the root cause isn’t only “two layout trees”.
  2. Height variables are not identical: The hero image uses `heroHeight = imageHeightForView + heroTopInset`. The overlay variants have used either `heroImageHeight` or `heroImageHeight + safeAreaTopInset`. A subtle mismatch (top-inset inclusion, pull-down, clamping) at any progress value will show up as a gap. We need to drive both hero and overlay from a single, exact value per frame (e.g., a single `heroHeaderHeight` and `heroImageHeight`) and ensure both apply identical offsets/masks.
  3. Timing/gating amplifies drift: Earlier reveal exposes transient misalignment while the hero still animates. The fact that `chromeRevealFraction = 1` hides the symptom indicates the overlay height/position is correct by the end state, but can be stale mid-transition.
  4. Safe-area computation may differ: We compute safe-area from both `GeometryReader.safeAreaInsets` and from the key window as a fallback. If these diverge mid-animation, `heroTopInset` and the overlay’s top accounting can disagree.
  5. MatchedGeometry is not the culprit (yet): We anchor `.bottom` and rely on consistent frames. Since the overlay and hero are not using matched-geometry relative to each other (image uses pure layout; overlay relies on frame sizing), any mismatch in their frame math will manifest as drift. If we move to a true matched pair between image and overlay container, we must ensure properties and transforms (offset/scale/clip) are applied consistently to both.
- Where the issue could be

  - Inconsistent height sources: Using `heroHeight` for the image vs `heroImageHeight` for the overlay. These must be the same logical height if the overlay is intended to sit on the image bottom at all times.
  - Safe-area/top inset resolution: `heroTopInset` derived from `proxy.safeAreaInsets.top` vs key-window top inset. Any branch differences during the open could change one side but not the other.
  - Progress-to-height lerp: `DiscoveryDetailHeroGeometry` computes `imageHeight` with lerp and clamping. If the overlay uses a derived/clamped value different from what the hero actually uses, they diverge until the end.
  - Opacity gating order: When overlay opacity flips on (based on `isChromeReady`/threshold), if its initial frame is evaluated before a subsequent hero-geometry recompute in the same frame, you can see a brief mismatch.
- Proposed next steps

  1. Single source of truth for hero dimensions: In `DiscoveryDetailOverlayView`, compute both `heroHeaderHeight` and `heroImageHeight` once per render and pass those exact values into a unified container that lays out both the hero image and overlay (no separate subtrees need to compute their own heights). Avoid mixing `heroHeight` and `heroImageHeight` in different places.
  2. Log geometry diffs during open: Add lightweight logs (or on-screen debug labels) of `(heroHeaderHeight, heroImageHeight, overlayFrame.height, safeAreaTop)` every frame while `progress < 1`. Confirm whether the overlay’s height lags behind the hero’s value.
  3. Normalize safe-area: Prefer a single safe-area source (likely key-window top inset) for the duration of the transition and pass it through explicitly (don’t read from different places in different subtrees).
  4. Verify transforms parity: Ensure any `offset/clip/mask` applied to the hero image is applied equivalently to the overlay container that should be pinned to it (or, better, make the overlay a child of the same container that owns the hero’s height/clip).
  5. Consider matched-geometry for the overlay container: If we still see a 1–2 frame lag, match the overlay container’s frame with the hero’s image container, not only anchoring `.bottom` but letting the system drive identical frame interpolation.
- Acceptance criteria for the final fix

  - With `chromeRevealFraction <= 0.3`, the overlay remains visually pinned to the bottom edge of the image throughout the open.
  - No duplicate overlays, no crossfade flicker, no visible jump at handoff.
  - No variance across devices with or without a notch (safe-area-top differences).

## Back Button Jump During Open (Unresolved)

- Summary

  - The custom back button (top-left control rendered by `DiscoveryDetailTopControls`) appears during the opening animation and then “jumps” upward a few frames later. Expected behavior: it should remain pinned relative to the hero image as the image expands, without abrupt positional changes.
- Current behavior and logs

  - The back button becomes visible when `isContentReady` flips to true (driven by `scheduleDetailSettled` inside `DiscoveryDetailTransitionCoordinator`). Shortly after appearing, it shifts upward by a small but noticeable amount.
  - Observed logs show repeated chrome-ready scheduling and multiple `isContentReady changed -> true` entries during a single open sequence:
    - `[Transition] scheduleDetailSettled delay=0.200000 phase=animatingIn`
    - `[Transition] chrome-ready triggered progress=1.000000 opacity=0.000000 phase=animatingIn`
    - `[Layout] isContentReady changed -> true` (repeated)
  - There is no visible change from our recent layout experiments; the issue persists identically.
- What we tried (and results)

  1. Unifying the top inset source for layout and controls
     - Change: Resolve a single `resolvedTopInset` (GeometryReader safe-area with key-window fallback) used for container frame math and for controls’ top padding.
     - Result: No visible change. The jump still occurs; logs still show repeated chrome-ready events.
  2. Anchoring controls to hero geometry
     - Change: Route the effective top inset from the layout to the controls instead of re-reading safe area at the controls level.
     - Result: No visible change. The position still nudges shortly after controls appear.
  3. Moving overlay/header around (related work)
     - Change: Tested overlay placement (hero ZStack vs. scroll header) and temporarily simplified the overlay crossfade to a single overlay.
     - Result: Helped diagnose overlay drift but did not affect the back button jump.
  4. Logging around content readiness
     - Change: Added logs for `isContentReady` flips and layout timing.
     - Result: Confirmed multiple “chrome-ready” triggers; the back button jump correlates with or follows these triggers, but persists even when inset calculations are unified.
- Likely culprits to investigate next

  1. Multiple coordinator instances or re-entrancy
     - Symptom: Repeated `scheduleDetailSettled` and `isContentReady changed -> true` suggest the coordinator might be instantiated more than once or “present” is being called multiple times. Each instance could re-insert the controls overlay, causing a brief re-layout.
     - Action: Add a coordinator UUID and log it for `present`, `scheduleDetailSettled`, and `isContentReady` flips to confirm single-instance behavior.
  2. Present re-entry from the view layer
     - Symptom: `presentPendingDiscoveryIfNeeded()` and `onSelect` could both call `present` within a close interval (e.g., on first load or when a pending ID resolves).
     - Action: Log all present calls from `DiscoveriesHomeView` with discovery ID and whether a presentation is already active. Debounce or guard more strictly if needed.
  3. Overlay insertion timing and implicit animation scope
     - Symptom: Controls are inserted with `.overlay(alignment: .topLeading)` and the card has `.animation(..., value: isChromeReady)`. When controls are inserted, any slight change in layout (header offset, safe area, scale) may be implicitly animated, causing a perceived jump.
     - Action: Temporarily remove or isolate the `.animation(..., value: isChromeReady)` on the card and the controls’ `.animation(..., value: layout.contentOpacity)` to see if the jump disappears.
  4. Scroll baseline initialization
     - Symptom: `DiscoveryDetailContentView` establishes a `baselineOffset` via a `GeometryReader` and updates `scrollOffset` once the preference publishes. If this fires just after controls appear, header offsets may change for one frame.
     - Action: Log the first `baselineOffset` value and its timestamp relative to `isContentReady`; confirm no header/offset update occurs immediately after controls appear.
  5. Safe-area resolution order
     - Symptom: The overlay container ignores the top safe area at the host level, while subviews derive safe area from `GeometryReader` and sometimes from key-window fallbacks. A frame or two of disagreement can bump top padding.
     - Action: For the duration of the open, fix a single safe-area top inset at the coordinator level and inject it; avoid per-subtree queries.
  6. Z-order and re-stacking
     - Symptom: On “chrome-ready,” a new hero card instance or overlay subtree could be inserted above the old one (or vice versa), momentarily affecting measurement or alignment.
     - Action: Confirm the hero card instance is stable across `isContentReady` changes; log identity or a stable ID for the card/overlay view hierarchy.
  7. Crossfade handoff and matched geometry
     - Symptom: The header overlay crossfades between hero-pinned and scroll-pinned states very late. If the controls appear precisely during this crossfade, a minor frame size or anchor difference could nudge layout.
     - Action: Delay controls until after the overlay handoff, or synchronize the controls to the same container used by the hero overlay during open.
  8. Image phase swap (placeholder → decoded image)
     - Symptom: Image loaders swapping phases can trigger a layout pulse. If this coincides with controls insertion, it looks like a jump.
     - Action: Log image phase changes and ensure height is entirely driven by the hero geometry (no intrinsic content changes during open).
  9. Rounding and pixel snapping at end-of-open
     - Symptom: At progress ≈ 1, final sizes/offsets round, which can shift the top-left origin by 1–2 px at the exact moment controls appear.
     - Action: Verify any rounding/clamping during hero open and apply the same rounding where the controls’ top padding is computed.
- Proposed verification plan (no functional changes yet)

  - Instrument coordinator identity and present calls (with discovery ID and timestamps) to confirm single flow per open.
  - Gate the card’s `.animation(value: isChromeReady)` temporarily and re-run to see if the jump is animation-scope related.
  - Log baseline scroll and header offsets around the exact frame `isContentReady` flips.
  - If controlled experiments point to overlay insertion/layout-scope animation, consider showing the controls only after a short post-chrome delay (e.g., +50–100 ms) or insert them in the same hero ZStack container for the duration of the open.
- Status

  - Done. Placement is pinned to the image bottom for the entire open/close flow with no obvious flicker or similar artifacts.

### Resolution

We removed cross-tree handoffs and kept a single overlay in the ScrollView subtree, driven directly by hero geometry from the overlay container.

- Single overlay only: no hero-mounted overlay, no crossfade handoff.
- Geometry source of truth (overlay container):
  - `heroVisibleHeight = heroImageHeight + heroTopInset`
  - `heroBottomGlobalY = containerFrameRaw.origin.y + geometry.offset.y + headerOffset + heroVisibleHeight` (parallax included)
  - Passed via `LayoutConfiguration` to the detail view.
- Pinning in ScrollView:
  - Overlay frame: `.frame(height: heroVisibleHeight)`
  - Overlay Y: `.offset(y: headerOffset - pullDownOffset)` (analytical; no runtime measurement)
  - No `.matchedGeometryEffect` on overlay; implicit size/position animations disabled so the overlay only fades.
- Opacity policy:
  - Shown from frame 0 (no chrome gating) and fades out smoothly with collapse during close.

### Experiment A — Remove scroll overlay matchedGeometryEffect (anchor .bottom)

- Goal: Determine if solo matched-geometry participation and `.bottom` anchor are introducing a transient frame/transform offset for the overlay during the open animation.
- Change:
  - File: `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/DiscoveryDetailView.swift:224-230`
  - Removed the `.matchedGeometryEffect(id:in:properties:anchor:isSource:)` modifier from the scroll overlay (`DiscoveryHeaderOverlayView`). No other logic changed. The overlay still faded according to `scrollOverlayOpacity`.
- Result (first attempt): No change. The header overlay still drifted during open. Conclusion: inconclusive because we later discovered we couldn’t reliably test that build.
- Rollback (first attempt): Restored the `.matchedGeometryEffect(...)` on the scroll overlay.
- Retry (current): Removed the `.matchedGeometryEffect(...)` again to re-test A under correct conditions.
- Result (retry): No change. The drift persisted. Rolled back by restoring `.matchedGeometryEffect(...)` on the scroll overlay.

### Experiment B — Add hero-mounted overlay during open (single-source crossfade)

- Goal: Eliminate a potential one-frame layout lag between the hero ZStack and the ScrollView subtree by rendering the overlay in the same container as the hero image during the open phase, then crossfading to the scroll overlay at settle.
- Change:
  - File: `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/DiscoveryDetailView.swift`
  - Lines near hero header (`~70-90`): Added `.overlay(alignment: .bottom) { ... }` on `DiscoveryHeroHeaderView` to render `DiscoveryHeaderOverlayView` with `frame(height: layout.heroImageHeight + layout.safeAreaTopInset)`, `opacity(layout.heroOverlayOpacity)`, and `allowsHitTesting(false)`.
  - File: same, lines `~224-230`: Restored the scroll overlay `.matchedGeometryEffect(...)` so the scroll overlay fades in via `scrollOverlayOpacity` while the hero overlay fades out via `heroOverlayOpacity`.
- Expected observation: The header overlay stays perfectly attached to the image bottom throughout the open animation. The crossfade avoids double-render flicker, and the scroll overlay takes over as the hero settles.
- Result: No change. The drift persisted. Rolled back the hero-mounted overlay and proceeded with Experiment A (retry).

### Experiment C — Add +1pt overlay height fudge (rounding test)

- Goal: Detect whether a rounding/sub-pixel mismatch between hero image height and overlay height causes the thin strip of image below the overlay during open.
- Change:
  - File: `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/DiscoveryDetailView.swift`
  - In `DiscoveryDetailContentView` header overlay, changed `.frame(height: headerOverlayHeight)` to `.frame(height: headerOverlayHeight + 1)` to intentionally overdraw the overlay by 1 point.
- Expected observation: If the gap disappears entirely, rounding mismatch is implicated and we should adopt a consistent pixel-alignment or shared rounding function for hero and overlay heights. If no change, rounding is less likely the culprit.
- Result: No change. The visible strip still appears during open. Rolled back the +1pt fudge.

### Experiment D — Gate safe-area contribution until chrome is ready

- Goal: Test whether a safe-area mismatch between the hero container and the scroll overlay contributes to the gap while the hero is still animating.
- Change:
  - File: `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/DiscoveryDetailView.swift`
  - In `DiscoveryDetailContentView` body, introduced local values:
    - `overlayHeight = imageHeight + (isChromeReady ? safeAreaTopInset : 0)`
    - `layoutHeight = overlayHeight + pullDownOffset`
  - Switched the header containers to use these:
    - Spacer container: `.frame(height: layoutHeight)` (was `headerLayoutHeight`)
    - Overlay gradient: `.frame(height: overlayHeight)` (was `headerOverlayHeight`)
- Expected observation: During open (when `isChromeReady == false`), the overlay ignores the top safe-area, matching the hero’s visible bottom edge and eliminating the thin gap. After chrome-ready, behaviour matches current layout.
- Result: No change. The drift persisted. Rolled back the safe-area gating.

### Experiment E — Force `headerOffset` to 0 until chrome ready

- Hypothesis: The hero image applies `layout.headerOffset` during open, but the scroll overlay does not. If `headerOffset` becomes negative from early scroll preference readings, the hero image shifts up while the overlay remains fixed, exposing a strip of image below the overlay.
- Change:
  - File: `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/DiscoveryDetailOverlayView.swift`
  - In the geometry block, changed `headerOffset` computation to zero out until `isChromeReady`:
    - Before: `let headerOffset = (snapshot.isClosing || snapshot.isInteracting) ? 0 : min(scrollOffset, 0) * (1 - collapseProgress)`
    - After:  `let headerOffset = { if snapshot.isClosing || snapshot.isInteracting || !isChromeReady { return 0 } ; return min(scrollOffset, 0) * (1 - collapseProgress) }()`
- Expected observation: The hero header no longer shifts relative to the overlay during open; the overlay appears attached to the bottom of the image throughout the expansion.
- Result: No change. The drift persisted. Rolled back the `!isChromeReady` gating for `headerOffset`.

### Experiment F — Apply headerOffset to scroll overlay during open

- Hypothesis: The hero image applies a negative `headerOffset` early due to scroll preference emissions; the scroll overlay did not. Applying the same offset to the overlay during open should keep them aligned.
- Change:
  - File: `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/DiscoveryDetailView.swift`
  - In `DiscoveryDetailContentView`, added an offset to the overlay:
    - `.offset(y: (!isChromeReady ? min(scrollOffset, 0) : 0))`
- Expected observation: The overlay tracks the hero image if a negative offset appears early, eliminating the visible strip during open. After chrome-ready, behaviour reverts to current (no offset at rest).
- Result: No change. The drift persisted. Rolled back the overlay `.offset(...)` addition.

### Experiment G — Pixel-align hero image and overlay heights during open

- Hypothesis: Sub-pixel rounding between the hero image height and the overlay height introduces a 0.5–1 px gap that’s visible mid-animation.
- Change:
  - File: `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/DiscoveryDetailOverlayView.swift`
  - In the geometry block, aligned heights to device pixels using `UIScreen.main.scale`:
    - `imageHeightAligned = floor(imageHeightForView * scale) / scale`
    - `heroTopInsetAligned = floor((safeAreaTopInsetRaw) * scale) / scale`
    - `heroHeaderHeight = imageHeightAligned + heroTopInsetAligned`
  - Passed `imageHeightAligned` and `heroTopInsetAligned` into `DiscoveryDetailView.LayoutConfiguration` for `heroImageHeight` and `safeAreaTopInset` respectively.
- Expected observation: With pixel snapping, the overlay bottom should no longer reveal a sub-pixel strip of the hero image as the animation progresses.
- Result: No change. The drift persisted. Rolled back pixel-alignment changes to restore original height math.

### Experiment H — Change matchedGeometryEffect anchor from `.bottom` to `.center`

- Hypothesis: Using `.bottom` anchor for an overlay without a visible matched counterpart might bias the frame transform during open. Switching to `.center` could eliminate any anchor-related offset.
- Change:
  - File: `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/DiscoveryDetailView.swift`
  - In `DiscoveryDetailContentView` overlay, changed `.matchedGeometryEffect(..., anchor: .bottom, ...)` to `.matchedGeometryEffect(..., anchor: .center, ...)`.
- Expected observation: If the anchor choice contributes to drift, setting it to `.center` should keep the overlay locked to the perceived image center and reduce bottom-edge gaps during open.
- Result: No change. The drift persisted. Rolled back to `.bottom` anchoring.

### Experiment I — Single-tree overlay during open (no ScrollView overlay)

- Hypothesis: The large gap comes from cross-tree layout timing (hero container vs. ScrollView). Rendering the overlay only inside the hero header (same tree) during open should keep it glued to the image bottom.
- Change:
  - File: `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/DiscoveryDetailView.swift`
  - On `DiscoveryHeroHeaderView`, added `.overlay(alignment: .bottom)` that renders `DiscoveryHeaderOverlayView` when `!layout.isChromeReady`, with `.frame(height: layout.heroHeight)` and `.opacity(1)`.
  - Kept the ScrollView overlay as-is, which remains effectively hidden until chrome-ready per coordinator logic.
- Expected observation: During open, the overlay is pinned precisely to the hero image bottom. After settle, the ScrollView overlay takes over without visible misalignment.
- Observation: The hero-mounted gradient appears immediately and is correctly placed at the image bottom. Shortly after, a second overlay (the ScrollView overlay) fades in "from above" and we return to the misaligned state. The sequence matches the three screenshots provided (bottom-pinned gradient only → gradient+title with second gradient behind → only the upper gradient remains).
- Rollback: Removed the hero-mounted overlay to prepare for the next architectural change discussion.

## Proposed Direction — Single Overlay Hosted in the Hero Container

Observation
- Hosting the overlay inside the hero container eliminates the drift during the open phase because the overlay shares the hero image’s coordinate space and timing. The gradient is visibly correct when drawn there.

Proposal
- Make the header overlay a single view rendered in the hero container (not inside the ScrollView subtree). This removes cross-tree timing and layout discrepancies that cause the overlay to appear to "float" above the image.

Architectural feasibility analysis
- Layering/z-order:
  - Today, `DiscoveryDetailView` renders `DiscoveryHeroHeaderView` first, then `DiscoveryDetailContentView` on top. The ScrollView overlay sits inside the content subtree. To keep a single overlay hosted with the hero image and visible above content, we must render the overlay in a higher z-order than the ScrollView (e.g., a top-level `.overlay` in `DiscoveryDetailView`, or placing the overlay immediately above the hero in the ZStack and ensuring it remains above the content with `.zIndex`).
  - The overlay must clip to the same rounded rectangle mask as the card shell to avoid spillover.
- Scroll behavior:
  - As the user scrolls, the overlay can either (a) remain pinned to the image bottom and fade out at a threshold, or (b) transition into a compact, scroll-affixed variant. If we insist on “one overlay” only, option (a) is simpler: keep the overlay above content during rest and diminish its opacity with scroll to reveal body text. Option (b) is possible with a single view if the overlay’s position is driven by `scrollOffset` so it moves from the hero-bottom anchor to a fixed position, but that increases complexity and requires precise transforms rather than re-parenting.
- Gesture/dismiss interaction:
  - During interactive dismiss, the hero card translates/scales/rotates as a unit. An overlay hosted with the hero will follow exactly, which is desirable and consistent with your “always attached” requirement.
- Accessibility and hit-testing:
  - With the overlay rendered above the ScrollView, its buttons (share/map) remain tappable; ensure hit-testing is enabled only while visible and that accessibility focus doesn’t conflict with content beneath. When fading the overlay, also reduce hit-testing to prevent overlap issues.
- Performance:
  - A single overlay reduces duplicate rendering and crossfade bookkeeping. Keep gradient simple and text layout pre-measured to avoid layout churn mid-animation.
- Safe-area/rations:
  - Drive overlay height and bottom position from the same values used by the hero image: `heroImageHeight` and `safeAreaTopInset`. Avoid recomputation in a separate subtree.

Effects and tradeoffs
- Pros: Removes drift, removes duplicate overlays and handoff timing, makes the open animation visually robust and predictable.
- Cons: If we want the overlay to scroll away with content post-open, we need to animate its position/opacity based on `scrollOffset` rather than handing off to a scroll-pinned overlay. This changes current behavior slightly but can be designed to match the visual spec.

Implementation sketch (for later; do not implement yet)
- Render `DiscoveryHeaderOverlayView` in `DiscoveryDetailView` as a sibling above the hero image with `.overlay(alignment: .bottom)` and a higher `.zIndex` than the ScrollView.
- Bind its height and position to `heroImageHeight` + `safeAreaTopInset` and to `headerOffset` for parallax if needed.
- Control opacity with `heroOverlayOpacity` during open, then fade down with scroll (e.g., based on `scrollOffset`) post-open, leaving only the body text visible.
- Remove the ScrollView overlay entirely; eliminate the matched-geometry effect.

Open questions
- Should the overlay remain visible at rest after open, or fade out once body content enters? If it remains, how does it interact with top controls? This needs design confirmation.
- If we retain a scroll-affixed variant later (e.g., a compact title bar), we can still implement it as a state of the same overlay view positioned via transforms instead of introducing a second subtree.

## Alternative Direction — Keep Overlay in ScrollView, Drive It with Hero Coordinates

Goal
- Keep the overlay in its current parent (the ScrollView subtree) but compute its height and vertical offset from the hero image’s actual geometry, so the overlay stays attached to the image bottom throughout open without re‑parenting.

Why this could work
- The hero’s size/offset during open is already computed deterministically in the overlay container (`DiscoveryDetailOverlayView`) via `DiscoveryDetailHeroGeometry` plus gesture deltas. If the ScrollView overlay derives its layout directly from those hero coordinates (instead of its own subtree’s measurements), it can pin itself to the same bottom edge every frame.

Two viable implementation paths (non‑exclusive)
1) AnchorPreference measurement pipeline
   - Add an `Anchor<CGRect>` preference on the hero image container (or a transparent marker view anchored to the image bottom) inside `DiscoveryDetailView`.
   - Name a shared coordinate space at the overlay root (e.g., `.coordinateSpace(name: "overlay-root")`).
   - In the ScrollView header, read the anchor via a `GeometryReader` using that coordinate space and compute:
     - `heroBottomY = proxy[anchor].maxY`
     - `overlayContainerBottomY = proxy.frame(in: .named("overlay-root")).maxY`
     - `overlayYOffset = heroBottomY - overlayContainerBottomY`
   - Drive the overlay with:
     - `.frame(height: heroVisibleHeight)` where `heroVisibleHeight = proxy[anchor].height`
     - `.offset(y: overlayYOffset)` so the overlay bottom matches the hero bottom exactly.
   - Notes/risks:
     - Anchor preferences reflect layout, not post‑layout transforms. If we keep 3D rotation/scale on the hero during open, the anchor might not include those transforms. If that becomes an issue, prefer Path 2 below.

2) Single‑source hero geometry from the overlay (no live measuring)
   - Reuse the geometry the overlay already computes each frame:
     - `containerFrame` (global), `geometry.offset.y`, `imageHeight`, `heroTopInset`, collapse/gesture deltas.
   - Pass down to the ScrollView header the following values through the existing `LayoutConfiguration`:
     - `heroBottomGlobalY = containerFrame.minY + geometry.offset.y + heroTopInset + imageHeight`
     - `heroVisibleHeight = heroTopInset + imageHeight`
   - In the ScrollView header, compute its own container bottom in the same global space and derive the exact offset:
     - `overlayContainerBottomGlobalY = …` via a `GeometryReader` on the header container in `.global` or the named overlay coordinate space.
     - `overlayYOffset = heroBottomGlobalY - overlayContainerBottomGlobalY`
   - Apply:
     - `.frame(height: heroVisibleHeight)` (no recomputation inside the scroll subtree)
     - `.offset(y: overlayYOffset)` (pins overlay to hero bottom)
   - Notes/risks:
     - Avoid preference write loops by updating these values only from the overlay container (which already ticks per progress), not from the ScrollView subtree.
     - Ensure both sides use the same coordinate space (recommend `.global` or a single named space defined at the overlay root).

Additional considerations
- Progress gating: Update the ScrollView overlay using hero geometry throughout open and interactive dismiss; once fully presented, you can transition to a simpler rule (e.g., no offset adjustments) if desired.
- Parallax/pull‑down: Because these already factor into `geometry.offset` and the computed `heroTopInset`, Path 2 naturally accounts for them. Path 1 needs to ensure you anchor the exact view that experiences those offsets.
- Top controls: Keep as‑is; they already sit above and fade with content opacity.
- Performance: Path 2 is cheaper at runtime (no live measuring), since you reuse the overlay’s existing geometry. Path 1 is more WYSIWYG but can be sensitive to transforms.

Pros
- No re‑parenting of the overlay (keeps current view organization and scrolling behavior intact).
- Eliminates timing drift by making the ScrollView overlay a visual follower of the hero geometry.

Cons / Risks
- Path 1 may not pick up transforms applied after layout (e.g., 3D rotation) — you may still see small discrepancies during those phases.
- Path 2 requires threading global coordinates to the header and computing deltas carefully to avoid off‑by‑insets and coordinate space mistakes.

High‑level implementation steps (Path 2 recommended)
1. In `DiscoveryDetailOverlayView`, compute and package:
   - `heroVisibleHeight`, `heroBottomGlobalY`, and `overlayRootGlobalOriginY` (from `containerFrame`).
   - Add to `LayoutConfiguration` (or a small `OverlayGeometry` struct) and pass into `DiscoveryDetailView`.
2. In `DiscoveryDetailContentView` header container:
   - Read its own bottom in the same coordinate space via a `GeometryReader`.
   - Compute `overlayYOffset = heroBottomGlobalY - overlayContainerBottomGlobalY`.
   - Set the overlay gradient: `.frame(height: heroVisibleHeight)` and `.offset(y: overlayYOffset)`.
3. Remove local re‑computations of `headerOverlayHeight` and any matched‑geometry on the overlay.
4. Verify during open, close, and interactive dismiss.

Acceptance criteria
- During open, the overlay stays visually attached to the expanding image bottom with no visible gap.
- No double overlay or crossfade artifacts; only one overlay is rendered.
- Close and interactive dismiss behave the same; the overlay follows the hero.

---

## Applied Solution (Path 2) — Scroll Overlay Driven by Hero Geometry

Changes relative to the starting state

- Single overlay only (removed hero overlay during open):
  - Removed any hero‑mounted overlay instances and the crossfade handoff. The ScrollView overlay is the single source of truth.
  - File: `.../DiscoveryDetailView.swift` (ContentView overlay) — deleted `.matchedGeometryEffect(...)` on the overlay and kept a single overlay view.

- Pass hero geometry to the Scroll overlay:
  - File: `.../DiscoveryDetailOverlayView.swift`
    - Compute hero geometry each frame: `heroVisibleHeight = heroImageHeight + heroTopInset`.
    - Compute hero bottom in global space and include parallax: `heroBottomGlobalY = containerFrameRaw.origin.y + geometry.offset.y + headerOffset + heroVisibleHeight`.
    - Add both to `LayoutConfiguration` (`heroVisibleHeight`, `heroBottomGlobalY`).
  - File: `.../DiscoveryDetailView.swift`
    - Thread `heroVisibleHeight` and `heroBottomGlobalY` into `DiscoveryDetailContentView`.

- Pin overlay to hero bottom using global coordinates:
  - File: `.../DiscoveryDetailView.swift` (ContentView)
    - Measure the header container bottom in `.global` via `HeaderContainerBottomPreferenceKey`.
    - Compute `overlayYOffset = heroBottomGlobalY − headerContainerBottomGlobalY` (applied only during open).
    - Set overlay layout: `.frame(height: heroVisibleHeight)` and `.offset(y: overlayYOffset)`.
    - Disable implicit animations for position/size: `.animation(nil, value: overlayYOffset)`, `.animation(nil, value: heroVisibleHeight)`, and `.transaction { $0.animation = nil }`.

- Opacity policy (no chrome gating, smooth close):
  - File: `.../DiscoveryDetailOverlayView.swift` — `resolvedOverlayOpacities(...)`
    - Show overlay from frame 0 (no dependency on `isChromeReady`).
    - Keep overlay during close and fade with collapse progress.
    - Include `headerOffset` in the hero bottom calculation to avoid parallax jumps.

Current status (resolved)

- Placement is correct and stable; overlay remains pinned to the image bottom across open/close and interactive dismiss.
- No mid‑image “ghost” frame; no cross‑tree drift.
- No obvious flicker or similar artifacts under normal operation.
### Changes J–L — Flicker and Slide-in cleanup

- J: Show overlay from frame 0 (no chrome gating)
  - Rationale: We no longer render a hero overlay; gating the scroll overlay caused an early pop.
  - Code: `DiscoveryDetailOverlayView.resolvedOverlayOpacities` now returns `(hero: 0, scroll: baseOpacity)` regardless of `isChromeReady` (except close/interaction cases).

- K: Include `headerOffset` in hero bottom calculation
  - Rationale: Avoid mid-animation re-alignment when parallax kicks in.
  - Code: `heroBottomGlobalY = containerFrameRaw.origin.y + geometry.offset.y + headerOffset + heroVisibleHeight`.

- L: Keep overlay visible during close, fade with collapse
  - Rationale: Removing the overlay immediately at close start produced a flash.
  - Code: For `isClosing`, `resolvedOverlayOpacities` now returns `(hero: 0, scroll: baseOpacity * (1 - collapseProgress))`.

- Prevent slide-down animation of the overlay
  - Rationale: The overlay visually slid from the middle to the bottom when its position snapped to hero coordinates.
  - Code (ScrollView overlay): disabled animations for geometry-driven changes via `.animation(nil, value: overlayYOffset)`, `.animation(nil, value: heroVisibleHeight)`, and `.transaction { $0.animation = nil }`.
