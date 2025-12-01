# Audio Guides – Functional Requirements (Working Draft)

Status legend: [ ] not implemented, [~] partial, [x] implemented (as of current mock UI in `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/AudioGuides/`).
UI-only items are called out explicitly; anything not wired to real playback/generation/storage should be read as visual/demo behavior only.

## Audio Player (Hero)
- [~] Controls: play/pause, next/prev, seek via ±5s; hold to repeat/accelerate seek.
  - [x] UI buttons for play/pause, next/prev, ±5s in hero (updates mock progress).
  - [ ] Actual audio playback engine; long-press seek that repeatedly steps ±5s every 0.2s while held.
- [~] Playback speed presets: 0.75x, 1.25x, 1.5x, 2x (no sleep timer; global per user).
  - [x] Speed menu UI present in hero.
  - [ ] Speed affects playback (actual audio engine rate changes) via a shared playback controller.
  - [ ] Speed selection is stored and restored across sessions/plays using a global per-user playback speed store shared by all voiceover playback surfaces.
- [~] States tracked: ready / playing / paused / stopped with position/duration display.
  - [x] UI shows play/pause state and position/duration.
  - [ ] Ready/stopped surfaced in UI.
  - [ ] Real playback state tracking from audio engine.
- [~] Per-guide resume: persist last-played position per discovery (surface in lists/history).
  - [x] In-memory per-guide progress shown for queued items in the mock.
  - [ ] Progress persisted per discovery (stored and restored across sessions).
  - [ ] Resume works with real audio playback and surfaces in history.

## Mini Player (Global replacement)
- [ ] Replace existing Voiceover UI (e.g., `VoiceoverPersistentPlayerView`, `VoiceoverPlayerBar`, `VoiceoverPlayerHost`) with a single global Audio Guides mini player backed by the shared `VoiceoverPlaybackController` and queue store.
- [ ] Mini visible only on:
  - Main Discoveries grid.
  - Discovery Detail overlay.
  - Discovery streaming stage and post-discovery states.
  - Audio Guides page (list overlay mode), using the same placement and styling as the existing mini there.
  - Not visible on: camera flow, upload flow, Confirm Image Selection, Settings.
- [~] Hero and mini stay in sync; collapse/expand doesn’t interrupt playback.
  - [x] UI state syncs within Audio Guides page via shared view model.
  - [ ] Real playback sync with shared audio engine and queue across views/screens.

## List View (common shell for Up Next & My Discoveries)
- [x] Toggle bar switches between Up Next and My Discoveries. (Tap only.)
- [x] Hero↔list collapse/expand; mini sticky while browsing within Audio Guides page. (Works in-page; no global mini/dismiss.)

## Up Next
- [ ] Single list combining current, upcoming, and last-played items in a unified Up Next view.
- [ ] History UX: fresh design for presentation/interaction, surfacing “Just Played” / “Last Played” inline with the queue.
- [~] Actions: tap history makes current; removing current advances; removing upcoming reflows.
  - [x] Tap-to-play works for Up Next items in the mock list.
  - [ ] History/removal/advance behaviors implemented with real queue.
- [~] Insertion rules: “Play next” inserts at top; “Add to end” appends; auto items append after manual.
  - [x] Play Next/Add UI via menu and swipe appends to mock queue.
  - [ ] Enforced ordering rules for auto vs manual; aligns with real queue.
- [~] Auto-play toggle: advance to next ready item; skip non-ready and continue.
  - [x] Toggle UI present.
  - [ ] Functional auto-advance behavior wired to playback/queue so that:
    - Generating or failed items are skipped for playback but kept visible at the front of Up Next as non-playable items (for awareness and retry).
    - Ready items continue to play in order, using the Immediate/Deferred/base playlist model.
- [ ] Persistence: queue ordering, history, current item, progress, auto-play toggle.
- [x] Up Next reordering: drag-to-reorder allowed in Up Next. (Works in the mock list; no persistence.)
- [ ] Queued items without guides trigger generation: any item queued/Play Next with no guide calls edge function to generate.
- [~] Queue visuals: distinct current; clear separation of history vs upcoming.
  - [x] Playing highlight in list.
  - [ ] History section/visual separation.
- [ ] Unified Up Next layout: `Now Playing` row pinned at top with “Now Playing” chip; `Up Next` section immediately below (shows full queue, short slice + expand when long); `Last Played` section at bottom showing up to 3 most-recent items with an “Expand history” affordance; clear visual separation between the three.
- [ ] Swipe-to-remove on Up Next rows (including upcoming/current items) with trash/dumpster affordance and remove-on-release behavior; tap-to-play remains unchanged. Removal should mirror the lightweight swipe feedback used for queuing (haptic + disappearance).
- [ ] Offline state: when the device is offline and a queued item’s voiceover is not cached locally, show an “Offline – not downloaded” chip/badge on the row and block playback until the asset has been downloaded while online.

## My Discoveries
- [ ] Mirrors existing My Discoveries content/ordering (real data, not mocks) 1:1 with the current My Discoveries list, grouped by day for display.
- [~] Row states: ready / generating (ghosted + spinner) / absent (ghosted + “Create audio guide”) / failed (warning tint + retry overlay) / playing indicator.
  - [x] UI shows ready/generating/empty/failed/playing on mock data.
  - [ ] States driven by backend; absent copy/affordance polish.
- [~] Ready action: tap plays in place without tab switch (works in-page; needs full integration).
  - [x] Single tap plays via mock player; double tap opens hero.
  - [ ] Hooks into real playback and cross-tab context.
- [~] Absent action: credit modal (cost + current balance) with Cancel/OK; OK triggers generation via edge function.
  - [x] Alert shows credits and starts simulated generation.
  - [ ] Real edge call + credit handling.
- [~] Failed action: retry overlay/icon triggers regeneration.
  - [x] Failed badge + tap retries simulated generation.
  - [ ] Real regeneration call and error handling.
- [~] Light swipe adds to queue tail with feedback.
  - [x] Trailing swipe queues item in mock list.
  - [ ] Haptics/feedback + real queue integration.
- [x] Queue controls: slide row or use 3-dot menu to add to end or play next (no reordering). (Menu + swipe route to the mock queue.)
- [x] No search/filters in this list.
- [ ] Credit balance updates from edge function response. (Only local decrement in the mock flow.)
- [~] My Discoveries actions UI: credit modal, retry overlay, swipe to queue tail, play-in-place. (All UI present; actions operate on mock data only.)
- [~] My Discoveries states visuals: ready/generating/absent/failed/playing. (UI covers these on mock data; not driven by live backend.)
- [ ] Status/queue chips in My Discoveries: keep current readiness styling (Ready/Generating/Failed/Empty) and add chips for queue state—`Playing` chip when active, `Queued` chip when the item is in Up Next (prevent duplicate queue action when already queued).

## Audio Guide Storage & Caching
- [ ] Reuse voiceover caching layer for Audio Guides; verify parity with needs.
- [ ] Offline: play from cache; if not cached and offline, show an “Offline – not downloaded” state and block playback.
- [ ] Streaming fallback when online if not cached.
- [ ] Prefetch any queued item; track in-flight fetches to avoid duplicates.
- [~] Generation statuses: absent / generating / failed / ready.
  - [x] Status enum + UI badges/spinner in mock data.
  - [ ] Wired to backend/edge responses.
- [ ] Retention/cleanup: reuse existing voiceover cache eviction (no new policy). (No audio-guide-specific caching yet.)

## Credit & Generation Flow
- [~] Absent ghosted items show credit modal; generation starts on confirm.
  - [x] Alert + simulated generation in mock.
  - [ ] Real credit check (balance) + edge generation call.
- [~] No cancel of in-flight generation; failed state with retry returning to generating.
  - [x] Mock generation toggles to failed/ready; tap retries.
  - [ ] Real request lifecycle and error handling.
- [ ] Auto-generate setting feeds Up Next (generating → ready) for new discoveries.

## Error Handling
- [ ] Playback errors: inline surface + retry; for non-offline failures, show a per-row “Playback failed” chip and allow retry without blocking the rest of the queue.
- [~] Generation failures: mark item failed and allow retry.
  - [x] Mock flow sets failed state and allows tap-to-retry.
  - [ ] Real error surfacing + retry behavior.
- [ ] Fetch/prefetch errors: inline per item with retry; avoid blocking rest of queue.
- [ ] Dismiss mini while error visible stops playback and hides mini.

## Data & Persistence
- [ ] Stable discovery IDs everywhere; hydrate from store/cache; avoid transient UUIDs and duplicate fetches.
- [ ] Persist per-discovery progress, queue state, toggle settings, cached assets. (Current model uses ephemeral UUIDs and in-memory state only.)
- [ ] Stale session handling: if there is no playback activity for 24h, prompt to resume or clear; auto-clear queue/history payloads on user-decline or after timeout.

## Discovery Detail Integration
- [ ] Text/Audio pill in `DiscoveryDetailView`; selecting Audio switches to the Audio Guides tab and focuses the hero for that discovery; Text returns to the discovery details (no special page-flip animation).
- [ ] Discovery Detail Text/Audio pill is visible only when the open Discovery Detail corresponds to the same discovery currently loaded in the shared Audio Guides/voiceover player and that player is in a playing or paused state; hide it for all other discoveries and when playback is idle, stopped, or failed.
- [ ] Existing `VoiceoverDetailButton` remains; the Text/Audio pill is an additional affordance that appears only when the current discovery matches the active audio guide.

## Nice to have (post-MVP)
- Mini dismiss gesture: stops playback if active; hides when stopped.
- Gesture-based tab swipe between Up Next and My Discoveries.
