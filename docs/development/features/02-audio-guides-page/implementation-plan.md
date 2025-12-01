# Audio Guides – Implementation Plan (Working Draft)

Purpose: migrate Audio Guides to use the existing Voiceover playback backend (engine, caching, storage, generation) while replacing all legacy Voiceover UI with the new hero/mini player UX. Track decisions made vs. open items to settle before coding.

## Decisions Locked (per product direction)
- Reuse `VoiceoverPlaybackController` backend stack (playback, caching, generation, credits); do not rewrite engine or generation flow.
- Remove/replace old Voiceover UI (e.g., `VoiceoverPersistentPlayerView`, `VoiceoverPlayerBar`, `VoiceoverPlayerHost`) with the Audio Guides hero + mini player UI.
- Extend playback controls with ±5s seek buttons and press-and-hold accelerated seek.
- History is append-only with timestamps; every played discovery is added once per completion/start event and retains last known position for resume.
- Progress resume per discovery: remember last position and restore on replay.
- Autoplay: when enabled, skip items that are not ready; skipped non-ready items stay at the top of Up Next. If status is generating/failed, item remains at the top; failed requires user retry before playback.
- My Discoveries list uses the same Discovery dataset (1:1 with Discovery feed).
- Use existing “generate voiceover” edge function for Audio Guides; reuse credits behavior and storage/caching policies.

## To-Do: Immediate Investigation Tasks
- Audit Voiceover UI components to deprecate: map where `VoiceoverPersistentPlayerView`, `VoiceoverPlayerBar`, `VoiceoverPlayerHost`, inset stores, and related insets are instantiated (e.g., Discoveries tab safe area inset) and plan removal/replacement with Audio Guides mini player.
- Review `VoiceoverPlaybackController` APIs for:
  - Seek hooks to support ±5s and press-and-hold accelerated seek.
  - Rate control entry points (playback speed) and persistence hooks.
  - Queue provider integration (already present for discovery sequences) to align with Up Next model.
  - Error surfacing and retry pathways we can re-use.
- Inspect generation flow call sites (Discovery creation, Settings auto-generate toggle) to ensure Audio Guides connects to the existing edge function and credit handling without duplication.
- Inventory data models where discovery IDs are the source of truth (e.g., `DiscoverySummary`) to replace Audio Guides’ mock UUIDs.
- Identify storage/persistence mechanism for queue/history/progress (UserDefaults-backed actors for this phase) and gaps to fill.

## Architecture & Data Model Draft
- Identity: use stable `discovery.id` (`Int64`) everywhere; no transient UUIDs or Audio-Guides-specific IDs. Audio Guides must operate on the same discovery models already used in the Discoveries tab and detail view.
- Queue model (Up Next):
  - Ordered list of discovery IDs.
  - Each entry has status (ready/generating/failed/missing), progress, and insertion source (manual/auto) if needed.
  - Persistence local-first (disk cache); discuss whether to sync to backend later (not in scope now).
  - Autoplay skip rule: skipped non-ready items remain at head until ready/failed retry resolves.
  - Reordering allowed; removal advances current when applicable.
- History model:
  - Append-only log with discovery ID, last position, timestamp of last play.
  - No mutation except truncation/cleanup policy (to decide).
- Progress:
  - Per-discovery position stored locally; restored on play.
  - Update on periodic ticks and on pause/stop transitions.
- Playback settings:
  - Playback speed presets (0.75/1/1.25/1.5/2x) stored as a global per-user setting (not per discovery), shared across all voiceover playback surfaces.
  - Autoplay toggle persisted.

## Real Data Wiring (mock → production)
- Replace `AudioGuidesViewModel` mock data with bindings to shared `VoiceoverPlaybackController` plus a new queue/history/progress store that operates on `DiscoverySummary` IDs. `AudioGuide` models should carry `DiscoverySummary` and rely on normalized assets from the controller for readiness/error.
- Single source of truth: playback state, position, duration, and asset readiness come from `VoiceoverPlaybackController`; queue/history/autoplay come from the new store; UI only mirrors these sources (no local progress/credits/UUIDs).
- Per-discovery progress: add a lightweight `VoiceoverProgressStore` (actor) that persists position and lastPlayedAt by discovery ID in `UserDefaults`. Drive updates from the controller’s time observer and pause/stop callbacks; hydrate when resuming a discovery.
- Queue/history store: add `AudioGuidesQueueStore` (actor) that owns Immediate/Deferred/base snapshot, history stack, autoplay flag, current discovery ID, and lastActivityAt. Persist to `UserDefaults` with dedupe and trimming. On app launch, reload and drop missing discoveries; if `lastActivityAt` is older than 24h, prompt to resume or clear, and auto-clear if declined or after timeout. Auto-clear also runs if no playback activity for 24h.
- Queue control flow: `AudioGuidesQueueStore` is the single source of truth for Up Next. It exposes `next()/previous()/playNow(id)/enqueue` helpers; hero/mini invoke these, and the store in turn calls `VoiceoverPlaybackController.togglePlayback(for:)` with the resolved `DiscoverySummary`. The controller’s `currentDiscovery` stays in sync with the store’s `current` item; any legacy queue providers are adapted once into the store and then discarded.
- Playback speed: add a global `VoiceoverPlaybackSpeedStore` (actor/UserDefaults) storing the last chosen speed per user. Wire hero/mini speed menu to set/read it and call a new `VoiceoverPlaybackController.setRate(_:)` helper that updates AVPlayer rate immediately and on new items. This store is separate from `VoiceoverPreferences` (which govern voice creation, not playback).
- Prefetch & offline guards: queue store calls `VoiceoverPlaybackController.prefetch(for:)` when items enter Immediate/Deferred/base snapshot. UI asks controller for `isDownloadPending` + reachability to show “Offline – not downloaded” and block playback; retries when online and cache available.
- Generation path: My Discoveries absent/failed states call `requestVoiceover(for:)` on the controller; reuse `insufficient_credits` copy and retry semantics from `VoiceoverDetailButton`. No local credit math.
- Error surfacing: playback errors surfaced from controller errorMessage; UI shows inline chip with retry → `togglePlayback`/`requestVoiceover` as appropriate. Clearing error hides mini if playback is idle/failed.

## Playback Speed (new, global)
- New store key (UserDefaults) for `playbackSpeed`, default 1.0. Exposed via `VoiceoverPlaybackSpeedStore` actor to keep concurrency safe.
- `VoiceoverPlaybackController` gains `setRate(_:)` and persists current rate in memory; on player setup, it applies the stored rate from `VoiceoverPlaybackSpeedStore`. UI reads the store and updates the controller; the controller’s active rate is reflected in hero/mini and any other playback surfaces.
- This store is distinct from `VoiceoverPreferences` (auto/voice/tts); no migration of prior keys is required and playback speed does not affect voiceover generation.

### Voiceover Asset Status Behaviour (Parity with Discovery Detail)
- Source of truth: Audio Guides must use `VoiceoverPlaybackController.normalizedAsset(for:)` for all readiness/error states. Do not reimplement status ageing logic.
- Processing → none:
  - `VoiceoverPlaybackController.normalize(_:)` treats `.processing` assets as `.none` once they are older than `processingStaleThreshold` (currently 5 minutes; derived from `updatedAt` or `requestedAt`).
  - Audio Guides UI must mirror this: rows whose assets are normalized to `.none` should appear as “no audio guide yet” (absent state), not “stuck generating”.
- Failed → none:
  - Failed assets are normalized back to `.none` after `failedExpiry` (currently 1 hour since `updatedAt`).
  - Audio Guides must adopt the same rule: items that failed long ago should appear as absent (create affordance), not permanently “failed”.
- Fresh failures:
  - For assets with `status == .failed` that are newer than `failedExpiry`, Audio Guides should show a failed state with retry (matching `VoiceoverDetailButton` semantics: “Retry audio”).
- Missing/none:
  - Assets with `status == .missing` or `status == .none` are treated as “no guide exists yet” and should show an absent/empty state with “Create audio guide” affordance.
- Credit errors:
  - If `errorReason == "insufficient_credits"`, Audio Guides should surface the same “Not enough credits” copy used in the existing Discovery detail voiceover button, and then rely on the global credits flow. Audio Guides must not manually decrement or track credit counts.

### Audio Guides Status Mapping (per row)
- For each discovery shown in My Discoveries / Up Next, derive row state from the normalized asset + playback state:
  - `processing` → Generating (ghosted + spinner, “Generating…” copy).
  - `failed` (fresh) → Failed (warning tint, retry affordance).
  - `ready` → Ready (duration, can play; “Playing” badge when active).
  - `missing` / `none` → Absent (ghosted + “Create audio guide”).
  - Additionally, apply queue state chips (`Playing`, `Queued`) on top of readiness states.

## Up Next Queue Behavior – Spec
- Base context: when the user taps a discovery to play, initialise or update the base playlist to reflect the Discoveries ordering around that item. `baseList` is a sequence of discovery IDs and `baseIndex` points at the currently playing item. The base playlist is allowed to evolve over time (for example when new discoveries are captured and auto-generated voiceovers appear), but always represents “previous/next” around the current item, similar to a playlist in Spotify.
- Queue layers (mirrors Spotify/Apple Music):
  - Immediate queue (front): items added via “Play Next” are enqueued FIFO here.
  - Deferred queue (tail): items added via “Add to End” are appended here.
  - Base fallback: after queues drain, advance through `baseList` starting at `baseIndex + 1`.
- Next selection order: take head of Immediate; if empty, head of Deferred; if both empty, next item in `baseList` after `baseIndex`. When a queued item is consumed, remove it and push the current item into history.
- Prev behavior: if current playback position > restartThreshold (2–3s), restart current; else pop from history stack (most recent first). If history is empty, step backward in `baseList` before `baseIndex`. History grows whenever we advance to a new item (queued or base).
- History visibility: surfaced in UI under “Just Played” / “Last Played”; trimming policy can cap length (e.g., 100) while persisting last N items.
- Ad-hoc play while queue exists: tapping any discovery (e.g., from Discoveries grid or My Discoveries) replaces current, pushes prior current to history, and keeps both queue layers intact. The base playlist is re-centred on the new discovery so that previous/next now reflect the items immediately before and after it in Discoveries ordering. After the ad-hoc item ends, playback resumes Immediate → Deferred → base fallback from this new base context. If we detect a stale session (see below) we may clear queues first.
- Auto-generated/ready items:
  - When auto-generate is enabled and new discoveries are created, their voiceovers are requested automatically. As these auto-generated assets transition to ready, their discoveries are inserted into the base playlist after the current item (in Discoveries recency order), so they appear as natural “next up” items even without manual queueing.
  - Default insertion for manually enqueued items remains: “Play Next” enqueues into Immediate; “Add to End” appends to Deferred tail. Auto-generated items that the user explicitly queues follow the same Immediate/Deferred rules.
  - Skip non-ready items (processing/failed) when autoplay is on; skipped items are kept at the front of the relevant section of Up Next so users can see and retry them, but playback moves on to the next ready item.
- Persistence/staleness:
  - Persist: queue ordering (Immediate/Deferred), base snapshot identifiers, baseIndex, current item, history stack, autoplay toggle, and per-discovery progress.
  - Stale session rule: if no playback activity for 24h, prompt on return: “Resume your queue (N items)?” with Resume / Clear. If user opts Clear, drop Immediate/Deferred/baseIndex but keep per-discovery progress/history. Auto-clear if declined or on next launch after timeout.
  - Auto-prune completed items from queue/history as they are consumed; dedupe queued items by discovery ID.
- Clear affordance: explicit “Clear queue” action removes Immediate/Deferred while leaving history and current intact; current continues and will fall back to base traversal when done.
- Duplicate prevention: if an item is already in Immediate or Deferred, do not add again; instead, surface “Already queued.” If playing, mark as `Playing`; if queued, mark as `Queued` in My Discoveries chips.
- Layout implications (list):
  - Sections: Now Playing (pinned row) → Up Next (Immediate then Deferred in order) → From My Discoveries (remaining baseList slice) → Last Played (history, expandable).
  - Swipe-to-remove on Up Next rows removes from the corresponding queue; removing current advances to Next selection order.
- Data model needs:
  - Stable discovery IDs; queue entries carry ID, status (ready/generating/failed/missing), progress, insertion source (manual/auto), timestamp added.
  - Persisted structures: `queueImmediate: [DiscoveryID]`, `queueDeferred: [DiscoveryID]`, `baseList: [DiscoveryID]`, `baseIndex: Int`, `history: [DiscoveryID]`, `current: DiscoveryID?`, `autoplayEnabled: Bool`.
  - Resume logic loads persisted structures; if any IDs are missing/absent, drop them with a soft notice in UI.

## Discovery Detail Integration
- Navigation contract (no custom animation):
  - Discovery Detail → Audio Guides: tapping the Audio pill in Discovery Detail switches `MainTabView` to the Audio Guides tab and focuses the hero for that discovery, using the shared `VoiceoverPlaybackController` as the playback state source. Standard tab / overlay transitions are used (no bespoke “page-flip”).
  - Audio Guides → Discovery Detail: tapping the Text pill in the Audio Guides hero switches back to the Discoveries tab and opens the Discovery Detail overlay for the same discovery, again using standard transitions.
  - One-way entry: Discovery Detail does not start playback for arbitrary discoveries via the pill; the Audio pill is present only for the discovery already active in the shared player so users can hop to text and back to audio for that one item.
  - Visibility: Text/Audio pill in Discovery Detail appears only when the open detail’s `discovery.id` matches the controller’s active discovery and the controller is playing/paused; hide it for other discoveries and when playback is idle/failed so only one detail screen shows the pill at a time.
- Data handoff: ensure detail view provides the discovery to the playback controller with correct asset state and image URL; avoid duplicate fetches when switching contexts.
- Back stack: after opening from detail, back returns the user to the previous screen (e.g., Discoveries grid or whatever was underneath), not always the Audio Guides tab root.
- Discovery Detail voiceover UI:
  - The existing `VoiceoverDetailButton`-based playback/create UI remains; the Text/Audio pill is an additional affordance on top of it.
  - Discovery Detail Text/Audio pill visibility must be derived from the single shared `VoiceoverPlaybackController` state (no local flags): show the pill only when the open `discovery.id` matches the controller’s active discovery and the controller is in a playing or paused state; hide it for all other discoveries and when playback is idle, stopped, or failed, so the pill appears in exactly one Discovery Detail at a time and stays in sync with the global Audio Guides player.

## Generation & Credits – Alignment Tasks
- Wire Audio Guides creation flows to existing generate-voiceover edge function through `VoiceoverPlaybackController.requestVoiceover(for:)`; do not introduce a new generation path.
- Absent/failed states:
  - Trigger generation and retry via the same request path as Discovery creation and detail, using the normalized asset states described above.
  - Audio Guides must not implement its own credit logic; it simply invokes generation and renders the resulting statuses.
- Auto-generate toggle (Settings):
  - Remains owned by the existing voiceover preferences and creation flows (out of scope for Audio Guides).
  - Audio Guides integration is limited to reflecting whatever assets and queue entries exist as a result.
- Balance updates:
  - Credit balance continues to be managed by the existing credits infrastructure. When generation responses include updated balance, the global credit balance store is updated there; Audio Guides reads any exposed balance for UI copy but never decrements locally.

## Storage, Caching, Offline/Streaming
- Reuse `VoiceoverFileCache` for audio guides; continue storing audio under `Voiceovers/<discoveryId>/fileName` as implemented today.
- Prefetch:
  - Anything that enters the Up Next queue must call `VoiceoverPlaybackController.prefetch(for:)` so that assets are fetched and cached eagerly, reusing existing polling and cache-refresh logic.
  - Audio Guides must not bypass `VoiceoverPlaybackController` to fetch assets directly.
- Offline behavior:
  - If a guide is `ready` but not present in `VoiceoverFileCache` and the device is offline, block playback and show an “Offline – not downloaded” chip/badge in the row.
  - Detect offline via reachability + `voiceoverCache.cachedFileURL`; if offline and missing cache, disable play and surface inline message + retry CTA. Auto-retry when connectivity returns and cache is fetched.
  - Tapping such a row should explain that the guide will be playable once online and downloaded; there is no best-effort streaming while offline.
- Streaming fallback:
  - When online and not cached, `VoiceoverPlaybackController.resolvePlayableURL(for:)` already streams and caches; Audio Guides relies on this behavior rather than adding new download logic.
- Retention:
  - Follow existing voiceover cache eviction policy; confirm no extra retention requirements for audio guides.

## Playback UX Integration
- Mini player must replace legacy voiceover mini globally (visible on all screens where legacy appears) and open Audio Guides page; back/close returns to prior screen.
- Global mini host:
  - Replace `VoiceoverPersistentPlayerView`/`VoiceoverPlayerBar`/`VoiceoverPlayerHost` with a single Audio Guides mini player host that uses the shared `VoiceoverPlaybackController` and `AudioGuidesQueueStore`, and is overlaid above existing content (no safe-area inset plumbing, no height reporting).
  - The same mini instance is used everywhere it appears; there is no separate “page-local” mini. Audio Guides list mode reuses this same mini host and placement.
  - Host once at the root UI shell (e.g., in `RootContentView` as a ZStack overlay above `MainTabView`) so it can be shown/hidden based on screen context while remaining a single shared instance.
  - Visibility rules:
    - Visible on:
      - Main Discoveries page.
      - Discovery Detail overlay.
      - Discovery streaming stage and post-discovery states (after capture/selection/confirmation).
      - Audio Guides page in list mode (using the existing mini placement at the bottom of the overlay).
    - Hidden on:
      - Camera flow (capture).
      - Upload flow (gallery selection).
      - Confirm Image Selection.
      - Settings.
    - Hidden whenever playback is idle/failed with no current discovery.
  - Tap on the mini opens the Audio Guides page focused on the active discovery; system back/close returns to the previous screen without clearing queue/history.
- Hero/mini sync: both views bound to shared controller state; collapse/expand must not interrupt playback.
- Controls to add:
  - ±5s buttons (tap) mapped to `VoiceoverPlaybackController` seek-by-5s helpers.
  - Press-and-hold accelerated seek: while the user holds the ±5s buttons, repeatedly seek ±5 seconds at a fixed cadence (every 0.2 seconds) until release, then resume normal playback at the new position.
  - Playback speed menu wired to `VoiceoverPlaybackController` playback rate, persisted via the new global playback-speed store.
  - Resume state reflected in both hero and mini using the shared per-discovery progress store.
- Error surfacing: inline error + retry in mini/hero; dismissing mini while error visible stops playback and hides mini.

## My Discoveries (Data & UI)
- Drive list from the same My Discoveries dataset already used elsewhere in the app (1:1 with existing My Discoveries content and ordering), grouped by day for display; statuses mapped from `VoiceoverPlaybackController.normalizedAsset(for:)` (ready/processing/missing/failed) for each `discovery.id`.
- Chip rules: Ready/Generating/Failed/Empty plus `Queued` when in Up Next and `Playing` when active.
- Queue actions: swipe/menu add to end or play next; block duplicate queueing when already queued.
- Absent state triggers credit modal using shared generation path; failed state retry uses same; both flows must call `requestVoiceover(for:)` on the shared controller and rely on the global credits/edge-function behavior.

## Persisted Settings & Progress
- Storage mechanism:
  - Queue ordering, current item, autoplay toggle: persisted via `AudioGuidesQueueStore` using `UserDefaults` as backing storage.
  - Per-discovery progress and last-played timestamps (history): persisted via a shared `VoiceoverProgressStore` actor using `UserDefaults`, used by both Discovery Detail and Audio Guides.
  - Playback speed selection: persisted via `VoiceoverPlaybackSpeedStore` using `UserDefaults`, so the hero/mini and Discovery Detail share the same speed.

## UI Removal/Replacement Plan (high level)
- Remove usages of `VoiceoverPersistentPlayerView`, `VoiceoverPlayerBar`, `VoiceoverPlayerHost`, and related inset plumbing; replace with a single Audio Guides mini player host surfaced globally and overlaid on top of existing content (no bottom inset dependency).
- Remove `VoiceoverPlayerInsetStore`-based safe-area inset plumbing; individual screens should manage their own internal padding while the mini floats above the tab bar/home indicator.
- Ensure tab layouts remain visually correct once the legacy inset logic is removed; the mini should appear in the same placement as the Audio Guides list mini (above the tab bar/home indicator) without requiring each screen to manage additional padding.

## Outstanding Questions / Decisions Needed
- Whether to expose a “Clear history” affordance (in addition to “Clear queue”) and any UX gating around trimming history length or confirming destructive actions.

## Next Steps
- [ ] Complete deep-dive of `VoiceoverPlaybackController` to map required extension points (seek, rate, queue provider, error handling, progress persistence).
- [ ] Inventory and mark all legacy voiceover UI entry points for removal/replacement.
- [ ] Draft detailed Up Next queue behavior spec (ad-hoc play, clear queue policy, auto vs. manual ordering).
- [ ] Define persistence layer for queue/history/progress and speed/autoplay settings.
- [ ] Design navigation contract for Discovery Detail ↔ Audio Guides (including animation approach).
