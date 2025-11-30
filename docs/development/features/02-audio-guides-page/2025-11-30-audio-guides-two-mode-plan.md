# Audio Guides: Two-Mode Overlay Plan (Up Next / My Discoveries)

## Goals
- Split the screen into two explicit modes: **Full Page** (hero + sections; no mini player) and **List Overlay** (Up Next / My Discoveries filling the screen from bottom with mini player).
- Smooth lift animation: the selector and list move up together (no springy bounce), revealing a focused list view.
- Dismiss list mode via: tapping the mini player, pull-down gesture, or a down-arrow button in the top-left.
- Tap rules: single tap on a row starts playback; double tap on a row opens the audio player.

## Current State (as of 2025-11-30)
- `AudioGuidesPageView` is a single `ScrollView` with a sticky toggle bar and hero at the top.
- Mini player is driven by scroll collapse (`showMiniPlayer`/`hasCollapsedHero`), not by an explicit mode.
- Lists: `UpNextListView`, `DiscoverListView` reuse a shared `AudioGuidesViewModel`.
- Mini player component exists (`MiniPlayerView`), shown only when hero collapses.

## Proposed Structure
- Add `enum ViewMode { case fullPage, list }` in `AudioGuidesPageView` with `@State var mode: ViewMode = .fullPage`.
- Wrap page in `ZStack` and conditionally render:
  - **Full Page**: current hero + sections + toggle at bottom; no mini player.
  - **List Overlay**: toggle pinned at top, selected list filling remaining space, mini player pinned at bottom.
- Use `matchedGeometryEffect` for the toggle bar between positions to visually “lift” into place.
- Transition: `.easeInOut(duration: 0.28–0.32)` move from bottom + fade (no spring).
- Safe areas: pad bottom in list mode to clear the home indicator and the mini player.

## Entry / Exit Logic
- Enter list mode: tapping “Up Next” or “My Discoveries” when in full page.
- Exit list mode (back to full page):
  - Tap mini player.
  - Pull down from top (drag gesture on overlay) if gesture ends with downward displacement over threshold.
  - Tap down-arrow button in top-left of overlay.
- Maintain selected tab across mode switches.

## Row Interaction
- Single tap: start playback of the row (existing `playGuide`).
- Double tap: open audio player (hook into existing player host if available; otherwise placeholder action).

## Component Touch Points
- `AudioGuidesPageView`: add `mode`, remove scroll-collapse mini-player logic, add overlay layout, gestures, transitions.
- `ToggleBarView`: add namespace for matched geometry (already present) and support list-mode tap-to-dismiss if needed.
- `MiniPlayerView`: add tap handler to dismiss overlay (list mode only).
- List views: add single/double tap gesture per row (ensure single tap waits for double-tap failure).

## Risks / Questions
- Confirm the audio player open action (double tap) should use existing `VoiceoverPlayerHost` or a new sheet/full-screen view.
- Are we okay removing the scroll-driven mini player entirely in favor of mode-based visibility? (Plan assumes yes.)
- Accessibility: ensure the down-arrow button has a label (“Close list”) and gestures don’t conflict with VoiceOver.

## Implementation Steps (dev-ready)
1) Add `ViewMode` state + matched-geometry namespace to `AudioGuidesPageView`.
2) Restructure body into `ZStack`: render full page; overlay list mode with `transition(.move(edge: .bottom).combined(with: .opacity))`.
3) Wire entry: on toggle tap in full page, set `mode = .list` with `.easeInOut`.
4) Wire exit: mini-player tap, down-arrow button, and pull-down drag to set `mode = .fullPage`.
5) Add bottom safe-area padding in list mode so the mini player sits above the home indicator; hide mini player in full page.
6) Add per-row gestures: single tap to `playGuide`, double tap to open player.
7) Remove/replace `showMiniPlayer`/`hasCollapsedHero` scroll-offset logic.
8) Test on small and large simulators to confirm the list fully occupies the screen and transitions smoothly.
