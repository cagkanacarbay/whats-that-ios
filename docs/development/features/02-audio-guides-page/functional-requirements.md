# Audio Guides – Functional Requirements (Working Draft)

Status legend: [ ] not implemented, [~] partial, [x] implemented (as of current mock UI in `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/AudioGuides/`).
UI-only items are called out explicitly; anything not wired to real playback/generation/storage should be read as visual/demo behavior only.

## Data Architecture
- [ ] **Shared Discovery Store**: `DiscoveryStore` actor provides normalized cache `[Int64: DiscoverySummary]` plus `orderedIds: [Int64]` for both Discoveries grid and Audio Guides My Discoveries list.
  - Cache limit: ~250MB. Evict oldest discoveries (lowest IDs) when limit exceeded.
  - Discoveries never get updated on the backend; no invalidation needed.
- [ ] Each page maintains its own `localIds: [Int64]` for independent rendering—no cross-page re-render cascade when one page paginates.
- [ ] `DiscoveryFeedViewModel` and `AudioGuidesViewModel` each inject the shared `DiscoveryStore` and maintain their own pagination state (cursor, hasMore).
- [ ] **Voiceover Status Fetching**: 
  - On Discoveries tab load/pagination: fetch voiceover status immediately after loading discoveries via `voiceoverController.prefetch(for: loadedIds)`.
  - On Audio Guides entry: batch `voiceoverController.prefetch(for: allCachedIds)`.
  - On Audio Guides pagination: batch `voiceoverController.prefetch(for: newIds)`.
- [ ] Silent failure on fetch/prefetch errors—no toast, no banner. User just sees end of list.
- [ ] **No AudioGuide struct**: Use `DiscoverySummary` directly with `discovery.id` (Int64).
- [ ] **Pre-computed Row State Model**: Create `AudioGuideRowState` struct computed once per discovery, updated only when underlying stores change:
  ```swift
  struct AudioGuideRowState: Equatable {
      let discoveryId: Int64
      let voiceoverStatus: DiscoveryVoiceoverStatus
      let isQueued: Bool
      let isPlaying: Bool
      let progress: Double?
  }
  ```
  This avoids recomputing from 3 sources on every render.
- [ ] **Discovery Deletion Cleanup**: When a discovery is deleted from Discoveries, also remove its cached audio file, voiceover asset state, progress, and any queue entries.

## Audio Player (Hero)
- [~] Controls: play/pause, next/prev, seek via ±5s; hold to repeat/accelerate seek.
  - [x] UI buttons for play/pause, next/prev, ±5s in hero (updates mock progress).
  - [ ] Wired to `VoiceoverPlaybackController.seek(by:)` and accelerated seek (±5s every 0.1s while held).
- [~] Playback speed presets: 0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 2x (global per user).
  - [x] Speed menu UI present in hero.
  - [ ] Wired to `VoiceoverPlaybackSpeedStore` and `VoiceoverPlaybackController.setRate(_:)`.
- [~] States tracked: playing / paused / stopped with position/duration display.
  - [x] UI shows play/pause state and position/duration.
  - [ ] State derived from `VoiceoverPlaybackController.playbackState`.
- [ ] **Voiceover Asset Status Mapping**: Database voiceover states (processing/failed/ready/none) are distinct from playback states. Use `VoiceoverPlaybackController.normalizedAsset(for:)` which applies:
  - **Processing stale threshold**: Items stuck in `processing` for >5 minutes → treated as `none` (no audio).
  - **Failed expiry**: Items in `failed` state for >1 hour → treated as `none` (allows fresh retry).
- [~] Per-guide resume: persist last-played position per discovery (surface in lists/history).
  - [x] In-memory per-guide progress shown for queued items in the mock.
  - [ ] Wired to `VoiceoverProgressStore` for persistence.
  - Note: Progress is display-only ("you listened until here"). On play, always start from position 0.
- [ ] **Background playback**: Audio must continue playing when app is in background. Already implemented in `VoiceoverPlaybackController` via audio session category `.playback`.
- [ ] **Lock screen / Control Center controls**: Must work via `MPRemoteCommandCenter`. Already wired in controller; verify functionality with new Audio Guides integration. Discovery images used as artwork.

## Mini Player (Global replacement)
- [ ] Replace existing Voiceover UI (e.g., `VoiceoverPersistentPlayerView`, `VoiceoverPlayerBar`, `VoiceoverPlayerHost`) with a single global Audio Guides mini player backed by the shared `VoiceoverPlaybackController` and `AudioGuidesQueueStore`.
- [ ] **Hosting**: In `MainTabView` as ZStack overlay above TabView (provides access to `selectedTab`, `activeOverlayPhase` for visibility control).
- [ ] **Visibility rules**:

| Screen | Visible | Implementation |
|--------|---------|----------------|
| Discoveries grid | ✅ | `selectedTab == .discoveries` |
| Discovery Detail overlay | ✅ | When detail active |
| Streaming/Complete stages | ✅ | `activeOverlayPhase == .analyzing` |
| Audio Guides (list mode) | ✅ | `selectedTab == .audioGuides && mode == .list` |
| Audio Guides (hero/player mode) | ❌ | `selectedTab == .audioGuides && mode == .hero` |
| Camera capture | ❌ | `activeOverlayPhase == .capturingInitial/Retake` |
| Gallery selection | ❌ | `activeOverlayPhase == .selectingInitial/Retake` |
| Confirm Image Selection | ❌ | `activeOverlayPhase == .confirming` |
| Settings sheet | ❌ | Sheet slides over mini player, hiding it |

- [ ] **Tap behavior**: Tapping mini player switches to Audio Guides tab in hero mode (shows the currently playing discovery).
- [ ] **Exit animation**: Mini player animates by sliding down below the screen edge (not fade).
- [ ] No swipe gestures on mini player.
- [ ] **Scroll content padding**: `MiniPlayerPresenceStore` exposes `effectiveInset`. Discoveries grid, Discovery Detail, streaming/complete overlay, and Audio Guides list all apply `.padding(.bottom, effectiveInset)`.
- [~] Hero and mini stay in sync; mode switch doesn't interrupt playback.
  - [x] UI state syncs within Audio Guides page via shared view model.
  - [ ] Both bound to shared `VoiceoverPlaybackController` state.

## List View (common shell for Up Next & My Discoveries)
- [x] Toggle bar switches between Up Next and My Discoveries. (Tap only.)
- [ ] Horizontal swipe gesture between Up Next and My Discoveries tabs (must not interfere with list item swipes or sheet gestures).
- [x] Hero↔list mode switch; mini sticky while in list mode. (Works in-page; no global mini/dismiss.)
- [~] **List→Hero trigger**: Button at top (implemented) + pull-down gesture from top (needs implementation).
- [x] **Hero→List trigger**: Tap either tab button at bottom ("Up Next" or "My Discoveries"). Playback continues regardless of mode switch.
- [ ] **Empty state for Up Next**: "Select an audio guide from My Discoveries to start playing."
- [ ] **Empty state for My Discoveries**: Design pending (should handle zero discoveries case).
- [ ] **Loading state for My Discoveries**: Skeleton/shimmer rows during initial load.
- [ ] **Pull-to-refresh**: My Discoveries supports pull-to-refresh to reload discoveries and voiceover statuses.

## Up Next
- [ ] **Three-layer queue model** (Spotify/Apple Music style):
  - **Immediate queue**: Items added via "Play Next" (LIFO—most recent "Play Next" plays first).
  - **Deferred queue**: Items added via "Add to End" (FIFO—first added plays first).
  - **Base fallback**: Discovery ordering around current item; keep ~20 items on each side of `baseIndex`, not the full list.
- [ ] **Next selection order**: Immediate head → Deferred head → base playlist next item.
- [ ] **Previous behavior**: If position > 3s, restart current; else pop from history stack.
- [ ] **Three distinct sections** in unified Up Next view:
  - **Now Playing**: Single row pinned at top with "Now Playing" chip. Cannot be removed via swipe.
  - **Up Next**: Queue items below; show 3 items initially, "Show more" affordance expands by 10 each time.
  - **Last Played**: History section at bottom; show 3 items initially, "Expand history" affordance expands by 10. Max 50 items in history.
- [~] Actions: tap history makes current; removing current advances; removing upcoming reflows.
  - [x] Tap-to-play works for Up Next items in the mock list.
  - [ ] Wired to `AudioGuidesQueueStore.playNow()`, `next()`, `remove()`.
- [~] Insertion rules: "Play Next" inserts at immediate queue head (LIFO); "Add to End" appends to deferred queue tail (FIFO).
  - [x] Play Next/Add UI via menu and swipe appends to mock queue.
  - [ ] Wired to `AudioGuidesQueueStore.playNext()`, `addToEnd()`.
- [~] Auto-play toggle: advance to next ready item; skip non-ready (generating/failed) items and put them in Play Next.
  - [x] Toggle UI present.
  - [ ] Wired to `AudioGuidesQueueStore.autoplayEnabled` and skip logic.
- [ ] Persistence: queue ordering, history, current item, progress, auto-play toggle via `AudioGuidesQueueStore`.
- [x] Up Next reordering: drag-to-reorder allowed in Up Next. (Works in the mock list; no persistence.)
- [ ] Queued items without guides trigger generation via `requestVoiceover(for:)`.
- [~] Queue visuals: distinct current; clear separation of history vs upcoming.
  - [x] Playing highlight in list.
  - [ ] History section/visual separation.
- [ ] **Swipe-to-remove**: On Up Next rows (excluding Now Playing) with trash/remove affordance and remove-on-release behavior; tap-to-play remains unchanged. Feedback: haptic + row disappearance.
- [ ] **Offline state**: If device is offline and queued item's voiceover is not cached locally, show "Offline – not downloaded" chip and block playback. If playback starts online then loses connection: fails if not cached, continues if cached.
- [ ] **Queue limit**: Maximum 100 items across immediate + deferred queues.
- [ ] **Duplicate prevention**: Prevent adding the same discovery twice to the queue. "Play Next" on an already-queued item moves it to the front instead.
- [ ] **Clear queue**: Confirmation dialog before clearing.
- [ ] **Out of scope**: Shuffle mode, Repeat modes.

## My Discoveries
- [ ] Uses `DiscoverySummary` directly from shared `DiscoveryStore` (no separate `AudioGuide` struct). Identity via `discovery.id` (Int64).
- [ ] Mirrors existing My Discoveries content/ordering (real data, not mocks) 1:1 with the current My Discoveries list, grouped by day for display.
- [ ] All discoveries have images; no special handling needed for missing images.
- [ ] Row state computed at render: voiceover status from `VoiceoverPlaybackController.normalizedAsset(for:)`, queue state from `AudioGuidesQueueStore`, progress from `VoiceoverProgressStore`.
- [~] Row states: ready / generating (ghosted + spinner) / absent (ghosted + "Create audio guide") / failed (warning tint + retry overlay) / playing indicator.
  - [x] UI shows ready/generating/empty/failed/playing on mock data.
  - [ ] States driven by backend; absent copy/affordance polish.
- [~] Ready action: tap plays in place without tab switch (works in-page; needs full integration).
  - [x] Single tap plays via mock player.
  - [ ] Long-press opens hero view (replaces double-tap for accessibility).
  - [ ] Hooks into real playback and cross-tab context.
- [~] Absent action: credit modal (cost + current balance) with Cancel/OK; OK triggers generation via edge function.
  - [x] Alert shows credits and starts simulated generation.
  - [ ] Real edge call + credit handling.
  - [ ] If zero credits: show "Get More Credits" CTA in modal.
- [~] Failed action: retry overlay/icon triggers regeneration.
  - [x] Failed badge + tap retries simulated generation.
  - [ ] Real regeneration call and error handling.
- [~] Light swipe adds to queue tail with feedback.
  - [x] Trailing swipe queues item in mock list.
  - [ ] If already queued: swipe springs back, no action; shows existing "Queued" tick.
  - [ ] Haptics/feedback + real queue integration.
- [x] Queue controls: 3-dot menu to "Add to End" or "Play Next".
  - [ ] "Play Next" on already-queued item moves it to front of queue.
- [x] No search/filters in this list.
- [ ] Credit balance updates from edge function response. (Only local decrement in the mock flow.)
- [~] My Discoveries actions UI: credit modal, retry overlay, swipe to queue tail, play-in-place. (All UI present; actions operate on mock data only.)
- [~] My Discoveries states visuals: ready/generating/absent/failed/playing. (UI covers these on mock data; not driven by live backend.)
- [ ] **Status/queue chips**: `Playing` chip when active, `Queued` chip when in Up Next (prevents duplicate queue swipe).

## Audio Guide Storage & Caching
- [ ] Reuse voiceover caching layer (`VoiceoverFileCache`) for Audio Guides.
- [ ] **Current cache policy** (reviewed from code):
  - **Max size**: 150MB (`maxBytes = 150 * 1024 * 1024`)
  - **Eviction strategy**: LRU (Least Recently Used) by `lastAccessedAt`
  - **Trigger**: After each `store()` call, if `totalBytes > maxBytes`
  - **Access updates**: Each `cachedFileURL()` call updates `lastAccessedAt`
  - Conclusion: Policy is sufficient for Audio Guides (~50-100 voiceovers). No changes needed.
- [ ] No streaming—download audio file fully before playback.
- [ ] Offline: play from cache; if not cached and offline, show "Offline – not downloaded" state and block playback.
- [ ] Prefetch queued items in queue order (download priority = playback order).
- [ ] **Track in-flight downloads**: Add `inFlightDownloads: [Int64: Task<URL?, Error>]` to `VoiceoverFileCache`. If a download is requested for a discoveryId already in flight, return the existing Task's result instead of starting a new download.
- [~] Generation statuses: absent / generating / failed / ready.
  - [x] Status enum + UI badges/spinner in mock data.
  - [ ] Wired to backend/edge responses.

## Credit & Generation Flow
- [~] Absent ghosted items show credit modal; generation starts on confirm.
  - [x] Alert + simulated generation in mock.
  - [ ] Real credit check (balance) + edge generation call.
  - [ ] If zero credits: modal prevents generation, shows "Get More Credits" CTA instead.
- [~] No cancel of in-flight generation; failed state allows user-initiated retry.
  - [x] Mock generation toggles to failed/ready; tap retries.
  - [ ] Real request lifecycle and error handling.
- [ ] **Auto-generate + queue behavior**: When auto-play is enabled and base list has fewer than 20 items on the "next" side, newly auto-generated voiceovers for recent discoveries are added to fill the base list (up to 20 items each side). Do not auto-add if user is playing older discoveries far from the top.
- [ ] **Rate limiting**: Maximum 2 concurrent generation requests. Additional requests queued locally; send when a slot frees up.
- [ ] **Insufficient credits error**: Show alert explaining credits are insufficient with CTA to purchase credits screen.

## Error Handling
- [ ] Playback errors: inline surface + retry; for non-offline failures, show a per-row "Playback failed" chip and allow retry without blocking the rest of the queue.
- [~] Generation failures: mark item failed and allow retry.
  - [x] Mock flow sets failed state and allows tap-to-retry.
  - [ ] Real error surfacing + retry behavior.
  - [ ] Failed items in queue kept with failed state; after skipping, move to history.
- [ ] **Playback failed auto-clear**: Use same normalization as voiceover status—failed state clears after 1 hour, treating as "no audio" for fresh retry.
- [ ] Fetch/prefetch errors: silent (no toast, no banner—user just sees end of list if offline or fetch fails).
- [ ] **Offline banner**: Show subtle "You're offline" banner when device is offline.
- [ ] **Auto-retry on reconnect**: When device comes back online, auto-retry any failed prefetch operations.
- [ ] Dismiss mini while error visible stops playback and hides mini.
- [ ] **Error logging**: Log errors for debugging/analytics (implementation detail).

## Data & Persistence
- [ ] Stable discovery IDs everywhere; hydrate from store/cache; avoid transient UUIDs and duplicate fetches.
- [ ] Persist per-discovery progress, queue state, toggle settings, cached assets. (Current model uses ephemeral UUIDs and in-memory state only.)
- [ ] **Three state stores** (Option C—separate with clear responsibilities):
  - **`VoiceoverProgressStore`** (shared): `positions: [Int64: Double]`, `lastPlayed: [Int64: Date]`. UserDefaults backed, ~1MB limit, prune oldest entries if exceeded.
  - **`VoiceoverPlaybackSpeedStore`** (shared): `speed: Double`. UserDefaults backed.
  - **`AudioGuidesQueueStore`** (Audio Guides specific): `immediate`, `deferred`, `baseList`, `baseIndex`, `history`, `current`, `autoplayEnabled`, `lastActivityAt`. UserDefaults backed.
  - **`MiniPlayerPresenceStore`**: `height`, `isVisible`, `effectiveInset`. In-memory only.
- [ ] **Stale session handling**: If no playback activity for 24h, auto-clear queue/history. No user prompt needed.
- [ ] **Data loss**: Data lost on app uninstall (acceptable). No iCloud sync. No data migration concern for now.

## Discovery Detail Integration
- [ ] Text/Audio pill in `DiscoveryDetailView`; selecting Audio switches to the Audio Guides tab and focuses the hero for that discovery; Text returns to the discovery details (no special page-flip animation).
- [ ] **Text/Audio pill visibility** (keep current logic):
  - Visible only when: the open Discovery Detail matches the discovery currently in the audio player AND player is playing/paused.
  - Hide for all other discoveries and when playback is idle, stopped, or failed.
  - User can press existing "Play audio" button first, then pill becomes visible.
- [ ] **VoiceoverDetailButton**: Keep existing button as-is for create/play/pause/retry actions. Pill is additive affordance for switching views.
- [ ] **Out of scope**: Deep linking to specific audio guide, sharing audio guide links.

## Nice to have (post-MVP)
- Mini dismiss gesture: stops playback if active; hides when stopped.
