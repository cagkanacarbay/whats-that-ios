# Audio Guides – Single-Page Player & Lists (UISpec02)

## Visual References
- `reference-images/time-next-up.png`: Primary hero player layout (circular progress + adjacent next/prev thumbs).
- `reference-images/list-with-audio-player.png`: List density and collapsed mini player footprint when scrolled.
- `reference-images/list-view.png`: Overall styling inspiration; use its top tab bar pattern for Up Next vs Discover toggle.
- `reference-images/playing.png`: Detail styling/typography cues for the content card around the player.
- `reference-images/time.png`: Circular timing idea (adapt for readability and accessibility; avoid heavy ornamentation).

## Core Concept
A single vertical page with a collapsible hero player pinned at the top. Below it, a two-state list area that shows either **Up Next** (queue only) or **Discover** (full catalog). Only one list is visible at a time; the toggle is directly under the player. Scrolling collapses the hero into a mini player; tapping (or double-tapping) the mini expands the hero.

## Layout Structure (Default, at Top of Page)
1) **Hero Player (expanded)**  
   - Circular artwork with progress ring (scrubbable).  
   - Core controls: play/pause, skip ±, speed/timer row.  
   - Tiny prev/next thumbnails flanking the ring (tap to jump).  
   - Meta strip: title + duration (no language/source).  
   - Visual style: follow `time-next-up.png` for layout; take typography/weight cues from `playing.png`; refine ring legibility versus `time.png`.
3) **List Toggle Bar**  
   - Two tabs: `Up Next` (default) and `Discover`. Uses the tab styling from `list-view.png` (highlighted selected state). Swipe left/right on the list area also switches tabs.
4) **List Area (shows one list at a time)**  
   - When `Up Next` is active: pure queue in order (manual + auto if present). 3–5 items visible. Drag to reorder; swipe to remove; tap to jump. Auto items can have a subtle “Auto” badge only.  
   - When `Discover` is active: full catalog. Filters/search chips as needed. Row density from `list-with-audio-player.png`. Primary inline action: `Play next`; secondary: `Add to end`. Tapping row starts playback and switches back to `Up Next` so the user sees the queue result.

## Scroll & Collapse Behavior
- On downward scroll, the hero compresses into a **mini player** anchored above the tab bar (size/style per `list-with-audio-player.png`). Ring shrinks to a small arc; controls reduce to play/pause + skip.  
- The toggle and list remain; the mini stays visible while browsing.  
- Tap (or double-tap) the mini to re-expand the hero at the top.

## Playback & Queue Behavior
- Any item played from any list updates both the hero and the mini player immediately.  
- `Play next` inserts at the top of Up Next; `Add to end` appends.  
- Tapping an item in Up Next jumps playback to it.  
- Auto-stream (when enabled) appends after manual items; appears inside Up Next with a light badge but no separate section.  
- Removing an item reflows the queue; if the current item is removed, advance to the next.

## Gestures & Interactions
- Swipe left/right on the list area: switch between Up Next and Discover tabs.  
- Drag-and-drop reorder within Up Next.  
- Scrub on the hero ring for seek; haptics on seek boundaries.  
- Double-tap mini player: expand to hero. Single tap mini: open hero; long-press (optional) for quick actions (e.g., sleep timer).  
- List row swipe (Discover): optional accelerator to `Play next`.

## States & Empty/Loading
- Up Next empty: “Nothing queued — pick from Discover” inline state under the hero.  
- Discover empty (no items or filtered out): show a clear empty state and filter reset.  
- Loading: skeletons matching the chosen list density.  
- Errors: inline toast on failed add/play; errored items in Up Next can be dismissed or retried.

## Accessibility & Responsiveness
- Collapse/expand preserves control reach on small devices; ensure tap targets ≥44pt.  
- Provide a linear seek alternative when circular drag is hard (e.g., double-tap on ring opens a precise seek slider in the mini sheet).  
- Maintain contrast and text scaling from `playing.png` inspiration; avoid overly thin strokes from `time.png`.

## Visual Guidance
- Hero: use `time-next-up.png` structure; adapt the ring for clarity and reduce glow.  
-,List density: use `list-with-audio-player.png`; spacing/feel inspired by `list-view.png` and `playing.png`.  
-

## Persistence
- Queue, current item, and progress persist across app sessions; mini player should rehydrate instantly with the last state on app launch.
