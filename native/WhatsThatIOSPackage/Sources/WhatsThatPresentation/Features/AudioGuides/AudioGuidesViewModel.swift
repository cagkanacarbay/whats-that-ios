import SwiftUI
import Combine
import WhatsThatDomain
import WhatsThatShared
import os

private let log = Logger(subsystem: "WhatsThat.AudioGuides", category: "AudioGuidesViewModel")

/// List type toggle for Audio Guides page
public enum AudioGuideListType: Equatable {
    case upNext
    case discover
}

/// ViewModel for Audio Guides page, using real stores instead of mock data
@MainActor
public final class AudioGuidesViewModel: ObservableObject {
    
    // MARK: - Published State (from stores)
    
    /// Currently selected list tab
    @Published public var selectedList: AudioGuideListType = .upNext {
        didSet {
            if selectedList != .upNext {
                historyLimit = 3
            }
        }
    }
    
    /// Whether to show discoveries without audio guides in My Discoveries
    @Published public var showWithoutAudioGuide: Bool = true
    
    /// Current limit for history display
    @Published public var historyLimit: Int = 3
    
    /// Show history sheet
    @Published public var showHistory: Bool = false
    
    /// Discovery being considered for creation alert
    @Published public var discoveryForAlert: DiscoverySummary?
    
    /// Whether to show the create audio alert
    @Published public var showCreateAlert: Bool = false
    
    /// ID of recently queued discovery (for toast/badge)
    @Published public var recentlyQueuedDiscoveryId: Int64?
    
    // MARK: - Playback State (republished for SwiftUI observation)
    
    /// The currently playing discovery - republished from VoiceoverPlaybackController
    @Published public private(set) var nowPlayingDiscovery: DiscoverySummary?
    
    /// Items from baseList after the current index (shown in Up Next when queues are empty)
    @Published public private(set) var nextBaseItems: [Int64] = []
    
    /// Version counter to trigger row re-renders when states change
    @Published public private(set) var rowStateVersion: Int = 0
    
    // MARK: - Loading State
    
    @Published public private(set) var isLoadingVoiceoverStatus: Bool = false
    @Published public private(set) var localIds: [Int64] = []
    @Published public private(set) var isLoadingMore: Bool = false
    @Published public private(set) var localDiscoveryCache: [Int64: DiscoverySummary] = [:]
    
    // MARK: - Private State
    
    private var cursor: Int64?
    private var hasMore: Bool = true
    private var didInitialPrefetch: Bool = false
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Dependencies
    
    private let discoveryStore: DiscoveryStore
    private let queueStore: AudioGuidesQueueStore
    private let progressStore: VoiceoverProgressStore
    private let speedStore: VoiceoverPlaybackSpeedStore
    private let voiceoverController: VoiceoverPlaybackController
    private let rowStateProvider: AudioGuideRowStateProvider
    
    // MARK: - Init
    
    public init(
        discoveryStore: DiscoveryStore,
        queueStore: AudioGuidesQueueStore,
        progressStore: VoiceoverProgressStore,
        speedStore: VoiceoverPlaybackSpeedStore,
        voiceoverController: VoiceoverPlaybackController
    ) {
        self.discoveryStore = discoveryStore
        self.queueStore = queueStore
        self.progressStore = progressStore
        self.speedStore = speedStore
        self.voiceoverController = voiceoverController
        self.rowStateProvider = AudioGuideRowStateProvider(
            voiceoverController: voiceoverController,
            queueStore: queueStore,
            progressStore: progressStore
        )
        
        setupBindings()
    }
    
    // MARK: - Computed Properties
    
    /// All discoveries for My Discoveries list, filtered if needed
    public var filteredDiscoveries: [DiscoverySummary] {
        let allDiscoveries = localIds.compactMap { id -> DiscoverySummary? in
            localDiscoveryCache[id]
        }
        
        if showWithoutAudioGuide {
            return allDiscoveries
        } else {
            return allDiscoveries.filter { discovery in
                let state = rowStateProvider.rowState(for: discovery.id)
                return state.voiceoverStatus.isPlayable
            }
        }
    }
    
    /// Grouped discoveries by date for My Discoveries display
    public func groupedDiscoveries(_ discoveries: [DiscoverySummary]) -> [(String, [DiscoverySummary])] {
        let groupedByDate = Dictionary(grouping: discoveries) { discovery -> Date in
            Calendar.current.startOfDay(for: discovery.capturedAt)
        }
        
        let sortedDates = groupedByDate.keys.sorted(by: >)
        
        return sortedDates.map { date in
            let title: String
            if Calendar.current.isDateInToday(date) {
                title = "Today"
            } else if Calendar.current.isDateInYesterday(date) {
                title = "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                title = formatter.string(from: date)
            }
            return (title, groupedByDate[date] ?? [])
        }
    }
    
    /// Current discovery being played (convenience accessor)
    public var currentDiscovery: DiscoverySummary? {
        nowPlayingDiscovery
    }
    
    /// Current playback position (0.0 to 1.0)
    public var progress: Double {
        guard let duration = voiceoverController.duration, duration > 0 else { return 0 }
        return voiceoverController.position / duration
    }
    
    /// Current playback position as time string
    public var currentTimeString: String {
        let seconds = voiceoverController.position
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    /// Duration string
    public var durationString: String {
        guard let duration = voiceoverController.duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    /// Whether currently playing
    public var isPlaying: Bool {
        if case .playing = voiceoverController.playbackState { return true }
        return false
    }
    
    /// Current playback speed
    public var playbackSpeed: Double {
        speedStore.speed
    }
    
    /// Whether autoplay is enabled
    public var autoplayEnabled: Bool {
        get { queueStore.autoplayEnabled }
        set { queueStore.autoplayEnabled = newValue }
    }
    
    /// Up Next queue: immediate + deferred queues (user-added items only)
    /// Note: nextBaseItems is shown separately in the UI as the fallback items
    public var upNextItems: [Int64] {
        queueStore.upNextQueue
    }
    
    /// Combined Up Next: queued items + base list fallback (for display purposes)
    public var allUpNextItems: [Int64] {
        let queued = queueStore.upNextQueue
        if queued.isEmpty {
            return nextBaseItems
        }
        // Deduplicate: exclude items from nextBaseItems that are already in queued
        let queuedSet = Set(queued)
        let filteredBaseItems = nextBaseItems.filter { !queuedSet.contains($0) }
        return queued + filteredBaseItems
    }
    
    // MARK: - History Items
    
    /// History items with current limit, filtered to only show items with audio guides
    /// History items with current limit, filtered to only show items with audio guides
    public var historyItems: [Int64] {
        let history = queueStore.history
        let candidates = Array(history.prefix(historyLimit))
        
        // Deduplicate while preserving order
        var seen = Set<Int64>()
        return candidates.filter { seen.insert($0).inserted }
    }
    
    /// Returns discovery IDs that have ready audio guides
    private var audioReadyIds: [Int64] {
        let assetStates = voiceoverController.assetStates
        return localIds.filter { id in
            guard let asset = assetStates[id] else { return false }
            return asset.status == .ready
        }
    }
    
    // MARK: - Lifecycle
    
    /// Called when the Audio Guides page appears
    public func onAppear() async {
        guard !didInitialPrefetch else { return }
        didInitialPrefetch = true
        
        // Load discoveries from shared store
        var cachedDiscoveries = await discoveryStore.allCached()
        
        // If cache is empty, load from network
        if cachedDiscoveries.isEmpty {
            do {
                cachedDiscoveries = try await discoveryStore.loadMore(limit: 20, before: nil)
                cursor = cachedDiscoveries.last?.id
                hasMore = cachedDiscoveries.count == 20
            } catch {
                // Silent failure - will show empty state
            }
        } else {
            // Cache exists - set cursor to last item for proper pagination
            cursor = cachedDiscoveries.last?.id
        }
        
        localIds = cachedDiscoveries.map(\.id)
        
        // Populate local cache for synchronous access
        for discovery in cachedDiscoveries {
            localDiscoveryCache[discovery.id] = discovery
        }
        
        // Validate queue state against current data (remove deleted discoveries)
        let validIds = Set(localIds)
        queueStore.validateBaseList(validIds: validIds)
        
        // Batch prefetch voiceover status for all known discoveries
        if !localIds.isEmpty {
            isLoadingVoiceoverStatus = true
            rowStateProvider.markChecking(localIds)
            await voiceoverController.prefetchAsync(for: localIds)
            rowStateProvider.clearChecking(localIds)
            isLoadingVoiceoverStatus = false
        }
    }
    
    /// Load more discoveries if needed (pagination)
    public func loadMoreIfNeeded(currentId: Int64?) async {
        guard hasMore, !isLoadingMore else { return }
        guard let currentId, let index = localIds.firstIndex(of: currentId) else { return }
        
        // Trigger load when near end (4 items from end)
        let threshold = max(0, localIds.count - 4)
        guard index >= threshold else { return }
        
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        do {
            let newItems = try await discoveryStore.loadMore(limit: 10, before: cursor)
            let newIds = newItems.map(\.id)
            
            // Append to local list
            let existingSet = Set(localIds)
            let filtered = newIds.filter { !existingSet.contains($0) }
            localIds.append(contentsOf: filtered)
            
            // Populate cache for new items
            for item in newItems where filtered.contains(item.id) {
                localDiscoveryCache[item.id] = item
            }
            
            // Update cursor
            cursor = newItems.last?.id
            hasMore = newItems.count == 10
            
            // Batch prefetch voiceover status for new items
            if !filtered.isEmpty {
                rowStateProvider.markChecking(filtered)
                await voiceoverController.prefetchAsync(for: filtered)
                rowStateProvider.clearChecking(filtered)
            }
        } catch {
            // Silent failure - user just sees end of list
        }
    }
    
    // MARK: - Playback Actions
    
    public func togglePlayPause() {
        guard let discovery = currentDiscovery else {
            log.debug("[togglePlayPause] No currentDiscovery, skipping")
            return
        }
        log.debug("[togglePlayPause] Toggling for discovery id=\(discovery.id), title='\(discovery.title)'")
        voiceoverController.togglePlayback(for: discovery)
    }
    
    public func play(discovery: DiscoverySummary) {
        log.debug("[play] Called for discovery id=\(discovery.id), title='\(discovery.title)'")
        log.debug("[play] Image path: \(discovery.imagePath ?? "nil")")
        log.debug("[play] Queue before: current=\(self.queueStore.current ?? -1)")
        
        // Just call togglePlayback - it will handle queue setup via discoveryQueueProvider
        // This ensures consistent behavior whether playing from Audio Guides or Discovery Detail
        voiceoverController.togglePlayback(for: discovery)
        log.debug("[play] Called togglePlayback, controller.currentDiscovery=\(self.voiceoverController.currentDiscovery?.id ?? -1)")
    }
    
    public func playNext() {
        log.debug("[playNext] Called. Queue before: current=\(self.queueStore.current ?? -1)")
        
        if let nextId = queueStore.next() {
            log.debug("[playNext] Got nextId=\(nextId). Queue after: current=\(self.queueStore.current ?? -1)")
            // Try controller's queue provider first, then fall back to store
            if let discovery = voiceoverController.getDiscovery(id: nextId) {
                log.debug("[playNext] Found discovery from provider: '\(discovery.title)'")
                voiceoverController.togglePlayback(for: discovery)
            } else {
                Task {
                    if let discovery = await discoveryStore.get(id: nextId) {
                        log.debug("[playNext] Found discovery from store: '\(discovery.title)'")
                        voiceoverController.togglePlayback(for: discovery)
                    } else {
                        log.error("[playNext] Could not find discovery for id=\(nextId)")
                    }
                }
            }
        } else {
            log.debug("[playNext] No next item in queue")
        }
    }
    
    public func playPrevious() {
        let currentPosition = voiceoverController.position
        let currentId = queueStore.current
        log.debug("[playPrevious] Called. Position=\(currentPosition), current=\(currentId ?? -1)")
        
        if let prevId = queueStore.previous(currentPosition: currentPosition) {
            log.debug("[playPrevious] Got prevId=\(prevId). Queue after: current=\(self.queueStore.current ?? -1)")
            log.debug("[playPrevious] baseList.count=\(self.queueStore.baseList.count), baseIndex=\(self.queueStore.baseIndex)")
            log.debug("[playPrevious] history.count=\(self.queueStore.history.count)")
            
            // If previous() returns the same ID, it means "restart current"
            if prevId == currentId {
                log.debug("[playPrevious] Same ID - seeking to 0")
                voiceoverController.seek(to: 0) {}
            } else {
                // Try controller's queue provider first, then fall back to store
                if let discovery = voiceoverController.getDiscovery(id: prevId) {
                    log.debug("[playPrevious] Found discovery from provider: '\(discovery.title)'")
                    voiceoverController.togglePlayback(for: discovery)
                } else {
                    Task {
                        if let discovery = await discoveryStore.get(id: prevId) {
                            log.debug("[playPrevious] Found discovery from store: '\(discovery.title)'")
                            voiceoverController.togglePlayback(for: discovery)
                        } else {
                            log.error("[playPrevious] Could not find discovery for id=\(prevId)")
                        }
                    }
                }
            }
        } else {
            log.debug("[playPrevious] No previous item - previous() returned nil")
            log.debug("[playPrevious] State: baseList.count=\(self.queueStore.baseList.count), baseIndex=\(self.queueStore.baseIndex), history.count=\(self.queueStore.history.count)")
        }
    }
    
    // MARK: - Queue Actions
    
    public func addToQueue(_ discoveryId: Int64) {
        if !queueStore.isQueued(discoveryId) {
            queueStore.addToEnd(discoveryId)
            showQueueConfirmation(for: discoveryId)
        }
    }
    
    public func playNextInQueue(_ discoveryId: Int64) {
        queueStore.playNext(discoveryId)
        showQueueConfirmation(for: discoveryId)
    }
    
    public func removeFromQueue(_ discoveryId: Int64) {
        queueStore.remove(discoveryId)
    }
    
    public func clearQueue() {
        queueStore.clearQueue()
    }
    
    private func showQueueConfirmation(for id: Int64) {
        withAnimation {
            recentlyQueuedDiscoveryId = id
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            if self.recentlyQueuedDiscoveryId == id {
                withAnimation {
                    self.recentlyQueuedDiscoveryId = nil
                }
            }
        }
    }
    
    // MARK: - Seek Actions
    
    public func skipForward5() {
        voiceoverController.seek(by: 5)
    }
    
    public func skipBackward5() {
        voiceoverController.seek(by: -5)
    }
    
    public func seek(toFraction fraction: Double) {
        voiceoverController.seek(toFraction: fraction)
    }
    
    // MARK: - Speed Actions
    
    public func setPlaybackSpeed(_ speed: Double) {
        voiceoverController.setRate(speed)
    }
    
    public func cyclePlaybackSpeed() {
        voiceoverController.cycleRate()
    }
    
    // MARK: - Generation Actions
    
    public func requestCreation(for discovery: DiscoverySummary) {
        let state = rowStateProvider.rowState(for: discovery.id)
        
        switch state.voiceoverStatus {
        case .empty:
            // Show confirmation alert for new creation
            discoveryForAlert = discovery
            showCreateAlert = true
        case .failed:
            // Retry immediately
            voiceoverController.requestVoiceover(for: discovery)
        default:
            break
        }
    }
    
    public func confirmCreation() {
        log.debug("[confirmCreation] CALLED, discoveryForAlert=\(self.discoveryForAlert?.id ?? -1)")
        guard let discovery = discoveryForAlert else {
            log.error("[confirmCreation] discoveryForAlert is nil, aborting")
            return
        }
        log.debug("[confirmCreation] Calling voiceoverController.requestVoiceover for id=\(discovery.id)")
        voiceoverController.requestVoiceover(for: discovery)
        discoveryForAlert = nil
    }
    
    // MARK: - History
    
    public func loadMoreHistory() {
        historyLimit += 10
    }
    
    public func resetHistoryLimit() {
        historyLimit = 3
    }
    
    // MARK: - Row State
    
    public func rowState(for discoveryId: Int64) -> AudioGuideRowState {
        rowStateProvider.rowState(for: discoveryId)
    }
    
    // MARK: - Bindings
    
    private func setupBindings() {
        // Observe queue changes to invalidate row states
        queueStore.$current
            .sink { [weak self] _ in
                self?.rowStateProvider.invalidateAll()
                self?.rowStateVersion += 1
            }
            .store(in: &cancellables)
        
        queueStore.$immediate
            .sink { [weak self] _ in
                self?.rowStateProvider.invalidateAll()
                self?.rowStateVersion += 1
            }
            .store(in: &cancellables)
        
        queueStore.$deferred
            .sink { [weak self] _ in
                self?.rowStateProvider.invalidateAll()
                self?.rowStateVersion += 1
            }
            .store(in: &cancellables)
        
        // Observe voiceover state changes to invalidate row states AND insert newly-ready items
        voiceoverController.$assetStates
            .sink { [weak self] assetStates in
                guard let self else { return }
                self.rowStateProvider.invalidateAll()
                self.rowStateVersion += 1
                
                // Insert any newly-ready voiceovers into baseList
                self.insertNewlyReadyVoiceovers(assetStates: assetStates)
            }
            .store(in: &cancellables)
        
        // MARK: - Republish controller state for SwiftUI observation
        
        // Republish currentDiscovery from controller
        voiceoverController.$currentDiscovery
            .receive(on: DispatchQueue.main)
            .sink { [weak self] discovery in
                self?.nowPlayingDiscovery = discovery
            }
            .store(in: &cancellables)
        
        // Observe baseList, baseIndex, and assetStates to update nextBaseItems
        // "Next" goes towards newer items (lower indices), so show items BEFORE current index
        // Only include discoveries with ready audio guides
        Publishers.CombineLatest4(
            queueStore.$baseList,
            queueStore.$baseIndex,
            queueStore.$current,
            voiceoverController.$assetStates
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] baseList, baseIndex, _, assetStates in
            guard let self else { return }
            // Safety: ensure baseIndex is valid for the current baseList
            guard baseIndex > 0, baseIndex <= baseList.count else {
                self.nextBaseItems = []
                return
            }
            // Get items from 0 to baseIndex-1, but show them in order they'll be played (closest first)
            let candidateIds = Array(baseList[0..<baseIndex].reversed())
            // Filter to only include items with ready audio guides
            let readyItems = candidateIds.filter { id in
                guard let asset = assetStates[id] else { return false }
                return asset.status == .ready
            }
            // Limit to ~10 items for display
            self.nextBaseItems = Array(readyItems.prefix(10))
        }
        .store(in: &cancellables)
        
        // MARK: - BaseList Expansion
        
        // Observe when expansion is needed and fetch more discoveries
        queueStore.$needsExpansion
            .compactMap { $0 }
            .sink { [weak self] direction in
                Task {
                    await self?.handleExpansionNeeded(direction)
                }
            }
            .store(in: &cancellables)
        
        // MARK: - Discovery Store Updates
        
        // Subscribe to newly upserted discoveries (e.g., after creation)
        // This ensures My Discoveries list updates when a new discovery is created
        discoveryStore.discoveryUpserted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] discovery in
                guard let self else { return }
                
                // Add to local cache if not already present
                if !self.localIds.contains(discovery.id) {
                    self.localIds.insert(discovery.id, at: 0)
                }
                self.localDiscoveryCache[discovery.id] = discovery
                
                // Re-sort by capturedAt descending
                self.localIds.sort { id1, id2 in
                    let date1 = self.localDiscoveryCache[id1]?.capturedAt ?? .distantPast
                    let date2 = self.localDiscoveryCache[id2]?.capturedAt ?? .distantPast
                    return date1 > date2
                }
                
                log.debug("[discoveryUpserted] Added discovery id=\(discovery.id) to local cache")
            }
            .store(in: &cancellables)
    }
    
    // MARK: - BaseList Expansion Handling
    
    /// Fetches more discoveries when baseList needs expansion
    private func handleExpansionNeeded(_ direction: AudioGuidesQueueStore.ExpansionDirection) async {
        log.debug("[handleExpansionNeeded] direction=\(direction == .newer ? "newer" : "older")")
        
        // Safety: Can't expand if we don't have any local IDs
        guard !localIds.isEmpty else {
            log.debug("[handleExpansionNeeded] No localIds, skipping expansion")
            return
        }
        
        switch direction {
        case .newer:
            // Need more recent discoveries (lower indices)
            // For newer items, we'd need to fetch discoveries created AFTER the first item in baseList
            // This would typically happen when new discoveries are created during a session
            
            // Safety: Need a baseList with at least one item
            guard let firstBaseId = queueStore.baseList.first,
                  let firstBaseIndex = localIds.firstIndex(of: firstBaseId),
                  firstBaseIndex > 0 else {
                log.debug("[handleExpansionNeeded] Cannot expand newer: firstBaseIndex is 0 or not found")
                return
            }
            
            // Items before firstBaseIndex in localIds are newer
            let newerItems = Array(localIds[0..<firstBaseIndex].suffix(20))
            if !newerItems.isEmpty {
                // Filter to only audio-ready items
                let readyNewItems = newerItems.filter { id in
                    guard let asset = voiceoverController.assetStates[id] else { return false }
                    return asset.status == .ready
                }
                if !readyNewItems.isEmpty {
                    queueStore.expandBaseList(with: readyNewItems, direction: .newer)
                }
            }
            
        case .older:
            // Need older discoveries - might need to fetch from server
            if hasMore {
                do {
                    let newItems = try await discoveryStore.loadMore(limit: 20, before: cursor)
                    let newIds = newItems.map(\.id)
                    
                    // Update local tracking
                    let existingSet = Set(localIds)
                    let filtered = newIds.filter { !existingSet.contains($0) }
                    localIds.append(contentsOf: filtered)
                    
                    // Populate cache
                    for item in newItems where filtered.contains(item.id) {
                        localDiscoveryCache[item.id] = item
                    }
                    
                    cursor = newItems.last?.id
                    hasMore = newItems.count == 20
                    
                    // Prefetch voiceover status for new items
                    if !filtered.isEmpty {
                        await voiceoverController.prefetchAsync(for: filtered)
                        
                        // Now add the ready ones to baseList
                        let readyIds = filtered.filter { id in
                            guard let asset = voiceoverController.assetStates[id] else { return false }
                            return asset.status == .ready
                        }
                        queueStore.expandBaseList(with: readyIds, direction: .older)
                    }
                } catch {
                    log.error("[handleExpansionNeeded] Failed to load more: \(error)")
                }
            }
        }
    }
    
    /// Inserts newly-ready voiceovers into the baseList at their correct chronological position
    private func insertNewlyReadyVoiceovers(assetStates: [Int64: DiscoveryVoiceoverAsset]) {
        // Only process if we have at least one item in the base list
        guard !queueStore.baseList.isEmpty else { return }
        
        // Find IDs that are ready but not in baseList yet
        for (id, asset) in assetStates where asset.status == .ready {
            // Skip if already in baseList
            guard !queueStore.baseList.contains(id) else { continue }
            
            // Skip if not in our local discovery list
            guard localIds.contains(id) else { continue }
            
            // Insert at correct chronological position
            queueStore.insertVoiceoverReady(id) { [weak self] checkId -> Int? in
                self?.localIds.firstIndex(of: checkId)
            }
        }
    }
}
