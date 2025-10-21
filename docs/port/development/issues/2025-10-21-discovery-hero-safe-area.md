# 2025-10-21 – Discovery Hero Safe-Area Strip

## Context
- Change: moved the hero header image for `DiscoveryHeroContentView` inside the detail `ScrollView` so the full hero presentation scrolls with the content.
- Additional tweak: offset the embedded header by the top safe-area inset and called `.ignoresSafeArea(.top)` so the image would visually extend under the top edge.

## Observed Regression
- Result: both the hero animation and the settled detail view now show a white strip above the image.
- Prior behaviour: the animation rendered without the strip because the hero header lived in an overlay that ignored the top inset.
- Current behaviour: the scroll view respects the top inset before the overlay adjustment, and the overlay compensation applies only once the header is inside the scroll content. The hero overlay path still renders its background using the original geometry that assumes a top inset of `0`, so both paths leave a strip.

## Root Cause
- In the hero overlay (`DiscoveryHeroOverlay`), `HeroGeometry` calculates its frames relative to the container bounds that already exclude the safe-area top inset. When we add the header to the scroll content and then stretch it by `safeAreaTopInset`, the overlay still draws the background at the old origin. The result is mismatched origins between the overlay container and the header, manifesting as the visible white strip.

## Hypothesis For Fix
1. Ensure the hero overlay’s root `ZStack` ignores the top safe area so the animated card starts at `y = 0` from the top screen edge. (Today only the scroll-content path compensates.)
2. Alternatively, keep the header inside the scroll view but apply a negative top padding equal to `safeAreaTopInset` before the background is applied. That shifts the rendered content up while preserving scroll behaviour.
3. Adjust `HeroGeometry` so it factors in `safeAreaTopInset` when resolving `offset.y` while the hero is open, aligning the animated card with the new scroll layout.

## Next Steps
- Prototype option 1 first (ignore safe area on the animated container) since it mirrors the original overlay behaviour and should keep the card firmly against the top edge.
- If that fails, fall back to option 2 by adding `padding(.top, -safeAreaTopInset)` to the scroll container to counteract the default inset without disturbing gesture math.
- Adjust `HeroGeometry` so it factors in `safeAreaTopInset` when resolving `offset.y` while the hero is open, aligning the animated card with the new scroll layout.

## Experiment Log – 2025-10-21
- Implemented hypothesis #2: shifted the hero detail scroll view upward by applying `.padding(.top, -safeAreaTopInset)` and removed the earlier safe-area offsets/extra height from `DiscoveryHeroHeaderView`. The intent is to let both the settled view and the hero animation render the image flush with the top edge, without reintroducing a gap. Result: still saw the white strip, so iterated again.
- Implemented hypothesis #3: restored the hero-header overlay (outside the scroll view), binding its vertical offset to the live scroll position while expanding its height by the top inset. The scroll content now keeps only a placeholder for the header image, so the entire hero card should translate upward with the scroll gesture without leaving a white strip. This should also preserve the stretch effect when pulling down.
- Pending verification in the simulator: confirm that the animation and settled view both align the image with the very top of the screen after this adjustment.
