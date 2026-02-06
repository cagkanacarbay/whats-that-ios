# Phase 2 Testing Checklist: Remove PreservedStreamingState

Focused on Phase 2 changes (~20 tests). Not comprehensive — covers behavioral changes from PreservedStreamingState removal and audio modal dual options.

## A. Core Happy Paths (4 tests)

- [ ] 1. Camera tab → take photo → confirm → stream completes → X to dismiss → lands on Discoveries
- [ ] 2. Gallery tab → pick photo → confirm → stream completes → X to dismiss → lands on Discoveries
- [ ] 3. Camera tab → take photo → confirm → stream completes → audio modal appears (first discovery only)
- [ ] 4. Audio modal "Read This One First" → returns to streaming view

## B. "Discover More" from Streaming View (4 tests)

- [ ] 5. During streaming, tap "Discover More" → modal re-presents → camera picker opens → take photo → new flow starts
- [ ] 6. During streaming, tap "Discover More" → camera picker opens → cancel picker → **modal dismisses → land on Discoveries tab** (NEW behavior — previously restored streaming view)
- [ ] 7. After stream completes, tap "Discover More" → same as #5
- [ ] 8. Old discovery continues in background → appears in Discoveries feed (check after new discovery completes)

## C. Audio Modal Dual Options (4 tests)

- [ ] 9. Audio modal shows "Take a Photo" and "Upload Another" buttons (verify both visible)
- [ ] 10. Audio modal → "Take a Photo" → modal re-presents with camera → take photo → new flow starts
- [ ] 11. Audio modal → "Upload Another" → modal re-presents with gallery → pick photo → new flow starts
- [ ] 12. Audio modal → "Take a Photo" → cancel picker → modal dismisses → land on Discoveries

## D. Session Background Continuity (2 tests)

- [ ] 13. Start discovery → "Discover More" during streaming → old session completes → toast appears
- [ ] 14. Start discovery → X to dismiss during streaming → session completes in background → toast appears in Discoveries tab

## E. Credits & Intro Mode (3 tests)

- [ ] 15. With 0 credits: camera tab → credits exhausted modal appears inside flow modal
- [ ] 16. Credits exhausted → "Unlock More Stories" → purchase → balance updates → flow continues
- [ ] 17. Intro mode: 3rd free discovery completes → credits exhausted appears on next attempt

## F. Edge Cases (3 tests)

- [ ] 18. Rapid tab switching: tap Camera, immediately tap Gallery → no crash, single modal presents
- [ ] 19. "Discover More" → pick photo → confirm → retake → cancel retake → modal dismisses (verify no regression)
- [ ] 20. App background during streaming → foreground → stream resumes correctly

## Key Behavioral Change

**Test #6** is the critical behavioral change. Previously, cancelling the photo picker after "Discover More" would restore the streaming view showing the previous discovery. Now, the modal simply dismisses and the user lands on the Discoveries tab. The old discovery continues processing in the background and appears in the feed.
