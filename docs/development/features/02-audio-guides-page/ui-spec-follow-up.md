Result time: 2025-11-29

# Audio Guides – UI Spec Follow-up

## Sneak Peek under Hero (definition)
- A small inline card directly beneath the expanded hero showing the next item in the queue: thumbnail + title + duration.
- Purpose: keep “what’s next” visible without scrolling; when the hero collapses, the mini player takes over and the list becomes primary context.

## Discover List Actions (needed)
- Inline actions: `Play next` (primary) and `Add to end` (secondary) on each row.
- Gesture accelerator: light swipe to trigger `Play next`.
- Layout to decide: trailing buttons vs. inline chip row vs. overflow menu; ensure row density matches list-with-audio-player reference.

## Row Slide for Queueing (needed)
- Light horizontal swipe on a row to queue a voiceover (`Play next` default).
- Consider haptic + brief toast for confirmation.

## Up Next / Queue Interactions (needed)
- Drag-to-reorder within Up Next.
- Swipe-to-remove and swipe-to-add.
- Tap to jump playback.
- Up Next should include “Recently played” so prev/next buttons navigate within the combined history + current + upcoming list; decide labeling/segmentation for played vs upcoming.

## Mini Player (discussion)
- Options to decide:
  - Controls + title: back 5s, play/pause, next/prev, plus single-line title.
  - Controls-only: back 5s, play/pause, next/prev, no title for compactness.
- Interaction: double-tap to expand hero; long-press for quick actions (e.g., sleep timer, queue actions).
- Ensure collapse/expand stays reliable (resolved), mini remains sticky while browsing.

## Item States (needed)
- Generating: ghosted with spinner and “Generating…”; tap shows a gentle “still processing” notice.
- No voiceover yet: ghosted; tap triggers generation request.
- Failed: ghosted; tap retries silently; user does not need explicit error messaging in-list.
- Ready: normal.

## Auto-play Toggle (needed)
- Simple on/off near hero controls (e.g., below play/pause/next). Governs whether newly ready items auto-enter Up Next.

## Seek Behavior (decision)
- Prefer explicit seek buttons (±5s/±10s). Avoid circular scrubbing for now; keep ring purely as progress/feedback.

## Hero Simplifications (agreed)
- Skip prev/next thumbnail flanks around the ring.
- Focus hero on artwork, progress ring, core controls, and meta strip.

## Discover Filters/Search (needed)
- Add chips and/or search to filter catalog; placement and priority to be defined to match density/feel of reference lists.
