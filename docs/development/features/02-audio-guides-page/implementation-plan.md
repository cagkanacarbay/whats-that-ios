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
- Identity: use stable `discovery.id` (`Int64`) everywhere; no transient UUIDs or Audio-Guides-specific IDs. Audio Guides must operate on the same discovery models already used in the Discoveries tab and detail view. Do NOT use a separate `AudioGuide` struct with UUID identity—use `DiscoverySummary` directly and compute voiceover status at render time.
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

## Data Layer Architecture

### Shared Discovery Store

Create a shared `DiscoveryStore` actor that both Discoveries and Audio Guides pages read from. This prevents re-renders in one page when the other fetches more data.

```
┌───────────────────────────────────────────────────────────────┐
│                   DiscoveryStore (Actor)                      │
│  - cache: [Int64: DiscoverySummary]  (normalized dictionary)  │
│  - orderedIds: [Int64]               (maintains recency)      │
│  - loadMore(limit:before:) async -> [DiscoverySummary]        │
│  - get(id:) -> DiscoverySummary?                              │
└────────────────────────────┬──────────────────────────────────┘
                             │
             ┌───────────────┴───────────────┐
             ▼                               ▼
┌─────────────────────────────┐   ┌─────────────────────────────┐
│   DiscoveryFeedViewModel    │   │   AudioGuidesViewModel      │
│  - localIds: [Int64]        │   │  - localIds: [Int64]        │
│  - cursor, hasMore, etc.    │   │  - cursor, hasMore, etc.    │
│  - owns grid pagination     │   │  - owns list pagination     │
└─────────────────────────────┘   └─────────────────────────────┘
```

**File: `WhatsThatDomain/Discovery/DiscoveryStore.swift`** (NEW)

```swift
public actor DiscoveryStore {
    private var cache: [Int64: DiscoverySummary] = [:]
    private var orderedIds: [Int64] = []
    private let repository: DiscoveryRepository
    
    public init(repository: DiscoveryRepository) {
        self.repository = repository
    }
    
    /// Fetches more discoveries and caches them. Returns newly fetched items.
    public func loadMore(limit: Int, before cursor: Int64?) async throws -> [DiscoverySummary] {
        let page = try await repository.fetchDiscoveries(limit: limit, before: cursor)
        for item in page {
            if cache[item.id] == nil {
                orderedIds.append(item.id)
            }
            cache[item.id] = item
        }
        return page
    }
    
    /// Returns cached discovery by ID, nil if not cached.
    public func get(id: Int64) -> DiscoverySummary? {
        cache[id]
    }
    
    /// Returns all cached discoveries in recency order.
    public func allCached() -> [DiscoverySummary] {
        orderedIds.compactMap { cache[$0] }
    }
    
    /// Returns all cached discovery IDs.
    public func allCachedIds() -> [Int64] {
        orderedIds
    }
    
    /// Upserts a discovery (e.g., after creation).
    public func upsert(_ summary: DiscoverySummary) {
        if cache[summary.id] == nil {
            orderedIds.insert(summary.id, at: 0)
        }
        cache[summary.id] = summary
        // Re-sort by capturedAt descending
        orderedIds.sort { 
            (cache[$0]?.capturedAt ?? .distantPast) > (cache[$1]?.capturedAt ?? .distantPast)
        }
    }
    
    /// Removes a discovery from cache.
    public func remove(id: Int64) {
        cache.removeValue(forKey: id)
        orderedIds.removeAll { $0 == id }
    }
}
```

**Update: `DiscoveryFeedViewModel`**

- Inject `DiscoveryStore` instead of `DiscoveryFeedUseCase`
- Maintain local `@Published var localIds: [Int64]` for what's visible in the grid
- On pagination, call `store.loadMore()` and append new IDs to `localIds`
- Computed property maps `localIds` → `[DiscoverySummary]` for grid display

**Update: `AudioGuidesViewModel`** with voiceover prefetch:

```swift
@MainActor
final class AudioGuidesViewModel: ObservableObject {
    @Published private(set) var localIds: [Int64] = []
    @Published private(set) var isLoadingVoiceoverStatus = false
    
    private let discoveryStore: DiscoveryStore
    private let voiceoverController: VoiceoverPlaybackController
    private var didInitialPrefetch = false
    private var cursor: Int64?
    private var hasMore = true
    
    func onAppear() async {
        guard !didInitialPrefetch else { return }
        didInitialPrefetch = true
        
        // Load IDs from shared store
        let cachedIds = await discoveryStore.allCachedIds()
        localIds = cachedIds
        
        // Batch prefetch voiceover status for all known discoveries
        if !cachedIds.isEmpty {
            isLoadingVoiceoverStatus = true
            voiceoverController.prefetch(for: cachedIds)
            // prefetch is fire-and-forget; status updates via assetStates publisher
            isLoadingVoiceoverStatus = false
        }
    }
    
    func loadMoreIfNeeded(currentId: Int64?) async {
        guard hasMore else { return }
        guard let currentId, let index = localIds.firstIndex(of: currentId) else { return }
        
        // Trigger load when near end
        let threshold = localIds.index(localIds.endIndex, offsetBy: -4, limitedBy: localIds.startIndex) ?? localIds.startIndex
        guard index >= threshold else { return }
        
        do {
            let newItems = try await discoveryStore.loadMore(limit: 10, before: cursor)
            let newIds = newItems.map(\.id)
            
            // Append to local list
            let existingSet = Set(localIds)
            let filtered = newIds.filter { !existingSet.contains($0) }
            localIds.append(contentsOf: filtered)
            
            // Update cursor
            cursor = newItems.last?.id
            hasMore = newItems.count == 10
            
            // Batch prefetch voiceover status for new items
            if !filtered.isEmpty {
                voiceoverController.prefetch(for: filtered)
            }
        } catch {
            // Silent failure - user just sees end of list
        }
    }
}
```

### Row State Computation (No AudioGuide Struct)

Each row in My Discoveries / Up Next computes its display state from sources at render time:

```swift
struct MyDiscoveriesRowView: View {
    let discoveryId: Int64
    @ObservedObject var voiceoverController: VoiceoverPlaybackController
    @ObservedObject var queueStore: AudioGuidesQueueStore
    @ObservedObject var progressStore: VoiceoverProgressStore
    
    private var rowStatus: AudioGuideRowStatus {
        guard let asset = voiceoverController.normalizedAsset(for: discoveryId) else {
            return .empty
        }
        switch asset.status {
        case .ready: return .ready
        case .processing: return .generating
        case .failed: return .failed
        case .none, .missing: return .empty
        }
    }
    
    private var isQueued: Bool { queueStore.isQueued(discoveryId) }
    private var isPlaying: Bool { queueStore.current == discoveryId }
    private var progress: Double? { progressStore.position(for: discoveryId) }
}

enum AudioGuideRowStatus {
    case ready, generating, failed, empty
}
```

### Voiceover Status Fetching Strategy
Voiceover metadata (ready/generating/failed/empty) is fetched via `VoiceoverPlaybackController.prefetch(for:)` with internal caching in `SupabaseVoiceoverRepository`.

- **Discoveries tab**: Do NOT fetch voiceover status when loading discoveries. Keep the grid lightweight.
- **Audio Guides page entry**: On first appearance, take all discovery IDs from `DiscoveryStore.allCachedIds()` and call `voiceoverController.prefetch(for: allCachedIds)` to batch-fetch statuses. Display rows with computed status from `voiceoverController.normalizedAsset(for:)`.
- **Audio Guides pagination**: After new discoveries are fetched, immediately call `voiceoverController.prefetch(for: newIds)` for the new items.
- **Return to Discoveries**: No change needed—Discoveries grid doesn't show voiceover status per-row; Discovery Detail reads from already-cached `assetStates`.
- **Error handling**: Silent failures for fetch/prefetch errors—no toast, no banner. User just sees end of list if offline or fetch fails.

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
  - **Decision**: Host the global mini player in `MainTabView` as a ZStack overlay above the TabView. This provides direct access to `selectedTab`, `activeOverlayTab`, and `activeOverlayPhase` for visibility control.
  - Replace `VoiceoverPersistentPlayerView`/`VoiceoverPlayerBar`/`VoiceoverPlayerHost` with a single Audio Guides mini player host that uses the shared `VoiceoverPlaybackController` and `AudioGuidesQueueStore`, and is overlaid above existing content.
  - The same mini instance is used everywhere it appears; there is no separate "page-local" mini. Audio Guides list mode reuses this same mini host and placement.
  - Visibility rules:
    - Visible on:
      - Main Discoveries page (`selectedTab == .discoveries`).
      - Discovery Detail overlay.
      - Discovery streaming stage and post-discovery states (`activeOverlayPhase == .analyzing`).
      - Audio Guides page in list mode (`selectedTab == .audioGuides`).
    - Hidden on:
      - Camera flow (`activeOverlayPhase == .capturingInitial/Retake`).
      - Upload flow (`activeOverlayPhase == .selectingInitial/Retake`).
      - Confirm Image Selection (`activeOverlayPhase == .confirming`).
      - Settings (presented as sheet—should slide over mini; **TODO**: verify this behavior after implementation).
    - Hidden whenever playback is idle/failed with no current discovery.
  - Tap on the mini opens the Audio Guides page focused on the active discovery; system back/close returns to the previous screen without clearing queue/history.
- Scroll content padding:
  - Create `MiniPlayerPresenceStore` that exposes `height: CGFloat` and `isVisible: Bool` with computed `effectiveInset`.
  - Discovery Detail, creation overlay streaming/complete, and Audio Guides list apply `.padding(.bottom, miniPlayerPresence.effectiveInset)` to extend scroll area so content can scroll above mini player.
  - Discoveries grid does NOT need padding—content scrolls naturally under mini, user can scroll more.
  - **TODO**: After implementing, verify scroll padding behavior in Discovery Detail and creation overlay.
- Legacy removal:
  - Retire `VoiceoverPlayerInsetStore` and related safe-area inset plumbing.
  - Remove `.safeAreaInset(edge: .bottom)` modifier from Discoveries tab in `MainTabView`.
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

### State Stores Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Shared Voiceover Stores                      │
│  (Used by Discovery Detail, Audio Guides, any future surfaces) │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  VoiceoverProgressStore (Actor)    VoiceoverPlaybackSpeedStore  │
│  ├── positions: [Int64: Double]    ├── speed: Double (1.0)     │
│  ├── lastPlayed: [Int64: Date]     └── UserDefaults backed     │
│  └── UserDefaults backed                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  Audio Guides Specific Store                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  AudioGuidesQueueStore (Actor)                                  │
│  ├── immediate: [Int64]        (Play Next queue)                │
│  ├── deferred: [Int64]         (Add to End queue)               │
│  ├── baseList: [Int64]         (Discovery ordering snapshot)    │
│  ├── baseIndex: Int            (Current position in base)       │
│  ├── history: [Int64]          (Just Played stack)              │
│  ├── current: Int64?           (Now playing)                    │
│  ├── autoplayEnabled: Bool                                      │
│  ├── lastActivityAt: Date?     (For stale session detection)    │
│  └── UserDefaults backed                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### VoiceoverProgressStore

**File: `WhatsThatPresentation/Shared/Stores/VoiceoverProgressStore.swift`** (NEW)

```swift
@MainActor
public final class VoiceoverProgressStore: ObservableObject {
    private static let positionsKey = "voiceover_positions"
    private static let lastPlayedKey = "voiceover_last_played"
    
    @Published private(set) var positions: [Int64: Double] = [:]
    @Published private(set) var lastPlayed: [Int64: Date] = [:]
    
    private let defaults: UserDefaults
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }
    
    public func position(for discoveryId: Int64) -> Double? {
        positions[discoveryId]
    }
    
    public func updatePosition(_ position: Double, for discoveryId: Int64) {
        positions[discoveryId] = position
        lastPlayed[discoveryId] = Date()
        save()
    }
    
    public func clearPosition(for discoveryId: Int64) {
        positions.removeValue(forKey: discoveryId)
        save()
    }
    
    private func load() { /* decode from UserDefaults */ }
    private func save() { /* encode to UserDefaults */ }
}
```

### VoiceoverPlaybackSpeedStore

**File: `WhatsThatPresentation/Shared/Stores/VoiceoverPlaybackSpeedStore.swift`** (NEW)

```swift
@MainActor
public final class VoiceoverPlaybackSpeedStore: ObservableObject {
    private static let speedKey = "voiceover_playback_speed"
    
    @Published var speed: Double {
        didSet { defaults.set(speed, forKey: Self.speedKey) }
    }
    
    private let defaults: UserDefaults
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: Self.speedKey)
        self.speed = stored > 0 ? stored : 1.0
    }
}
```

### AudioGuidesQueueStore

**File: `WhatsThatPresentation/Features/AudioGuides/Stores/AudioGuidesQueueStore.swift`** (NEW)

```swift
@MainActor
public final class AudioGuidesQueueStore: ObservableObject {
    @Published private(set) var immediate: [Int64] = []      // Play Next
    @Published private(set) var deferred: [Int64] = []       // Add to End
    @Published private(set) var baseList: [Int64] = []       // Discovery ordering
    @Published private(set) var baseIndex: Int = 0
    @Published private(set) var history: [Int64] = []        // Just Played
    @Published private(set) var current: Int64?
    @Published var autoplayEnabled: Bool = false
    
    private var lastActivityAt: Date?
    private let staleThreshold: TimeInterval = 24 * 60 * 60  // 24h
    
    // MARK: - Query Methods
    
    public func isQueued(_ id: Int64) -> Bool {
        immediate.contains(id) || deferred.contains(id)
    }
    
    public func isPlaying(_ id: Int64) -> Bool {
        current == id
    }
    
    // MARK: - Queue Operations
    
    public func playNow(_ id: Int64, recentering baseSnapshot: [Int64]) {
        if let currentId = current {
            history.insert(currentId, at: 0)
            trimHistory()
        }
        current = id
        baseList = baseSnapshot
        baseIndex = baseSnapshot.firstIndex(of: id) ?? 0
        lastActivityAt = Date()
        save()
    }
    
    public func playNext(_ id: Int64) {
        guard !isQueued(id) && current != id else { return }
        immediate.insert(id, at: 0)
        save()
    }
    
    public func addToEnd(_ id: Int64) {
        guard !isQueued(id) && current != id else { return }
        deferred.append(id)
        save()
    }
    
    public func next() -> Int64? {
        lastActivityAt = Date()
        
        // Push current to history
        if let currentId = current {
            history.insert(currentId, at: 0)
            trimHistory()
        }
        
        // Take from immediate first, then deferred, then base
        if let nextId = immediate.first {
            immediate.removeFirst()
            current = nextId
        } else if let nextId = deferred.first {
            deferred.removeFirst()
            current = nextId
        } else if baseIndex + 1 < baseList.count {
            baseIndex += 1
            current = baseList[baseIndex]
        } else {
            current = nil
        }
        
        save()
        return current
    }
    
    public func previous(currentPosition: TimeInterval, restartThreshold: TimeInterval = 3.0) -> Int64? {
        lastActivityAt = Date()
        
        // If past threshold, restart current (don't change current)
        if currentPosition > restartThreshold {
            return current
        }
        
        // Pop from history
        if let prevId = history.first {
            history.removeFirst()
            current = prevId
        } else if baseIndex > 0 {
            baseIndex -= 1
            current = baseList[baseIndex]
        }
        
        save()
        return current
    }
    
    public func remove(_ id: Int64) {
        immediate.removeAll { $0 == id }
        deferred.removeAll { $0 == id }
        save()
    }
    
    public func clearQueue() {
        immediate.removeAll()
        deferred.removeAll()
        save()
    }
    
    private func trimHistory() {
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
    }
    
    // MARK: - Stale Session
    
    public var isStale: Bool {
        guard let lastActivity = lastActivityAt else { return false }
        return Date().timeIntervalSince(lastActivity) > staleThreshold
    }
    
    // MARK: - Persistence
    private func save() { /* encode to UserDefaults */ }
    private func load() { /* decode from UserDefaults */ }
}
```

### MiniPlayerPresenceStore

**File: `WhatsThatPresentation/Shared/Stores/MiniPlayerPresenceStore.swift`** (NEW)

```swift
@MainActor
public final class MiniPlayerPresenceStore: ObservableObject {
    @Published var height: CGFloat = 0
    @Published var isVisible: Bool = false
    
    public var effectiveInset: CGFloat {
        isVisible ? height : 0
    }
}
```

### MainTabView Mini Player Hosting

**File: `MainTabView.swift`** (MODIFY)

```swift
struct MainTabView: View {
    @StateObject private var miniPlayerPresence = MiniPlayerPresenceStore()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // ... existing tabs
            }
            
            // Creation overlay (existing)
            if let overlayTab = activeOverlayTab, ... { ... }
            
            // Global mini player
            if shouldShowMiniPlayer {
                AudioGuidesMiniPlayerView(
                    controller: voiceoverController,
                    queueStore: queueStore
                )
                .padding(.bottom, bottomSafeAreaInset + tabBarHeight)
                .background(GeometryReader { geo in
                    Color.clear.preference(
                        key: MiniPlayerHeightKey.self,
                        value: geo.size.height
                    )
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environmentObject(miniPlayerPresence)
        .onPreferenceChange(MiniPlayerHeightKey.self) { height in
            miniPlayerPresence.height = height
            miniPlayerPresence.isVisible = shouldShowMiniPlayer
        }
    }
    
    private var shouldShowMiniPlayer: Bool {
        // Must have active playback
        guard voiceoverController.currentDiscovery != nil else { return false }
        
        switch voiceoverController.playbackState {
        case .idle, .failed:
            return false
        default:
            break
        }
        
        // Hide during capture/selection/confirmation phases
        if let phase = activeOverlayPhase {
            switch phase {
            case .capturingInitial, .capturingRetake,
                 .selectingInitial, .selectingRetake,
                 .confirming, .requestingPermissions:
                return false
            case .analyzing, .idle, .cancelled, .error:
                break
            }
        }
        
        // Note: Settings is presented as sheet and should slide over mini
        // TODO: Verify this behavior after implementation
        
        return true
    }
}
```

### VoiceoverPlaybackController Extensions

**New methods required:**

```swift
extension VoiceoverPlaybackController {
    /// Seek forward/backward by seconds
    func seek(by seconds: TimeInterval) {
        guard let player = audioPlayer,
              let duration = player.currentItem?.duration.seconds,
              duration.isFinite else { return }
        
        let newTime = max(0, min(duration, player.currentTime().seconds + seconds))
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
    }
    
    /// Set playback rate (persisted via VoiceoverPlaybackSpeedStore)
    func setRate(_ rate: Double) {
        audioPlayer?.rate = Float(rate)
        currentRate = rate
    }
    
    /// Current rate
    var currentRate: Double { get set }
}
```

**Accelerated Seek (Press-and-Hold):**

```swift
// In hero/mini player controls:
Button(action: { controller.seek(by: 5) })
    .simultaneousGesture(
        LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                startAcceleratedSeek(direction: .forward)
            }
    )

func startAcceleratedSeek(direction: SeekDirection) {
    // Every 0.2s, seek by 5s in direction
    acceleratedSeekTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
        controller.seek(by: direction == .forward ? 5 : -5)
    }
}
```

## UI Removal/Replacement Plan (high level)

### Components to Remove

| Component | Location | Replacement |
|-----------|----------|-------------|
| `VoiceoverPersistentPlayerView` | `Shared/Voiceover/` | `AudioGuidesMiniPlayerView` |
| `VoiceoverPlayerBar` | `Shared/Voiceover/` | `AudioGuidesMiniPlayerView` |
| `VoiceoverPlayerHost` | `Shared/Voiceover/` | ZStack overlay in `MainTabView` |
| `VoiceoverPlayerInsetStore` | `Shared/Voiceover/` | `MiniPlayerPresenceStore` |
| `VoiceoverPlayerHeightPreferenceKey` | `Shared/Voiceover/` | `MiniPlayerHeightKey` |

### Removal Steps

1. Remove `.safeAreaInset(edge: .bottom)` modifier from Discoveries tab in `MainTabView`
2. Remove `@StateObject private var playerInsetStore` from `MainTabView`
3. Delete the four files listed above
4. Update any views that read `playerInsetStore` to use `MiniPlayerPresenceStore` instead

## Outstanding Questions / Decisions Needed
- Whether to expose a “Clear history” affordance (in addition to “Clear queue”) and any UX gating around trimming history length or confirming destructive actions.

## Next Steps
- [ ] Complete deep-dive of `VoiceoverPlaybackController` to map required extension points (seek, rate, queue provider, error handling, progress persistence).
- [ ] Inventory and mark all legacy voiceover UI entry points for removal/replacement.
- [x] ~~Draft detailed Up Next queue behavior spec~~ (done above).
- [x] ~~Define persistence layer for queue/history/progress and speed/autoplay settings~~ (three stores defined: VoiceoverProgressStore, VoiceoverPlaybackSpeedStore, AudioGuidesQueueStore).
- [x] ~~Design navigation contract for Discovery Detail ↔ Audio Guides~~ (no custom animation, standard tab transitions).
- [x] ~~Define data layer architecture for shared discovery data~~ (DiscoveryStore actor with separate view model localIds).
- [x] ~~Define mini player hosting location~~ (MainTabView ZStack overlay with MiniPlayerPresenceStore for scroll padding).
- [ ] Implement `DiscoveryStore` actor and update `DiscoveryFeedViewModel` and `AudioGuidesViewModel`.
- [ ] Implement the three state stores.
- [ ] Verify Settings sheet correctly covers mini player.
- [ ] Verify scroll padding behavior in Discovery Detail after implementation.
