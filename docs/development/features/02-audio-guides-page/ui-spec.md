# Audio Guides Page – UI Specification

## Inputs & References

- Requirements derived from `research.md`.
- **Visual References**:
  - `reference-images/time-next-up.png`: Hero player layout (Circular progress with flanking prev/next images).
  - `reference-images/list-with-audio-player.png`:  Base list style and "Mini Player" anchored at the bottom to adapt.
  - `reference-images/list-view.png`: Nice look and feel to be inspired from.
  - `reference-images/time.png`: Interaction model for circular progress.

## Architecture: The "Side-by-Side" Pager

To solve the vertical stacking issue, the feature uses a horizontal **Swipe Pager** with two distinct modes. These modes never overlap vertically.

1. **Mode 1: The Library (Main List)**
   - The default entry point.
   - Displays all discoveries.
   - Anchored **Mini Player** appears at the bottom if audio is active.
   - Swiping right opens **The Station**
2. **Mode 2: The Station (Player + Queue)**
   - Accessed by **Swiping Right** from the Library OR **Tapping** the Mini Player.
   - Contains the expanded Hero Player and the "Up Next" Queue.
   - **Swiping Left** returns to the Library.

## Mode 1: The Library (Discovery List)

### Header

- **Filter Toggle (Top Right) - Show only existing guides:**
  - **On (Default):** Show "Ready" + "Processing" + "Errored" (The "Real" content).
  - **Off:** Show All (Includes "Ghost" items that haven't been generated).

### List Items

- **Layout:** Condensed row.
  - **Left:** Small Thumbnail (Discovery Image).
  - **Center:** Title (No Subtitle).
  - **Bottom Row (Context):**
    - **Slider:** Horizontal progress bar indicating playback position (visible if started).
  - **Right:**
    - **Play/Pause Toggle:** Circular button.
    - **Start Over:** Small "Rewind" or "Restart" icon (visible if progress > 0).
- **Interaction:**
  - **Tap Row:** Starts playback and transitions to **Mode 2 (Player)**.
  - **Ghost Item Tap:** Simulates generation start (State changes to "Processing" with spinner).
  - **Swipe Right:** "Add to Queue" (Toast confirmation).

### Mini Player (Floating/Anchored)

- **Design:** Based on `list-with-audio-player.png`.
- **Position:** Fixed at the bottom of the Library view (above Tab Bar).
- **Content:** Thumbnail, Title, Play/Pause, Progress Ring (Mini).
- **Interaction:** Tap to expand to Mode 2.

## Mode 2: The Station (Player + Queue)

### Top Half: Hero Player

- **Design:** Based on `time-next-up.png` (Carousel/Coverflow style).
- **Center:** Current Discovery Image with **Circular Time Ring**.
  - **Ring:** Visualizes progress. Tap/Drag to seek.
- **Flanking:**
  - **Left:** Previous item thumbnail (dimmed/smaller).
  - **Right:** Next item thumbnail (dimmed/smaller).
- **Controls:**
  - Play/Pause (Center, large).
  - Skip Forward / Backward.
  - **Auto-Play Toggle:** Switch to enable/disable continuous playback.

### Bottom Half: The Queue ("Next Up")

- **Structure:** A single scrollable list.
- **Section 1: Manual Queue:**
  - Items explicitly added by the user via "Swipe to Queue".
  - Visual indicator (e.g., "Queued" badge).
- **Section 2: Auto-Stream:**
  - **Logic:** "Next Discovery Made" / "Forward in Time".
  - Populated by the next available items in the chronological list (Newest/Upcoming relative to current).
- **Behavior:** Manual items always play before Auto-Stream items.

## Behaviors & Logic

### Auto-Play

- **Logic:** The player moves "Forward in Time".
- **Scenario:** If playing Discovery #5, the Auto-Stream queues #6, #7, etc. (Assuming #6 is newer/next).
- **Live Updates:** If the user creates a *new* discovery while listening, it is injected into the Auto-Stream immediately after the current track (if Manual Queue is empty).

### States

- **Ghost (Missing Audio):** Greyed out. Tapping triggers "Processing".
- **Processing:** Spinner. Tapping shows "Retry" if stuck.
- **Errored:** Red/Warning state. Tapping triggers "Retry".
- **Ready:** Normal state. Playable.

## Implementation Notes

- **Transition:** Use a `TabView` with `PageTabViewStyle` or a custom HStack with geometry offsets for the Swipe interaction to ensure smooth performance.
- **State Management:** A central `AudioPlayerService` must hold the Queue, Playback State, and Current Time, decoupled from the UI views.
- **Styling:** Strictly adhere to `BrandTheme.swift` for colors, fonts, and spacing.
