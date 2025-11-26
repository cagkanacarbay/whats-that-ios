# Audio Guides Page – UI Specification

## Inputs & References
- Requirements derived from `research.md` (tourist-on-the-move, flow certainty, quick control, readiness clarity).
- Visual references (to be adapted into WhatsThat styling): `reference-images/time.png` (circular progress), `reference-images/playing.png` (hero card layout), `reference-images/list-view.png` (list density/affordances), `reference-images/audio-player-minimum.png` (collapsed mini-player).

## Page Purpose
One bottom-tab destination titled **Audio Guides** where users browse all discoveries, see audio readiness, create missing audio, and play/queue guides with Spotify-like controls.

## Navigation & Entry
- Tab bar item: label `Audio Guides`; icon should imply sound/headphones.
- Opening the tab loads the list immediately; no full-screen player unless something is playing.

## Screen Structure & States
1) **Player region (top)**  
   - Hidden when nothing is playing.  
   - Expanded while viewing/controlling playback.  
   - Collapses into a mini-player when the user scrolls the list (sticky at top).
2) **Discovery list region (below player)**  
   - Always present; scrollable.  
   - Supports tap-to-play or tap-to-create depending on readiness.

Page-level states:
- **Idle (no playback):** Only the list is visible; no player.
- **Playing (expanded):** Player occupies the top half; list starts below.
- **Playing (collapsed/mini):** Mini-player pinned at top while the list scrolls.

## Discovery List (Ready vs. Missing Audio)
- Each row shows discovery thumbnail, title, subtitle (location or capture date), and readiness status.
- **Ready:** Normal opacity. Tap → play immediately and place at top of queue.
- **Missing (no audio yet):** Greyed/softened. Tap → start “Create audio guide” flow (respect credit rules). Show inline “Create” call-to-action on the right.
- **Processing:** Show spinner/pill “Generating…”; tap does nothing except expose a more menu with “Retry” if failed previously.
- **Failed:** Show “Retry audio” action; preserves greyed state until ready.
- **Inline overflow menu:** Actions vary by state (Play now, Play next, Add to queue, Retry, Remove from queue).
- **Density:** Based on `list-view.png` but with smaller thumbnails so 3–4 items appear per viewport. Keep 44pt minimum tap targets.
- **Play overlay:** Small transparent play/queued indicator over thumbnails; tap also triggers play/queue.

## Player – Expanded (Top Half)
Visual composition:
- **Hero image + circular progress:** Use `time.png` as interaction model: discovery image is the inner circle; the surrounding ring animates progress. Tap/drag on ring seeks.  
- **Metadata block:** Title, optional location line, duration.  
- **Controls (classic audio controls):** Play/pause, previous, next, skip forward 30s, skip back 5s.  
- **Auto-play toggle:** “Auto-play next” switch in control cluster; reflects queue behavior.  
- **Progress bar:** Numeric elapsed / remaining under the ring.
- **Action chip:** “Create audio” replaces controls when the current item is missing (should only appear when the user promoted a missing item from list).
- Adapt top framing from `playing.png` (carded hero area + soft background) using WhatsThat colors/blur/shadows.

## Queue & Up Next (Bottom Half while Expanded)
- Header: “Up Next” with auto-play toggle mirrored here for clarity.
- List styling: derived from `list-view.png` but smaller images; shows play/queued indicator. Rows are reorderable (drag handle), removable (swipe-to-remove), and tappable to jump playhead.
- **Queue actions:**  
  - Tap item → start playing it immediately and re-stack queue.  
  - Swipe right → “Play next”.  
  - Swipe left → “Remove from queue”.
- **Ready vs. missing:** If an item is missing audio, tapping opens create flow and then places it in queue once ready.

## Mini-Player (Collapsed)
- Trigger: user scrolls list while something is playing or manually collapses.  
- Layout: follow `audio-player-minimum.png` proportions but restyle with WhatsThat palette. Show thumbnail, title, subtitle, compact waveform/progress scrub, play/pause, and a collapse/expand affordance.  
- Behavior: tap expands; swipe horizontally to skip track; tap thumbnail opens discovery detail (optional, confirm with design).

## Behaviors & Interactions
- **List + player coexistence:** When playback starts, the expanded player appears; scrolling collapses it. Pulling down on list when at top re-expands.
- **Readiness clarity:** Ring color and button states change only when status transitions to ready. Processing shows pulsing ring; failed shows a muted ring with “Retry”.
- **Generation flow:**  
  - From list: tap missing item → start generation; row shows processing state; when ready, auto-insert into queue tail and surface a non-intrusive toast (“Ready to play — Play now / Play next”).  
  - Never interrupt current playback automatically (per research).
- **Newly ready items while playing:** Present “Play now” and “Play next” lightweight choice; default to queue tail if user ignores.
- **Recovery:** Failed items show inline retry; retries do not steal audio focus.
- **Queue rules:** Single active queue; play/pause state persists across navigation. “Auto-play next” respects queue order; when off, playback stops at track end.
- **Empty states:**  
  - No discoveries: empty illustration + CTA “Start exploring to create your first audio guide.”  
  - All missing audio: list is greyed with “Create audio guide” prompts.

## Data & Status Mapping (client expectations)
- Statuses: `none` (no row), `processing`, `ready`, `failed`, `missing` (legacy) mapped to UI: create, generating, play, retry, create.  
- Progress: use server URL durations when available; otherwise estimate until first buffer.  
- Queue persistence: keep queue and playhead in memory; optional persistence across app sessions (decide in open questions).

## Accessibility & Motion
- 44pt targets; VoiceOver labels for controls and progress ring.  
- Reduce Motion: disable ring sweep animation; use linear progress bar fallback.  
- Haptics: light tick on play/pause, stronger on skip/queue actions.  
- Colors contrast-checked against WhatsThat palette.

## Telemetry (lightweight)
- Events: open_tab, start_play, pause, seek, skip_next/prev, add_to_queue, remove_from_queue, auto_play_toggle, create_audio_start/success/fail, queue_ready_prompt_shown/accepted.

## Open Questions / Decisions Needed
- Persist queue/playhead across app relaunch? If yes, define storage size and expiration.  
- Exact auto-play toggle default (on/off) and whether it mirrors user global setting.  
- Should tapping mini-player thumbnail open discovery detail or just expand player?  
- Allow drag-to-seek on the circular ring, or restrict to tap-to-seek for simplicity?  
- Queue ordering when a missing item finishes generating: insert at tail or right after current? (recommend tail per research to avoid stealing focus).  
- Do we support download-to-cache toggle per item, or always stream with silent caching?

## Implementation Notes (WhatsThat Style)
- Re-skin all referenced visuals to match WhatsThat typography, color system, and rounded-rectangle motif; avoid skeuomorphic gradients unless aligned with brand.  
- Use SwiftUI; prefer `GeometryReader` or `ScrollViewReader` for collapse behavior; use a single source of truth for queue/playback state to avoid desync with the list.  
- Keep performance: lazy list, image caching, avoid heavy blurs on long lists.
