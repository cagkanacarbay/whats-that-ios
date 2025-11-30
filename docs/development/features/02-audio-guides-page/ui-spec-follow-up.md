Result time: 2025-11-29

# Audio Guides – UI Spec Follow-up

## Decisions (locked-in)
- No separate sneak peek card; Up Next itself conveys what’s coming.
- Row slide gesture adds to end of queue (not “Play next”).
- Hero: no prev/next thumbnail flanks; keep artwork + ring + core controls + meta only.
- Auto-play toggle is needed; place near hero controls.

## To discuss (UX/design)
- Discover list actions: layout for `Play next` vs `Add to end`; swipe accelerator pattern given slide is reserved for add-to-end; density and control placement.
- Row slide feedback: haptic/toast when adding to queue tail; consistency between Discover and Up Next.
- Up Next behaviors: drag-to-reorder; swipe-to-remove; swipe-to-add; tap vs “pull to front” for immediate play; showing “Recently played” inline with current + upcoming so prev/next operate on that unified list.
- Mini player: which controls (back 5s, play/pause, next/prev) and whether to show title; gesture set (double-tap expand, long-press quick actions); compact vs full variants.
- Item states: visual treatment for generating/absent/failed/ready; ghosting and tap-to-request/retry behavior.
- Seek behavior: confirm buttons-only (±5s/±10s) vs any scrubbing.
- Discover filters/search: chip/search placement and density to match list styling.

## Locked-in features to implement
- Discover rows: inline `Play next` and `Add to end` actions (UI pattern TBD).
- Row slide for queueing: light swipe adds item to end of queue with feedback.
- Up Next queue: drag-to-reorder; swipe-to-remove; swipe-to-add; tap or pull-to-front to play immediately; list includes recently played + current + upcoming for prev/next navigation.
- Item states: generating (ghosted + spinner + “Generating…”), absent (ghosted; tap triggers generation), failed (ghosted; tap retries silently), ready (normal).
- Auto-play toggle wired to queue behavior.
- Seek via forward/back buttons for the current track.

## Notes
- Collapse/expand reliability is resolved; keep mini sticky while browsing.
- Hero prev/next thumbnails will not be added.
