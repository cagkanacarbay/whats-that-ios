# Discovery Detail Animation Issues

## Flash At End Of Hero Transition (Resolved)

- **Symptom:** Opening a discovery or beginning/cancelling the close gesture produced a bright white flash over the hero image just as the animation settled.
- **Root Cause:** `DiscoveryDetailOverlayView` forced the hero to prefer the cached card placeholder whenever chrome wasn’t “ready” or a gesture started. That placeholder includes a light gradient, so every state change briefly swapped the hero from the real image back to the placeholder, causing the flash.
- **Fix:** Removed the placeholder preference plumbing (`preferPlaceholderImage`) so the hero continues displaying the resolved remote image throughout the animation. The placeholder still appears only if the image genuinely fails or hasn’t loaded yet.

## Notes

- If new animation artifacts appear, revisit the remaining suspects we identified earlier (card background opacity, collapse bookkeeping, corner masking) and test them individually.
