# Discovery Detail Animation Issues

## Flash At End Of Hero Transition (Resolved)

- **Symptom:** Opening a discovery or beginning/cancelling the close gesture produced a bright white flash over the hero image just as the animation settled.
- **Root Cause:** `DiscoveryDetailOverlayView` forced the hero to prefer the cached card placeholder whenever chrome wasn’t “ready” or a gesture started. That placeholder includes a light gradient, so every state change briefly swapped the hero from the real image back to the placeholder, causing the flash.
- **Fix:** Removed the placeholder preference plumbing (`preferPlaceholderImage`) so the hero continues displaying the resolved remote image throughout the animation. The placeholder still appears only if the image genuinely fails or hasn’t loaded yet.

## Notes

- If new animation artifacts appear, revisit the remaining suspects we identified earlier (card background opacity, collapse bookkeeping, corner masking) and test them individually.

## Overlay Chrome Late Reveal (In Progress)

- **Symptom:** The discovery title/metadata and gradient overlay still appear only after the hero card finishes its open animation, even though we now schedule the chrome reveal 70% into the timeline.
- **Desired Outcome:** The header chrome should begin animating in while the hero is still expanding so the user can read the title/description by the time the card settles, without rendering duplicate overlays.
- **What We Observed:** Coordinator logs show the `scheduleDetailSettled` work item firing 280 ms into the hero animation (`openDuration * 0.7`). Inside that closure `isContentReady` flips and `updateContentVisibility()` animates `contentOpacity`. However, because the hero animation is driven via `withAnimation`, `snapshot.progress` already equals 1.0 when the closure runs, and the chrome views that fade in live underneath the hero image.
- **What We Tried:** Reintroducing the hero overlay directly above the image did make the fade visible earlier, but it caused flicker because both the hero-level and scroll-level overlays rendered simultaneously during the handoff.
- **Suggested Next Step:** Keep a single overlay, but host it above the hero image (e.g., `.overlay` on `DiscoveryHeroHeaderView`) while the hero is animating, then hand it off to the scroll container once `isChromeReady` stabilizes—preserving the matched-geometry transition without double rendering. This would let the gradient/title become visible during the tail of the hero animation while staying a single source of truth.
