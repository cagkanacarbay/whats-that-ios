# Audio Guides – Implementation Plan (Working Draft)

Purpose: migrate Audio Guides to use the existing Voiceover playback backend (engine, caching, storage, generation) while replacing all legacy Voiceover UI with the new hero/mini player UX. Track decisions made vs. open items to settle before coding.

## Decisions Locked (per product direction)
- Reuse `VoiceoverPlaybackController` backend stack (playback, caching, generation, credits); do not rewrite engine or generation flow.
- Remove/replace old Voiceover UI (e.g., `VoiceoverPersistentPlayerView`, `VoiceoverPlayerBar`, `VoiceoverPlayerHost`) with the Audio Guides hero + mini player UI.
- Extend playback controls with ±5s seek buttons and press-and-hold accelerated seek (±5s every **0.1s** while held).
- Playback speed presets: **0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 2x** (global per user).
- **History is display-only**: stored for "Last Played" UI display, but **NOT used for Previous button navigation**. **Max 50 items** in history.
- **Previous button traverses baseList only**: Previous goes to chronologically older items in the list (Spotify-like behavior), not based on play order.
- **Skipped stack for bidirectional navigation**: When Previous is pressed, current item is pushed to `skipped` stack. Next pops from `skipped` first, then queues, then baseList.
- Progress is display-only: persist last-played position per discovery for UI display ("you listened until here"), but playback always starts from position 0.
- Queue model: Play Next = LIFO (most recent plays first), Add to End = FIFO (first added plays first).
- Autoplay: when enabled, skip items that are not ready; skipped non-ready items are moved to Play Next queue. Failed requires user retry before playback.
- My Discoveries list uses the same Discovery dataset (1:1 with Discovery feed).
- Use existing "generate voiceover" edge function for Audio Guides; reuse credits behavior and storage/caching policies.
- Voiceover status fetched on Discoveries tab immediately after loading discoveries.
- Stale session handling: auto-clear queue/history after 24h of inactivity (no user prompt).
- **baseList is audio-ready filtered**: When populating baseList, only discoveries with ready voiceover status are included.
- **baseList uses full snapshot with lazy expansion**: No fixed 20-item window. Full list of audio-ready items is used, with lazy expansion via `needsExpansion` signal when approaching edges.
- **Validate on app launch**: `validateBaseList()` removes deleted discoveries from all queues on startup.

## Completed Investigation Tasks
- ✅ Audited `VoiceoverFileCache`: 150MB max, LRU eviction by `lastAccessedAt`. Policy sufficient for Audio Guides.
- ✅ Reviewed `VoiceoverPlaybackController.normalize()`: processing stale after 5min, failed expires after 1hr.
- ✅ Confirmed discovery images work as lock screen artwork via existing `MPMediaItemArtwork` integration.
- ✅ Decided in-flight download tracking: add `inFlightDownloads: [Int64: Task<URL?, Error>]` to `VoiceoverFileCache`.

---

## File Changes Summary

### Phase 1: State Stores & Data Layer

| Action | Path | Purpose |
|--------|------|---------|
| **NEW** | `WhatsThatDomain/Discovery/DiscoveryStore.swift` | Shared actor cache for discoveries |
| **NEW** | `WhatsThatPresentation/Shared/Services/AudioServicesContainer.swift` | Dependency container for all audio stores |
| **NEW** | `WhatsThatPresentation/Shared/Services/NetworkMonitor.swift` | Network connectivity detection + auto-retry |
| **NEW** | `WhatsThatPresentation/Shared/Stores/VoiceoverProgressStore.swift` | Per-discovery position persistence |
| **NEW** | `WhatsThatPresentation/Shared/Stores/VoiceoverPlaybackSpeedStore.swift` | Global playback speed |
| **NEW** | `WhatsThatPresentation/Shared/Stores/MiniPlayerPresenceStore.swift` | Mini player visibility + inset |
| **NEW** | `WhatsThatPresentation/Features/AudioGuides/Stores/AudioGuidesQueueStore.swift` | Queue/history/autoplay persistence |
| **MODIFY** | `WhatsThatDomain/Discovery/DiscoveryDeletionUseCase.swift` | Add audio cleanup cascade on deletion |
| **MODIFY** | `WhatsThatShared/Caching/VoiceoverFileCache.swift` | Add in-flight download tracking + remove method |
| **MODIFY** | `WhatsThatPresentation/Shared/Controllers/VoiceoverPlaybackController.swift` | Add seek/rate methods, container integration |

### Phase 2: ViewModel Refactor

| Action | Path | Purpose |
|--------|------|---------|
| **MODIFY** | `WhatsThatPresentation/DiscoveryFeedViewModel.swift` | Inject DiscoveryStore, add voiceover prefetch |
| **REWRITE** | `WhatsThatPresentation/Features/AudioGuides/AudioGuidesViewModel.swift` | Remove mocks, use real stores |
| **DELETE** | `WhatsThatPresentation/Features/AudioGuides/AudioGuidesModels.swift` | Remove `AudioGuide` struct (use DiscoverySummary) |
| **NEW** | `WhatsThatPresentation/Features/AudioGuides/AudioGuideRowStateProvider.swift` | Pre-computed row states |

### Phase 3: UI Components

| Action | Path | Purpose |
|--------|------|---------|
| **REWRITE** | `WhatsThatPresentation/Features/AudioGuides/HeroPlayerView.swift` | Wire to VoiceoverPlaybackController |
| **REWRITE** | `WhatsThatPresentation/Features/AudioGuides/MiniPlayerView.swift` | Wire to VoiceoverPlaybackController |
| **REWRITE** | `WhatsThatPresentation/Features/AudioGuides/AudioGuideRowView.swift` | Use DiscoverySummary + computed status |
| **REWRITE** | `WhatsThatPresentation/Features/AudioGuides/AudioGuidesPageView.swift` | Use new ViewModel, add tab swipe gesture |
| **MODIFY** | `WhatsThatPresentation/App/MainTabView.swift` | Host mini player globally, remove legacy inset |

### Phase 4: Legacy Removal

| Action | Path | Purpose |
|--------|------|---------|
| **DELETE** | `WhatsThatPresentation/Shared/Voiceover/VoiceoverPersistentPlayerView.swift` | Replaced by MiniPlayerView |
| **DELETE** | `WhatsThatPresentation/Shared/Voiceover/VoiceoverPlayerBar.swift` | Replaced by MiniPlayerView |
| **DELETE** | `WhatsThatPresentation/Shared/Voiceover/VoiceoverPlayerHost.swift` | Replaced by MainTabView overlay |
| **DELETE** | `WhatsThatPresentation/Shared/Voiceover/VoiceoverPlayerInsetStore.swift` | Replaced by MiniPlayerPresenceStore |

---

# Phase 1: State Stores & Data Layer (Detailed)

## 1.1 VoiceoverFileCache Modification

**File:** `WhatsThatShared/Caching/VoiceoverFileCache.swift`

**Current state:** The cache stores audio files with LRU eviction but doesn't track in-flight downloads. Multiple concurrent requests for the same discoveryId could trigger duplicate downloads.

**Changes required:**

```swift
// ADD: New property to track in-flight downloads
public actor VoiceoverFileCache: Sendable {
    // ... existing properties ...
    
    /// Tracks in-flight download tasks to prevent duplicate downloads
    private var inFlightDownloads: [Int64: Task<URL?, Error>] = [:]
    
    // ... existing init ...
}

// ADD: New public method for coalesced downloads
public extension VoiceoverFileCache {
    /// Downloads and caches a voiceover file, coalescing concurrent requests.
    /// If a download is already in flight for this discoveryId, returns the existing task's result.
    func downloadAndCache(
        discoveryId: Int64,
        fileName: String,
        downloadURL: URL,
        urlSession: URLSession = .shared
    ) async throws -> URL? {
        // Return existing in-flight task if present
        if let existingTask = inFlightDownloads[discoveryId] {
            return try await existingTask.value
        }
        
        // Check cache first
        if let cached = await cachedFileURL(discoveryId: discoveryId, fileName: fileName) {
            return cached
        }
        
        // Create new download task
        let task = Task<URL?, Error> {
            defer { inFlightDownloads.removeValue(forKey: discoveryId) }
            
            let (data, response) = try await urlSession.data(from: downloadURL)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            return try await store(data: data, discoveryId: discoveryId, fileName: fileName)
        }
        
        inFlightDownloads[discoveryId] = task
        return try await task.value
    }
    
    /// Cancels an in-flight download if one exists
    func cancelDownload(for discoveryId: Int64) {
        inFlightDownloads[discoveryId]?.cancel()
        inFlightDownloads.removeValue(forKey: discoveryId)
    }
    
    /// Returns true if a download is in progress for this discoveryId
    func isDownloading(_ discoveryId: Int64) -> Bool {
        inFlightDownloads[discoveryId] != nil
    }
}
```

---

## 1.2 Discovery Deletion Cleanup Cascade

**Purpose:** When a discovery is deleted, cascade the deletion to all audio-related caches and stores.

**Current State:** `DiscoveryDeletionUseCase.delete()` only calls `repository.deleteDiscovery()`. No audio cleanup exists.

**Changes Required:**

Modify `DiscoveryDeletionUseCase` to accept cleanup dependencies:

```swift
public actor DiscoveryDeletionUseCase: Sendable {
    private let repository: DiscoveryRepository
    private let voiceoverFileCache: VoiceoverFileCache
    private let progressStore: VoiceoverProgressStore
    private let queueStore: AudioGuidesQueueStore
    
    public init(
        repository: DiscoveryRepository,
        voiceoverFileCache: VoiceoverFileCache,
        progressStore: VoiceoverProgressStore,
        queueStore: AudioGuidesQueueStore
    ) {
        self.repository = repository
        self.voiceoverFileCache = voiceoverFileCache
        self.progressStore = progressStore
        self.queueStore = queueStore
    }
    
    public func delete(_ summary: DiscoverySummary) async throws {
        let discoveryId = summary.id
        
        // 1. Delete from backend
        try await repository.deleteDiscovery(summary)
        
        // 2. Delete cached audio file
        await voiceoverFileCache.remove(discoveryId: discoveryId)
        
        // 3. Clear progress/lastPlayed
        await progressStore.clearPosition(for: discoveryId)
        
        // 4. Remove from queue/history
        await queueStore.removeFromAllLists(discoveryId)
    }
}
```

**Add to VoiceoverFileCache:**

```swift
public extension VoiceoverFileCache {
    /// Removes all cached files for a discovery
    func remove(discoveryId: Int64) {
        // Remove from index
        index.removeAll { $0.discoveryId == discoveryId }
        
        // Delete files from disk
        let discoveryDir = cacheDirectory.appendingPathComponent("\(discoveryId)")
        try? FileManager.default.removeItem(at: discoveryDir)
        
        saveIndex()
    }
}
```

**Add to AudioGuidesQueueStore:**

```swift
public func removeFromAllLists(_ id: Int64) {
    immediate.removeAll { $0 == id }
    deferred.removeAll { $0 == id }
    history.removeAll { $0 == id }
    baseList.removeAll { $0 == id }
    if current == id {
        current = nil
    }
    save()
}
```

---

## 1.3 AudioServicesContainer (NEW)

**File:** `WhatsThatPresentation/Shared/Services/AudioServicesContainer.swift`

**Purpose:** Single dependency container that holds all audio-related stores. Injected once at the app root and flows through the view hierarchy via SwiftUI environment.

```swift
import Foundation
import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// Central container for all audio/voiceover-related services.
/// Created once at app launch and injected via environment.
@MainActor
public final class AudioServicesContainer: ObservableObject {
    
    // MARK: - Stores
    
    /// Queue, history, autoplay state for Audio Guides
    public let queueStore: AudioGuidesQueueStore
    
    /// Global playback speed (shared across all voiceover surfaces)
    public let speedStore: VoiceoverPlaybackSpeedStore
    
    /// Per-discovery playback position (display-only)
    public let progressStore: VoiceoverProgressStore
    
    /// Mini player visibility and height for scroll insets
    public let miniPlayerPresence: MiniPlayerPresenceStore
    
    /// Shared discovery cache
    public let discoveryStore: DiscoveryStore
    
    /// Audio file cache with in-flight tracking
    public let fileCache: VoiceoverFileCache
    
    // MARK: - Playback Controller
    
    /// Shared playback controller (created with container dependencies)
    public let playbackController: VoiceoverPlaybackController
    
    // MARK: - Init
    
    public init(
        repository: DiscoveryRepository,
        voiceoverRepository: DiscoveryVoiceoverRepository,
        defaults: UserDefaults = .standard
    ) {
        // Create stores
        self.queueStore = AudioGuidesQueueStore(defaults: defaults)
        self.speedStore = VoiceoverPlaybackSpeedStore(defaults: defaults)
        self.progressStore = VoiceoverProgressStore(defaults: defaults)
        self.miniPlayerPresence = MiniPlayerPresenceStore()
        self.discoveryStore = DiscoveryStore(repository: repository)
        self.fileCache = VoiceoverFileCache.shared
        
        // Create playback controller with store references
        self.playbackController = VoiceoverPlaybackController(
            repository: voiceoverRepository,
            voiceoverCache: fileCache
        )
        
        // Wire up stores to controller
        playbackController.configure(
            queueStore: queueStore,
            speedStore: speedStore,
            progressStore: progressStore
        )
    }
}

// MARK: - Environment Key

private struct AudioServicesKey: EnvironmentKey {
    static let defaultValue: AudioServicesContainer? = nil
}

public extension EnvironmentValues {
    var audioServices: AudioServicesContainer? {
        get { self[AudioServicesKey.self] }
        set { self[AudioServicesKey.self] = newValue }
    }
}

public extension View {
    func audioServices(_ container: AudioServicesContainer) -> some View {
        environment(\.audioServices, container)
    }
}
```

**Usage in App Root:**

```swift
// In WhatsThatApp.swift or root view
@StateObject private var audioServices = AudioServicesContainer(
    repository: supabaseDiscoveryRepository,
    voiceoverRepository: supabaseVoiceoverRepository
)

var body: some Scene {
    WindowGroup {
        MainTabView(...)
            .audioServices(audioServices)
            .environmentObject(audioServices.playbackController)
            .environmentObject(audioServices.miniPlayerPresence)
    }
}
```

**Usage in Child Views:**

```swift
struct AudioGuidesPageView: View {
    @Environment(\.audioServices) private var services
    
    var body: some View {
        // Access stores via services.queueStore, services.progressStore, etc.
    }
}
```

---

## 1.4 VoiceoverPlaybackController Modifications

**File:** `WhatsThatPresentation/Shared/Controllers/VoiceoverPlaybackController.swift`

**Current state:** Has playback, generation, prefetch. Missing: seek(by:), rate control, container integration.

**Changes required:**

```swift
// ADD: New properties (inside class declaration)
@MainActor
public final class VoiceoverPlaybackController: ObservableObject {
    // ... existing properties ...
    
    /// Current playback rate (persisted via VoiceoverPlaybackSpeedStore)
    @Published public private(set) var currentRate: Double = 1.0
    
    /// Store references (set via configure())
    private var queueStore: AudioGuidesQueueStore?
    private var speedStore: VoiceoverPlaybackSpeedStore?
    private var progressStore: VoiceoverProgressStore?
    
    // ... existing init unchanged ...
}

// ADD: Configuration method called by AudioServicesContainer
public extension VoiceoverPlaybackController {
    
    /// Called once by AudioServicesContainer after creation.
    /// Wires up stores for queue integration, speed persistence, and progress tracking.
    func configure(
        queueStore: AudioGuidesQueueStore,
        speedStore: VoiceoverPlaybackSpeedStore,
        progressStore: VoiceoverProgressStore
    ) {
        self.queueStore = queueStore
        self.speedStore = speedStore
        self.progressStore = progressStore
        
        // Initialize rate from persisted value
        self.currentRate = speedStore.speed
        player.rate = Float(speedStore.speed)
    }
    
    // MARK: - Seek Controls
    
    /// Seek forward/backward by seconds
    func seek(by seconds: TimeInterval) {
        guard let duration = player.currentItem?.duration.seconds,
              duration.isFinite else { return }
        
        let currentTime = player.currentTime().seconds
        let newTime = max(0, min(duration, currentTime + seconds))
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: 600)) { [weak self] _ in
            // Persist position after seek
            if let discoveryId = self?.currentDiscovery?.id {
                Task { @MainActor in
                    self?.progressStore?.updatePosition(newTime, for: discoveryId)
                }
            }
        }
    }
    
    /// Seek to specific position (0.0 to 1.0)
    func seek(to fraction: Double) {
        guard let duration = player.currentItem?.duration.seconds,
              duration.isFinite else { return }
        
        let newTime = duration * max(0, min(1, fraction))
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
    }
    
    // MARK: - Rate Control
    
    /// Set playback rate and persist
    func setRate(_ rate: Double) {
        let validRates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        guard validRates.contains(rate) else { return }
        
        player.rate = Float(rate)
        currentRate = rate
        speedStore?.speed = rate
    }
    
    /// Cycle to next playback speed
    func cycleRate() {
        let validRates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        guard let currentIndex = validRates.firstIndex(of: currentRate) else {
            setRate(1.0)
            return
        }
        let nextIndex = (currentIndex + 1) % validRates.count
        setRate(validRates[nextIndex])
    }
}
```

**MODIFY existing methods:**

```swift
// In existing skipToNextDiscovery() - integrate with queue store
@discardableResult
func skipToNextDiscovery() -> DiscoverySummary? {
    // NEW: Use queue store if available
    if let queueStore = queueStore {
        Task { @MainActor in
            if let nextId = await queueStore.next() {
                // Look up discovery from store and play
                // (This requires DiscoveryStore access - see architecture below)
            }
        }
    }
    
    // EXISTING: Fall back to discoveryQueueProvider for legacy callers
    guard let discovery = nextDiscoveryInQueue() else { return nil }
    togglePlayback(for: discovery)
    return discovery
}

// In existing time observer callback - persist progress periodically
private func setupTimeObserver() {
    // ... existing code ...
    timeObserverToken = player.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 5, preferredTimescale: 600),  // Every 5 seconds
        queue: .main
    ) { [weak self] time in
        guard let self = self,
              let discoveryId = self.currentDiscovery?.id else { return }
        
        // Persist position for display
        Task { @MainActor in
            self.progressStore?.updatePosition(time.seconds, for: discoveryId)
        }
    }
}
```

---


## Architecture & Data Model Summary

- **Identity**: use stable `discovery.id` (`Int64`) everywhere; no transient UUIDs. Audio Guides operates on the same `DiscoverySummary` models already used elsewhere—remove the separate `AudioGuide` struct.
- **Queue model**: Play Next = LIFO, Add to End = FIFO, max 100 items across immediate + deferred.
- **History**: Max 50 items, oldest pruned.
- **Progress**: Display-only; playback always starts from position 0.
- **Speed**: Global presets (0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 2x), persisted.

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

> [!IMPORTANT]
> **SwiftUI Observation Pattern**: `VoiceoverPlaybackController` properties like `currentDiscovery`, `position`, and `playbackState` are `@Published` on the controller, but computed properties that passthrough to the controller (e.g., `var currentDiscovery: DiscoverySummary? { voiceoverController.currentDiscovery }`) do **NOT trigger SwiftUI re-renders** in views that observe the ViewModel but not the controller. 
>
> **Required pattern**: Republish controller state as `@Published` properties on the ViewModel via Combine subscriptions in `setupBindings()`.

> [!IMPORTANT]
> **Audio-Ready Filtering**: The `baseList` passed to `queueStore.playNow()` must be filtered to only include discoveries with ready audio guides. Otherwise, the `next()` method may advance to items without audio, and those items can get pushed to history. Similarly, `historyItems` and `nextBaseItems` should filter by ready status.

```swift
@MainActor
final class AudioGuidesViewModel: ObservableObject {
    @Published private(set) var localIds: [Int64] = []
    @Published private(set) var isLoadingVoiceoverStatus = false
    
    // MARK: - Playback State (republished for SwiftUI observation)
    
    /// The currently playing discovery - republished from VoiceoverPlaybackController
    @Published public private(set) var nowPlayingDiscovery: DiscoverySummary?
    
    /// Items from baseList after the current index (shown in Up Next when queues are empty)
    /// Filtered to only include audio-ready items
    @Published public private(set) var nextBaseItems: [Int64] = []
    
    /// Version counter to trigger row re-renders when states change
    @Published public private(set) var rowStateVersion: Int = 0
    
    private let discoveryStore: DiscoveryStore
    private let queueStore: AudioGuidesQueueStore
    private let voiceoverController: VoiceoverPlaybackController
    private var cancellables = Set<AnyCancellable>()
    private var didInitialPrefetch = false
    private var cursor: Int64?
    private var hasMore = true
    
    /// Current discovery being played (convenience accessor)
    public var currentDiscovery: DiscoverySummary? {
        nowPlayingDiscovery  // Use republished @Published property
    }
    
    /// Up Next queue: immediate + deferred queues (user-added items only)
    public var upNextItems: [Int64] {
        queueStore.upNextQueue
    }
    
    /// Combined Up Next: queued items + base list fallback (for display in UpNextListView)
    public var allUpNextItems: [Int64] {
        let queued = queueStore.upNextQueue
        if queued.isEmpty {
            return nextBaseItems
        }
        return queued + nextBaseItems
    }
    
    /// History items filtered to only show items with audio guides
    public var historyItems: [Int64] {
        let assetStates = voiceoverController.assetStates
        return queueStore.history
            .filter { id in
                guard let asset = assetStates[id] else { return false }
                return asset.status == .ready
            }
            .prefix(historyLimit)
            .map { $0 }
    }
    
    /// Returns discovery IDs that have ready audio guides
    /// Used when building baseList for queue navigation
    private var audioReadyIds: [Int64] {
        let assetStates = voiceoverController.assetStates
        return localIds.filter { id in
            guard let asset = assetStates[id] else { return false }
            return asset.status == .ready
        }
    }
    
    // MARK: - Playback Actions
    
    public func play(discovery: DiscoverySummary) {
        // Get base list for queue context - ONLY include audio-ready items
        // This ensures next()/previous() only navigates to playable discoveries
        let baseList = audioReadyIds
        
        // playNow will trim to ~20 items on each side of current
        queueStore.playNow(discovery.id, recentering: baseList)
        voiceoverController.togglePlayback(for: discovery)
    }
    
    // MARK: - Combine Bindings
    
    private func setupBindings() {
        // Invalidate row states and increment version counter on queue changes
        queueStore.$current
            .sink { [weak self] _ in
                self?.rowStateProvider.invalidateAll()
                self?.rowStateVersion += 1
            }
            .store(in: &cancellables)
        
        // Republish currentDiscovery from controller for SwiftUI observation
        voiceoverController.$currentDiscovery
            .receive(on: DispatchQueue.main)
            .sink { [weak self] discovery in
                self?.nowPlayingDiscovery = discovery
            }
            .store(in: &cancellables)
        
        // Observe baseList, baseIndex, and assetStates to update nextBaseItems
        // Filter to only include discoveries with ready audio guides
        Publishers.CombineLatest4(
            queueStore.$baseList,
            queueStore.$baseIndex,
            queueStore.$current,
            voiceoverController.$assetStates
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] baseList, baseIndex, _, assetStates in
            guard let self else { return }
            if baseIndex + 1 < baseList.count {
                let candidateIds = Array(baseList[(baseIndex + 1)...])
                // Filter to only include items with ready audio guides
                let readyItems = candidateIds.filter { id in
                    guard let asset = assetStates[id] else { return false }
                    return asset.status == .ready
                }
                // Limit to ~10 items for display
                self.nextBaseItems = Array(readyItems.prefix(10))
            } else {
                self.nextBaseItems = []
            }
        }
        .store(in: &cancellables)
    }
    
    // ... loadMoreIfNeeded, etc.
}
```

> [!TIP]
> **Row Highlight State**: To ensure rows correctly show the "now playing" highlight state, the ViewModel exposes a `@Published rowStateVersion: Int` counter that increments whenever row states are invalidated. Row views should use `.id("row-\(discoveryId)-\(viewModel.rowStateVersion)")` to force SwiftUI to recreate the view when states change. Without this, computed `rowState(for:)` values may not trigger re-renders.

### Queue Base List Filtering

When `play()` is called:
1. `audioReadyIds` filters `localIds` to only discoveries with `.ready` voiceover status
2. `queueStore.playNow(id, recentering: audioReadyIds)` is called with this filtered list
3. Inside `playNow`, `trimBaseList()` creates a window of **~20 audio-ready items on each side** of the current item
4. This ensures `next()`/`previous()` only navigates to playable discoveries

### Navigation Direction

> [!IMPORTANT]
> **baseList ordering**: `localIds` (and therefore `baseList`) is ordered **newest-first** (index 0 = most recent discovery). This affects navigation direction:
> - **`next()`**: Decrements `baseIndex` → goes towards newer items (lower indices)
> - **`previous()`**: Increments `baseIndex` → goes towards older items (higher indices)
>
> **`nextBaseItems`** must show items **before** `baseIndex` (the upcoming newer items), not after.

### Navigation Availability

`AudioGuidesQueueStore` provides computed properties to check if navigation is possible:

```swift
/// Returns true if there is a next item to play
/// Priority: skipped stack, immediate queue, deferred queue, or baseList items before current (newer items)
public var hasNext: Bool {
    !skipped.isEmpty || !immediate.isEmpty || !deferred.isEmpty || baseIndex > 0
}

/// Returns true if there is a previous item to go back to
/// Only checks baseList items after current (older items) - history is display-only
public var hasPrevious: Bool {
    baseIndex + 1 < baseList.count
}
```

> [!IMPORTANT]
> **History is display-only**: `hasPrevious` does NOT check history. The Previous button only traverses the baseList (chronologically older items). History is used exclusively for the "Last Played" UI section.

### Button Disable States

`MiniPlayerView` and `HeroPlayerView` observe the `queueStore` to disable and grey out buttons:

```swift
@ObservedObject var queueStore: AudioGuidesQueueStore

private var canPlayNext: Bool {
    queueStore.hasNext
}

private var canPlayPrevious: Bool {
    // Always allow previous if playing (for restart functionality)
    controller.position > 3.0 || queueStore.hasPrevious
}
```

Button styling when disabled:
```swift
Button(action: playNext) {
    Image(systemName: "forward.end.fill")
        .foregroundColor(canPlayNext
            ? BrandTheme.palette(for: colorScheme).textPrimary
            : BrandTheme.palette(for: colorScheme).textSecondary.opacity(0.4))
}
.disabled(!canPlayNext)
```

### Previous Button Behavior

The previous button has dual behavior based on playback position:

1. **Position > 3 seconds**: Restart current track (seek to 0)
2. **Position ≤ 3 seconds**: Go to chronologically older track in baseList (NOT history)

> [!IMPORTANT]
> Previous traverses the **baseList** only, moving to older items (incrementing `baseIndex`). It does **NOT** pop from history. Before moving, the current item is pushed to the `skipped` stack so that Next can return to it.

```swift
private func playPrevious() {
    let currentPosition = controller.position
    let currentId = queueStore.current
    
    if let prevId = queueStore.previous(currentPosition: currentPosition) {
        // If previous() returns the same ID, it means "restart current"
        if prevId == currentId {
            controller.seek(to: 0) {}
        } else {
            // Different track - switch to it (this was pushed to skipped stack)
            Task {
                if let discovery = await audioServices.discoveryStore.get(id: prevId) {
                    controller.togglePlayback(for: discovery)
                }
            }
        }
    }
}
```

---

# Phase 2: ViewModel Refactor (Detailed)

## 2.1 Delete AudioGuidesModels.swift

**File:** `WhatsThatPresentation/Features/AudioGuides/AudioGuidesModels.swift`

**Action:** DELETE entirely. The `AudioGuide` struct with UUID identity is incompatible with our requirements.

**Current problematic code:**
```swift
// DELETE THIS FILE
struct AudioGuide: Identifiable, Equatable {
    let id = UUID()  // ❌ Unstable identity
    let title: String
    let duration: TimeInterval
    // ...
}
```

**Replacement:** Use `DiscoverySummary` directly. Status is computed from `VoiceoverPlaybackController.normalizedAsset(for:)`.

---

## 2.2 AudioGuideRowStateProvider (NEW)

**File:** `WhatsThatPresentation/Features/AudioGuides/AudioGuideRowStateProvider.swift`

To avoid per-render recomputation from 3 sources, create a pre-computed `AudioGuideRowState` struct:

```swift
struct AudioGuideRowState: Equatable {
    let discoveryId: Int64
    let voiceoverStatus: AudioGuideRowStatus
    let isQueued: Bool
    let isPlaying: Bool
    let progress: Double?
}

enum AudioGuideRowStatus {
    case ready, generating, failed, empty
}

// Computed once per discovery, updated only when stores change
@MainActor
final class AudioGuideRowStateProvider: ObservableObject {
    @Published private(set) var rowStates: [Int64: AudioGuideRowState] = [:]
    
    private let voiceoverController: VoiceoverPlaybackController
    private let queueStore: AudioGuidesQueueStore
    private let progressStore: VoiceoverProgressStore
    
    func rowState(for discoveryId: Int64) -> AudioGuideRowState {
        if let cached = rowStates[discoveryId] { return cached }
        return computeRowState(for: discoveryId)
    }
    
    private func computeRowState(for discoveryId: Int64) -> AudioGuideRowState {
        let asset = voiceoverController.normalizedAsset(for: discoveryId)
        let status: AudioGuideRowStatus = {
            guard let asset else { return .empty }
            switch asset.status {
            case .ready: return .ready
            case .processing: return .generating
            case .failed: return .failed
            case .none, .missing: return .empty
            }
        }()
        
        return AudioGuideRowState(
            discoveryId: discoveryId,
            voiceoverStatus: status,
            isQueued: queueStore.isQueued(discoveryId),
            isPlaying: queueStore.current == discoveryId,
            progress: progressStore.position(for: discoveryId)
        )
    }
}
```

### Voiceover Status Fetching Strategy
Voiceover metadata (ready/generating/failed/empty) is fetched via `VoiceoverPlaybackController.prefetch(for:)` with internal caching in `SupabaseVoiceoverRepository`.

- **Discoveries tab**: Fetch voiceover status **immediately after loading discoveries** via `voiceoverController.prefetch(for: loadedIds)`. This ensures status is known when user taps a discovery.
- **Audio Guides page entry**: On first appearance, take all discovery IDs from `DiscoveryStore.allCachedIds()` and call `voiceoverController.prefetch(for: allCachedIds)` to batch-fetch statuses.
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

## List View States
- **Empty state for Up Next**: "Select an audio guide from My Discoveries to start playing."
- **Empty state for My Discoveries**: Design pending (to be finalized during implementation).
- **Loading state for My Discoveries**: Skeleton/shimmer rows during initial load.
- **Pull-to-refresh**: My Discoveries supports pull-to-refresh to reload discoveries and voiceover statuses.

## Up Next Tab Header Controls
The Up Next tab header contains:
1. **Down arrow button** (left): Closes the list sheet and returns to hero view.
2. **Clear Queue button** (center/right): Clears all queued items. Shows confirmation dialog: "Clear all queued items?" with Cancel/Clear actions.
3. **Auto-play toggle** (right): Enables/disables auto-advance to next item.


## Up Next Queue Behavior – Spec
- Base context: when the user taps a discovery to play, initialise or update the base playlist to reflect the **audio-ready** discoveries around that item. `baseList` contains **all audio-ready discovery IDs** (no fixed window), and `baseIndex` points at the currently playing item. The base playlist is allowed to evolve over time via `insertVoiceoverReady()` when voiceovers become ready.
- **baseList ordering**: Ordered **newest-first** (index 0 = most recent discovery).
- **Lazy expansion**: When approaching edges (within 5 items of either end), `needsExpansion` signal is published. ViewModel fetches more discoveries and calls `expandBaseList()`.
- Queue layers (mirrors Spotify/Apple Music):
  - **Immediate queue (front)**: items added via "Play Next" are enqueued **LIFO** (most recent plays first).
  - **Deferred queue (tail)**: items added via "Add to End" are appended **FIFO** (first added plays first).
  - **Queue limit**: Maximum **100 items** across immediate + deferred.
  - Base fallback: after queues drain, advance through `baseList` (decrementing `baseIndex` for newer items).
- **Skipped stack for bidirectional navigation**:
  - When Previous is pressed, current item is pushed to `skipped` stack before moving.
  - Next pops from `skipped` first, allowing return traversal.
  - `playNow()` clears the skipped stack (user made explicit choice).
- Next selection order: **skipped** (if any) → head of Immediate → head of Deferred → baseList (decrement baseIndex for newer). When a queued item is consumed, push the prior current item into history.
- **Prev behavior (list traversal only)**: if current playback position > restartThreshold (3s), restart current; else push current to skipped and increment `baseIndex` (go to older item in baseList). **Does NOT pop from history** – history is display-only.
- History visibility: surfaced in UI under "Just Played" / "Last Played"; **max 50 items** in history, oldest pruned when exceeded. History is populated whenever we advance to a new item but is **never consulted for navigation**.
- Ad-hoc play while queue exists: tapping any discovery (e.g., from Discoveries grid or My Discoveries) replaces current, pushes prior current to history, clears skipped, and keeps both queue layers intact. The base playlist is re-centred on the new discovery. After the ad-hoc item ends, playback resumes skipped → Immediate → Deferred → base fallback from this new base context.
- Auto-generated/ready items:
  - `insertVoiceoverReady()` inserts newly-ready voiceovers at their correct chronological position in baseList.
  - Works symmetrically for both newer items (reachable via Next) and older items (reachable via Previous).
  - Default insertion for manually enqueued items remains: "Play Next" enqueues into Immediate (LIFO); "Add to End" appends to Deferred tail (FIFO).
  - Skip non-ready items (processing/failed) when autoplay is on; skipped items are **silently** moved to Play Next queue (no visual indicator, no toast). Playback moves on to the next ready item.
- Persistence/staleness:
  - Persist: queue ordering (Immediate/Deferred), base snapshot identifiers, baseIndex, current item, history stack, **skipped stack**, autoplay toggle, and per-discovery progress.
  - **Stale session rule**: if no playback activity for 24h, **auto-clear** queue/history without prompting user.
  - Auto-prune completed items from queue/history as they are consumed; dedupe queued items by discovery ID.
- **Validate on app launch**: `validateBaseList(validIds:)` removes deleted discoveries from all lists (baseList, immediate, deferred, history, skipped) and recalculates baseIndex.
- Clear affordance: explicit "Clear queue" action removes Immediate/Deferred only, while leaving **baseList**, history, skipped, and current intact; current continues and will fall back to base traversal when done. **Requires confirmation dialog** before clearing.
- Duplicate prevention: if an item is already in Immediate or Deferred, do not add again; "Play Next" on already-queued item **moves it to front** instead. If playing, mark as `Playing`; if queued, mark as `Queued` in My Discoveries chips.
- Layout implications (list):
  - Sections: Now Playing (pinned row, **cannot be removed**) → Up Next (Immediate then Deferred in order) → Last Played (show 3 items, "Expand history" shows 10 more).
  - Swipe-to-remove on Up Next rows (excluding Now Playing) removes from the corresponding queue.
- Data model needs:
  - Stable discovery IDs; queue entries carry ID only (status derived from `VoiceoverPlaybackController.normalizedAsset()`).
  - Persisted structures: `immediate: [Int64]`, `deferred: [Int64]`, `baseList: [Int64]`, `baseIndex: Int`, `history: [Int64]`, `skipped: [Int64]`, `current: Int64?`, `autoplayEnabled: Bool`, `lastActivityAt: Date?`.
  - Resume logic loads persisted structures; if any IDs are missing/absent, drop them silently via `validateBaseList()`.

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
- **Rate limiting**: Maximum **2 concurrent generation requests**. Additional requests are locally queued and show a **"Generation queued"** state (same visual as generating: ghosted row + spinner). Requests are sent when a slot frees up.
- **Zero credits handling**: If user has zero credits, credit modal shows "Get More Credits" CTA instead of proceeding with generation.
- **Insufficient credits error**: If server returns insufficient credits error, show alert with CTA to purchase credits screen.
- **"Get More Credits" navigation**: Tapping "Get More Credits" CTA opens the **Credits Sheet** (slides up from bottom) which displays credit balance and purchase options.
- Auto-generate toggle (Settings):
  - Remains owned by the existing voiceover preferences and creation flows (out of scope for Audio Guides).
  - Audio Guides integration is limited to reflecting whatever assets and queue entries exist as a result.
- Balance updates:
  - Credit balance continues to be managed by the existing credits infrastructure. When generation responses include updated balance, the global credit balance store is updated there; Audio Guides reads any exposed balance for UI copy but never decrements locally.

## Storage, Caching, Offline/Streaming
- Reuse `VoiceoverFileCache` for audio guides; continue storing audio under `Voiceovers/<discoveryId>/fileName` as implemented today.
- **Current cache policy** (verified from code):
  - **Max size**: 150MB (`maxBytes = 150 * 1024 * 1024`)
  - **Eviction strategy**: LRU (Least Recently Used) by `lastAccessedAt`
  - **Trigger**: After each `store()` call, if `totalBytes > maxBytes`
  - Sufficient for Audio Guides (~50-100 voiceovers). No changes needed.
- **In-flight download tracking**: Add `inFlightDownloads: [Int64: Task<URL?, Error>]` to `VoiceoverFileCache`. If a download is requested for a discoveryId already in flight, return the existing Task's result instead of starting a new download.
- No streaming—download audio file fully before playback.
- Prefetch:
  - Anything that enters the Up Next queue triggers prefetch in queue order (download priority = playback order).
  - Audio Guides must not bypass `VoiceoverPlaybackController` to fetch assets directly.
- Offline behavior:
  - If a guide is `ready` but not present in `VoiceoverFileCache` and the device is offline, block playback and show an "Offline – not downloaded" chip/badge in the row.
  - Detect offline via `NWPathMonitor` (Network framework) + `voiceoverCache.cachedFileURL`; if offline and missing cache, disable play and surface inline message.
  - If playback starts online then loses connection: fails if not cached, continues if cached.
  - **Offline banner**: Subtle "You're offline" banner appears at **top of screen**, auto-dismisses after ~5 seconds or when connectivity returns.

### Network Connectivity Detection & Auto-Retry

**File:** `WhatsThatPresentation/Shared/Services/NetworkMonitor.swift` (NEW)

```swift
import Network
import Combine

@MainActor
public final class NetworkMonitor: ObservableObject {
    @Published public private(set) var isConnected: Bool = true
    @Published public private(set) var connectionType: NWInterface.InterfaceType?
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    /// Callbacks registered for retry when connectivity returns
    private var reconnectCallbacks: [() async -> Void] = []
    
    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasConnected = self?.isConnected ?? true
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
                
                // Trigger auto-retry callbacks if we just reconnected
                if !wasConnected && path.status == .satisfied {
                    await self?.executeReconnectCallbacks()
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    /// Register a callback to be executed when connectivity returns
    public func onReconnect(_ callback: @escaping () async -> Void) {
        reconnectCallbacks.append(callback)
    }
    
    private func executeReconnectCallbacks() async {
        let callbacks = reconnectCallbacks
        reconnectCallbacks.removeAll()
        for callback in callbacks {
            await callback()
        }
    }
    
    deinit {
        monitor.cancel()
    }
}
```

**Integration with VoiceoverPlaybackController:**

```swift
// On prefetch failure due to network:
if !networkMonitor.isConnected {
    networkMonitor.onReconnect { [weak self] in
        await self?.prefetch(for: failedIds)
    }
}
```


## Error Handling
- **Playback errors**: Inline surface + retry in mini/hero. For non-offline failures, show per-row "Playback failed" chip and allow retry without blocking the rest of the queue.
- **Generation failures**: Mark item failed and allow retry. Failed items in queue kept with failed state; after skipping, move to history.
- **Playback failed auto-clear**: Use same normalization as voiceover status—failed state clears after 1 hour, treating as "no audio" for fresh retry.
- **Fetch/prefetch errors**: Silent (no toast, no banner). User just sees end of list if offline or fetch fails.
- **Auto-retry on reconnect**: When device comes back online, auto-retry any failed prefetch operations.
- **Error logging**: Log errors for debugging/analytics (implementation detail).

---

# Phase 3: UI Components (Detailed)

## 3.1 MainTabView Modifications

**File:** `WhatsThatPresentation/App/MainTabView.swift`

**Changes required:**

1. **Remove legacy voiceover inset** – Delete `@StateObject private var playerInsetStore = VoiceoverPlayerInsetStore()` and `.environmentObject(playerInsetStore)`.

2. **Remove legacy player host** – Delete the `.safeAreaInset(edge: .bottom)` block with `VoiceoverPlayerHost`.

3. **Add AudioServicesContainer injection** – Accept container and pass through environment.

4. **Add global mini player overlay** – Host mini player as ZStack overlay above TabView.

```swift
struct MainTabView: View {
    // REMOVE: @StateObject private var playerInsetStore = VoiceoverPlayerInsetStore()
    
    // ADD: Access audio services from environment
    @Environment(\.audioServices) private var audioServices
    
    // ADD: Track audio guides mode for visibility
    @State private var audioGuidesMode: AudioGuidesDisplayMode = .list
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // ... existing tabs ...
                
                // MODIFY: Pass environment to Audio Guides
                AudioGuidesPageView(
                    mode: $audioGuidesMode,
                    onTextSelected: { discovery in
                        handleAudioGuideTextSelected(discovery)
                    }
                )
                .tag(Tab.audioGuides)
                .tabItem {
                    Label("Audio Guides", systemImage: "headphones")
                }
                
                // ... remaining tabs ...
            }
            
            // REMOVE: Overlay from old implementation
            
            // ADD: Global mini player overlay
            if shouldShowMiniPlayer {
                VStack {
                    Spacer()
                    MiniPlayerView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        // REMOVE: .environmentObject(playerInsetStore)
        // ADD: controller is already in environment via AudioServicesContainer
    }
    
    private var shouldShowMiniPlayer: Bool {
        guard let services = audioServices else { return false }
        guard services.playbackController.currentDiscovery != nil else { return false }
        
        switch services.playbackController.playbackState {
        case .idle, .failed:
            return false
        default:
            break
        }
        
        // Hide in hero mode
        if selectedTab == .audioGuides && audioGuidesMode == .hero {
            return false
        }
        
        // Hide during capture/selection flows
        if let phase = activeOverlayPhase {
            switch phase {
            case .capturingInitial, .capturingRetake,
                 .selectingInitial, .selectingRetake,
                 .confirming, .requestingPermissions:
                return false
            default:
                break
            }
        }
        
        return true
    }
}
```

---

## 3.2 MiniPlayerView Rewrite

**File:** `WhatsThatPresentation/Features/AudioGuides/MiniPlayerView.swift`

**Current state:** Uses mock data and local state.

**Rewrite to:** Wire to `VoiceoverPlaybackController` via `AudioServicesContainer`.

> [!IMPORTANT]
> **Implementation Decision: Wrapper View with `@ObservedObject`**
> 
> The original plan suggested using `@EnvironmentObject private var controller: VoiceoverPlaybackController`. However, during implementation we discovered that reading `@Published` properties via environment computed properties (e.g., `services?.playbackController.currentDiscovery`) does **not** reliably trigger SwiftUI re-renders. 
> 
> **Solution:** Use a wrapper pattern where the outer view extracts the controller from the environment and passes it to an inner content view that uses `@ObservedObject`. This ensures SwiftUI properly observes changes to `currentDiscovery`, `playbackState`, `position`, etc.

```swift
struct MiniPlayerView: View {
    @Environment(\.audioServices) private var services
    @Environment(\.colorScheme) var colorScheme
    
    var onExpand: () -> Void = {}
    
    // Layout constants
    private let artworkDiameter: CGFloat = 110
    private let backgroundHeight: CGFloat = 84
    private let progressLineWidth: CGFloat = 3
    
    var body: some View {
        // Extract controller and pass to inner view that properly observes it
        if let services {
            MiniPlayerContentView(
                controller: services.playbackController,
                audioServices: services,
                colorScheme: colorScheme,
                artworkDiameter: artworkDiameter,
                backgroundHeight: backgroundHeight,
                progressLineWidth: progressLineWidth,
                onExpand: onExpand,
                onHeightChange: { height in
                    services.miniPlayerPresence.updateHeight(height)
                }
            )
        }
    }
}

/// Inner view that properly observes the playback controller via @ObservedObject
private struct MiniPlayerContentView: View {
    @ObservedObject var controller: VoiceoverPlaybackController
    let audioServices: AudioServicesContainer
    let colorScheme: ColorScheme
    // ... other parameters
    
    private var discovery: DiscoverySummary? {
        controller.currentDiscovery  // Now properly observed
    }
    
    private var isPlaying: Bool {
        if case .playing = controller.playbackState { return true }
        return false
    }
    
    var body: some View {
        // Discovery info from controller.currentDiscovery
        // Playback state from controller.playbackState
        // Progress from controller (current position / duration)
        // Play/pause via controller.togglePlayback(for:)
        // Tap -> switch to Audio Guides tab in hero mode
    }
}
```

> [!TIP]
> **Image Update Fix:** The `DiscoveryCachedImage` component may not reload when the discovery changes because SwiftUI reuses the view identity. Fix this by adding an `.id()` modifier:
> ```swift
> DiscoveryCachedImage(discoveryId: discovery.id, remoteURL: imageURL) { ... }
>     .id("artwork-\(discovery.id)-\(imagePath)")  // Force recreation
> ```

---

## 3.3 HeroPlayerView Rewrite

**File:** `WhatsThatPresentation/Features/AudioGuides/HeroPlayerView.swift`

**Current state:** Uses mock ViewModel.

**Rewrite to:** Uses the same wrapper pattern as `MiniPlayerView` for proper observation.

```swift
struct HeroPlayerView: View {
    @Environment(\.audioServices) private var services
    @Environment(\.colorScheme) var colorScheme
    
    var onTextSelected: (DiscoverySummary?) -> Void = { _ in }
    
    var body: some View {
        // Extract controller and pass to inner view
        if let services {
            HeroPlayerContentView(
                controller: services.playbackController,
                audioServices: services,
                colorScheme: colorScheme,
                onTextSelected: onTextSelected
            )
        }
    }
}

/// Inner view that properly observes the playback controller
private struct HeroPlayerContentView: View {
    @ObservedObject var controller: VoiceoverPlaybackController
    let audioServices: AudioServicesContainer
    let colorScheme: ColorScheme
    var onTextSelected: (DiscoverySummary?) -> Void
    
    @State private var selectedMode = "Audio"
    @State private var seekTimer: Timer?
    
    // Computed properties now properly observed
    private var discovery: DiscoverySummary? {
        controller.currentDiscovery
    }
    
    private var progress: Double {
        guard let duration = controller.duration, duration > 0 else { return 0 }
        return controller.position / duration
    }
    
    private var isPlaying: Bool {
        if case .playing = controller.playbackState { return true }
        return false
    }
    
    private var speedStore: VoiceoverPlaybackSpeedStore {
        audioServices.speedStore
    }
    
    private var queueStore: AudioGuidesQueueStore {
        audioServices.queueStore
    }
    
    var body: some View {
        VStack {
            // Discovery image from controller.currentDiscovery?.imagePath
            // Title, progress bar
            
            // Controls:
            HStack {
                // -5s button with press-and-hold
                seekButton(direction: .backward)
                
                // Play/pause
                Button(action: { togglePlayPause() }) {
                    // Play/pause icon based on isPlaying
                }
                
                // +5s button with press-and-hold
                seekButton(direction: .forward)
            }
            
            // Speed picker
            Menu {
                ForEach(VoiceoverPlaybackSpeedStore.validRates, id: \.self) { rate in
                    Button {
                        controller.setRate(rate)
                    } label: {
                        if speedStore.speed == rate {
                            Label(formatSpeed(rate), systemImage: "checkmark")
                        } else {
                            Text(formatSpeed(rate))
                        }
                    }
                }
            } label: {
                Text(formatSpeed(speedStore.speed))
            }
        }
    }
    
    private func togglePlayPause() {
        guard let discovery else { return }
        controller.togglePlayback(for: discovery)
    }
    
    @ViewBuilder
    private func seekButton(direction: SeekDirection) -> some View {
        let seconds: TimeInterval = direction == .forward ? 5 : -5
        
        Button(action: { controller.seek(by: seconds) }) {
            Image(systemName: direction == .forward ? "goforward.5" : "gobackward.5")
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in startAcceleratedSeek(direction: direction) }
        )
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            if !pressing { stopAcceleratedSeek() }
        }, perform: {})
    }
    
    private func startAcceleratedSeek(direction: SeekDirection) {
        let seconds: TimeInterval = direction == .forward ? 5 : -5
        seekTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            controller.seek(by: seconds)
        }
    }
    
    private func stopAcceleratedSeek() {
        seekTimer?.invalidate()
        seekTimer = nil
    }
}

private enum SeekDirection {
    case forward
    case backward
}
```

---

## 3.4 AudioGuideRowView Rewrite

**File:** `WhatsThatPresentation/Features/AudioGuides/AudioGuideRowView.swift`

**Current state:** Expects `AudioGuide` struct.

**Rewrite to:** Accept `DiscoverySummary` + `AudioGuideRowState`.

```swift
struct AudioGuideRowView: View {
    let discovery: DiscoverySummary
    let state: AudioGuideRowState
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onPlayNext: () -> Void
    let onAddToEnd: () -> Void
    
    var body: some View {
        HStack {
            // Image from discovery.imagePath
            AsyncImage(url: imageURL)
            
            VStack(alignment: .leading) {
                Text(discovery.title)
                
                // Chip based on state
                statusChip
            }
            
            Spacer()
            
            // Progress indicator if state.progress > 0
            if let progress = state.progress, progress > 0 {
                ProgressView(value: progress)
            }
        }
        .onTapGesture(perform: onTap)
        .onLongPressGesture(perform: onLongPress)
        .swipeActions(edge: .trailing) {
            if !state.isQueued && !state.isPlaying {
                Button("Play Next", action: onPlayNext)
                Button("Add to End", action: onAddToEnd)
            }
        }
    }
    
    @ViewBuilder
    private var statusChip: some View {
        switch state.status {
        case .ready:
            EmptyView()  // No chip for ready
        case .generating:
            Text("Generating").font(.caption)
        case .failed:
            Text("Failed").font(.caption).foregroundColor(.red)
        case .empty:
            Text("No Audio").font(.caption).foregroundColor(.secondary)
        case .queued:
            Text("Queued").font(.caption)
        case .playing:
            Text("Playing").font(.caption).foregroundColor(.accentColor)
        }
    }
}
```

---

## Playback UX Integration
- Mini player must replace legacy voiceover mini globally (visible on all screens where legacy appears) and open Audio Guides page; back/close returns to prior screen.
- Global mini host:
  - **Decision**: Host the global mini player in `MainTabView` as a ZStack overlay above the TabView. This provides direct access to `selectedTab`, `activeOverlayTab`, and `activeOverlayPhase` for visibility control.
  - Replace `VoiceoverPersistentPlayerView`/`VoiceoverPlayerBar`/`VoiceoverPlayerHost` with a single Audio Guides mini player host that uses the shared `VoiceoverPlaybackController` and `AudioGuidesQueueStore`, and is overlaid above existing content.
  - The same mini instance is used everywhere it appears; there is no separate "page-local" mini. Audio Guides list mode reuses this same mini host and placement.
  - Visibility rules:
    - Visible on:
      - Discoveries grid (`selectedTab == .discoveries`).
      - Discovery Detail overlay.
      - Discovery streaming stage and post-discovery states (`activeOverlayPhase == .analyzing`).
      - Audio Guides page **in list mode** (`selectedTab == .audioGuides && mode == .list`).
    - Hidden on:
      - **Audio Guides hero mode** (`selectedTab == .audioGuides && mode == .hero`).
      - Camera flow (`activeOverlayPhase == .capturingInitial/Retake`).
      - Upload flow (`activeOverlayPhase == .selectingInitial/Retake`).
      - Confirm Image Selection (`activeOverlayPhase == .confirming`).
      - Settings sheet (slides over mini player, hiding it).
    - Hidden whenever playback is idle/failed with no current discovery.
  - **Tap behavior**: Tapping mini player switches to Audio Guides tab in hero mode (shows currently playing discovery).
  - **Exit animation**: Mini player slides down below screen edge (not fade).
- Scroll content padding:
  - Create `MiniPlayerPresenceStore` that exposes `height: CGFloat` and `isVisible: Bool` with computed `effectiveInset`.
  - Discoveries grid, Discovery Detail, creation overlay streaming/complete, and Audio Guides list all apply `.padding(.bottom, miniPlayerPresence.effectiveInset)`.
- Legacy removal:
  - Retire `VoiceoverPlayerInsetStore` and related safe-area inset plumbing.
  - Remove `.safeAreaInset(edge: .bottom)` modifier from Discoveries tab in `MainTabView`.
- Hero/mini sync: both views bound to shared controller state; mode switch doesn't interrupt playback.
- **List→Hero navigation**: Button at top (implemented) + pull-down gesture from top (needs implementation).
- **Hero→List navigation**: Tap either tab button at bottom ("Up Next" or "My Discoveries"). Implemented.
- **Tab swipe gesture**: Horizontal swipe between Up Next and My Discoveries tabs (MVP feature).
- Controls to add:
  - ±5s buttons (tap) mapped to `VoiceoverPlaybackController` seek-by-5s helpers.
  - Press-and-hold accelerated seek: while the user holds the ±5s buttons, repeatedly seek ±5 seconds every **0.1 seconds** until release.
  - Playback speed menu wired to `VoiceoverPlaybackController` playback rate, persisted via the new global playback-speed store.
  - Progress display for UI only (playback always starts from 0).
  - Discovery images used as lock screen artwork.
- Error surfacing: inline error + retry in mini/hero; dismissing mini while error visible stops playback and hides mini.

## My Discoveries (Data & UI)
- Drive list from the same My Discoveries dataset already used elsewhere in the app (1:1 with existing My Discoveries content and ordering), grouped by day for display; statuses mapped from `VoiceoverPlaybackController.normalizedAsset(for:)` (ready/processing/missing/failed) for each `discovery.id`.
- Chip rules: Ready/Generating/Failed/Empty plus `Queued` when in Up Next and `Playing` when active.
- **Row interactions**:
  - Single tap: plays in place without tab switch.
  - **Long-press**: opens hero view (replaces double-tap for accessibility).
- Queue actions:
  - Swipe/menu "Add to End" or "Play Next".
  - **If already queued**: swipe springs back, shows existing "Queued" tick.
  - **"Play Next" on queued item**: moves it to front of immediate queue.
- Absent state triggers credit modal using shared generation path.
  - **Zero credits**: modal shows "Get More Credits" CTA instead of proceeding.
- Failed state retry calls `requestVoiceover(for:)` on the shared controller.
- **Rate limiting**: Maximum 2 concurrent generation requests; additional requests queued locally.

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
        lastPlayed.removeValue(forKey: discoveryId)
        save()
    }
    
    // MARK: - Pruning (~1MB limit)
    
    private static let maxEntries = 500  // ~2KB per entry = ~1MB
    
    private func pruneIfNeeded() {
        guard positions.count > Self.maxEntries else { return }
        
        // Sort by lastPlayed date (oldest first) and remove oldest entries
        let sortedIds = lastPlayed.sorted { $0.value < $1.value }.map(\.key)
        let toRemove = sortedIds.prefix(positions.count - Self.maxEntries)
        
        for id in toRemove {
            positions.removeValue(forKey: id)
            lastPlayed.removeValue(forKey: id)
        }
    }
    
    private func load() { /* decode from UserDefaults */ }
    
    private func save() {
        pruneIfNeeded()
        /* encode to UserDefaults */
    }
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
    @Published private(set) var immediate: [Int64] = []      // Play Next (LIFO)
    @Published private(set) var deferred: [Int64] = []       // Add to End (FIFO)
    @Published private(set) var baseList: [Int64] = []       // ~20 items each side
    @Published private(set) var baseIndex: Int = 0
    @Published private(set) var history: [Int64] = []        // Max 50 items
    @Published private(set) var current: Int64?
    @Published var autoplayEnabled: Bool = false
    
    private var lastActivityAt: Date?
    private let staleThreshold: TimeInterval = 24 * 60 * 60  // 24h
    private let maxQueueSize = 100                            // immediate + deferred
    private let maxHistorySize = 50
    
    // MARK: - Query Methods
    
    public func isQueued(_ id: Int64) -> Bool {
        immediate.contains(id) || deferred.contains(id)
    }
    
    public func isPlaying(_ id: Int64) -> Bool {
        current == id
    }
    
    // MARK: - Queue Operations
    
    public func playNow(_ id: Int64, recentering baseSnapshot: [Int64]) {
        // Auto-clear if stale
        if isStale { clearAll() }
        
        if let currentId = current {
            history.insert(currentId, at: 0)
            trimHistory()
        }
        current = id
        // Keep ~20 items on each side of current
        baseList = trimBaseList(baseSnapshot, around: id)
        baseIndex = baseList.firstIndex(of: id) ?? 0
        lastActivityAt = Date()
        save()
    }
    
    /// LIFO: inserts at head. If already queued, moves to front.
    public func playNext(_ id: Int64) {
        guard current != id else { return }
        
        if immediate.contains(id) {
            immediate.removeAll { $0 == id }
            immediate.insert(id, at: 0)
        } else if deferred.contains(id) {
            deferred.removeAll { $0 == id }
            immediate.insert(id, at: 0)
        } else if immediate.count + deferred.count < maxQueueSize {
            immediate.insert(id, at: 0)
        }
        save()
    }
    
    /// FIFO: appends to end. Ignores if already queued.
    public func addToEnd(_ id: Int64) {
        guard !isQueued(id) && current != id else { return }
        guard immediate.count + deferred.count < maxQueueSize else { return }
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
        
        // Take from immediate first (LIFO), then deferred (FIFO), then base
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
    
    private func clearAll() {
        immediate.removeAll()
        deferred.removeAll()
        history.removeAll()
        current = nil
        baseList.removeAll()
        baseIndex = 0
    }
    
    private func trimHistory() {
        if history.count > maxHistorySize {
            history = Array(history.prefix(maxHistorySize))
        }
    }
    
    private func trimBaseList(_ list: [Int64], around id: Int64) -> [Int64] {
        guard let index = list.firstIndex(of: id) else { return list }
        let start = max(0, index - 20)
        let end = min(list.count, index + 21)
        return Array(list[start..<end])
    }
    
    // MARK: - Stale Session (auto-clear after 24h)
    
    public var isStale: Bool {
        guard let lastActivity = lastActivityAt else { return false }
        return Date().timeIntervalSince(lastActivity) > staleThreshold
    }
    
    // MARK: - Persistence
    private func save() { /* encode to UserDefaults */ }
    private func load() { /* decode from UserDefaults; call clearAll() if isStale */ }
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
        
        // Hide in Audio Guides hero mode
        if selectedTab == .audioGuides && audioGuidesMode == .hero {
            return false
        }
        
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
    // Every 0.1s, seek by 5s in direction
    acceleratedSeekTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
        controller.seek(by: direction == .forward ? 5 : -5)
    }
}
```

---

# Phase 4: Legacy Removal (Detailed)

## 4.1 Files to Delete

| File | Full Path | Reason |
|------|-----------|--------|
| `VoiceoverPersistentPlayerView.swift` | `WhatsThatPresentation/Shared/Voiceover/` | Replaced by `MiniPlayerView` |
| `VoiceoverPlayerBar.swift` | `WhatsThatPresentation/Shared/Voiceover/` | Replaced by `MiniPlayerView` |
| `VoiceoverPlayerHost.swift` | `WhatsThatPresentation/Shared/Voiceover/` | Replaced by ZStack overlay in `MainTabView` |
| `VoiceoverPlayerInsetStore.swift` | `WhatsThatPresentation/Shared/Voiceover/` | Replaced by `MiniPlayerPresenceStore` |
| `AudioGuidesModels.swift` | `WhatsThatPresentation/Features/AudioGuides/` | `AudioGuide` struct replaced by `DiscoverySummary` |

## 4.2 Removal Steps (In Order)

1. **Verify new mini player works** – Confirm `MiniPlayerView` and `MainTabView` overlay work correctly before removing old code.

2. **Remove MainTabView dependencies:**
   ```swift
   // DELETE these lines from MainTabView.swift:
   @StateObject private var playerInsetStore = VoiceoverPlayerInsetStore()
   // ...
   .environmentObject(playerInsetStore)
   // ...
   .safeAreaInset(edge: .bottom) {
       if shouldShowPlayerInset {
           VoiceoverPlayerHost(...)
       }
   }
   ```

3. **Find and update all references to `playerInsetStore`:**
   ```bash
   grep -r "playerInsetStore" --include="*.swift" .
   grep -r "VoiceoverPlayerInsetStore" --include="*.swift" .
   ```
   Replace with `MiniPlayerPresenceStore` via environment.

4. **Delete legacy files:**
   ```bash
   rm native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Shared/Voiceover/VoiceoverPersistentPlayerView.swift
   rm native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Shared/Voiceover/VoiceoverPlayerBar.swift
   rm native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Shared/Voiceover/VoiceoverPlayerHost.swift
   rm native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Shared/Voiceover/VoiceoverPlayerInsetStore.swift
   rm native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/AudioGuides/AudioGuidesModels.swift
   ```

5. **Build and fix any remaining references** – Xcode will flag any remaining uses of deleted types.

---

## Decisions Finalized
- **Clear history affordance**: Not for MVP. History auto-prunes at 50 items and auto-clears on 24h staleness.
- **Dependency injection**: Use `AudioServicesContainer` for cleaner separation and testability.

## Completed Implementation Design
- ✅ Drafted detailed Up Next queue behavior spec (LIFO/FIFO, 100-item limit, 50-item history).
- ✅ Defined persistence layer for queue/history/progress and speed/autoplay settings (three stores).
- ✅ Designed navigation contract for Discovery Detail ↔ Audio Guides (standard tab transitions).
- ✅ Defined data layer architecture for shared discovery data (DiscoveryStore actor).
- ✅ Defined mini player hosting location (MainTabView ZStack overlay).
- ✅ Documented cache policy (150MB LRU) and in-flight download tracking.
- ✅ Defined pre-computed row state model (AudioGuideRowState).
- ✅ Clarified voiceover fetching strategy (prefetch on Discoveries load).
- ✅ Designed `AudioServicesContainer` for dependency injection.
- ✅ Designed `NetworkMonitor` for connectivity detection and auto-retry on reconnect.
- ✅ Designed discovery deletion cleanup cascade (audio cache, progress, queue).
- ✅ Specified Up Next header controls (down arrow, clear queue, auto-play toggle).
- ✅ Defined generation queued state for rate limiting feedback.
- ✅ Added `VoiceoverProgressStore` pruning logic (~500 entries max).

---


## Implementation Order (Recommended)

### Week 1: Foundation
1. [ ] Create `AudioServicesContainer` and environment setup
2. [ ] Implement `VoiceoverProgressStore`, `VoiceoverPlaybackSpeedStore`
3. [ ] Add `inFlightDownloads` tracking and `remove(discoveryId:)` to `VoiceoverFileCache`
4. [ ] Add `seek(by:)`, `setRate(_:)`, and `configure()` to `VoiceoverPlaybackController`
5. [ ] Create `NetworkMonitor` for connectivity detection and auto-retry

### Week 2: Stores & ViewModel
6. [ ] Implement `DiscoveryStore` actor
7. [ ] Implement `MiniPlayerPresenceStore`
8. [ ] Implement `AudioGuidesQueueStore` (including `removeFromAllLists`)
9. [ ] Update `DiscoveryFeedViewModel` to use `DiscoveryStore`
10. [ ] Update `DiscoveryDeletionUseCase` with audio cleanup cascade

### Week 3: Audio Guides ViewModel & Rows
11. [ ] Rewrite `AudioGuidesViewModel` (remove mocks)
12. [ ] Implement `AudioGuideRowStateProvider`
13. [ ] Delete `AudioGuidesModels.swift`
14. [ ] Rewrite `AudioGuideRowView`

### Week 4: UI Components
15. [ ] Rewrite `MiniPlayerView`
16. [ ] Rewrite `HeroPlayerView` with accelerated seek
17. [ ] Rewrite `AudioGuidesPageView` (including Up Next header with Clear Queue button)
18. [ ] Modify `MainTabView` (global mini player, offline banner, remove legacy)

### Week 5: Polish & Cleanup
19. [ ] Implement pull-down gesture for List→Hero navigation
20. [ ] Implement horizontal swipe gesture for tabs
21. [ ] Wire up app root with `AudioServicesContainer`
22. [ ] Delete legacy voiceover UI files
23. [ ] Build, test, fix remaining issues

