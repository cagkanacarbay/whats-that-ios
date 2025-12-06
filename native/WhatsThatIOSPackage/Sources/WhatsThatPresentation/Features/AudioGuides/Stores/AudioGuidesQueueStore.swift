import Foundation
import os

private let log = Logger(subsystem: "WhatsThat.AudioGuides", category: "AudioGuidesQueueStore")

/// Manages the Audio Guides queue, history, and autoplay state.
/// Queue model: Play Next = LIFO (most recent plays first), Add to End = FIFO (first added plays first).
/// Max 100 items across immediate + deferred queues, max 50 items in history.
///
/// Navigation model:
/// - baseList is ordered newest-first (index 0 = newest discovery)
/// - "Next" = newer items (lower indices), "Previous" = older items (higher indices)
/// - Skipped stack enables bidirectional navigation without losing your place
@MainActor
public final class AudioGuidesQueueStore: ObservableObject {
    private static let storeKey = "audio_guides_queue_store"
    
    // MARK: - Published State
    
    @Published private(set) var immediate: [Int64] = []      // Play Next queue (LIFO)
    @Published private(set) var deferred: [Int64] = []       // Add to End queue (FIFO)
    @Published public private(set) var baseList: [Int64] = []       // Navigation context (newest-first)
    @Published public private(set) var baseIndex: Int = 0
    @Published private(set) var history: [Int64] = []        // Max 50 items (most recent first)
    @Published private(set) var skipped: [Int64] = []        // Items passed when going Previous
    @Published private(set) var current: Int64?
    @Published public var autoplayEnabled: Bool = false {
        didSet { save() }
    }
    
    /// Signal when baseList expansion is needed
    public enum ExpansionDirection: Equatable {
        case newer
        case older
    }
    @Published public private(set) var needsExpansion: ExpansionDirection?
    
    // MARK: - Private State
    
    private var lastActivityAt: Date?
    private let staleThreshold: TimeInterval = 24 * 60 * 60  // 24 hours
    private let maxQueueSize = 100                            // immediate + deferred combined
    private let maxHistorySize = 50
    private let expansionThreshold = 5                        // Trigger expansion when within N items of edge
    
    private let defaults: UserDefaults
    
    // MARK: - Init
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        log.debug("[init] Loaded queue: current=\(self.current ?? -1), immediate=\(self.immediate.count), deferred=\(self.deferred.count), history=\(self.history.count)")
    }
    
    // MARK: - Query Methods
    
    /// Returns true if the discovery is in either queue (immediate or deferred)
    public func isQueued(_ id: Int64) -> Bool {
        immediate.contains(id) || deferred.contains(id)
    }
    
    /// Returns true if the discovery is currently playing
    public func isPlaying(_ id: Int64) -> Bool {
        current == id
    }
    
    /// Returns all items in the Up Next queue (immediate + deferred in order)
    public var upNextQueue: [Int64] {
        immediate + deferred
    }
    
    /// Returns the combined queue (queue + base fallback after current)
    public var effectiveQueue: [Int64] {
        var result = immediate + deferred
        if baseIndex + 1 < baseList.count {
            result += Array(baseList[(baseIndex + 1)...])
        }
        return result
    }
    
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
    
    // MARK: - Queue Operations
    
    /// Starts playing a discovery, updating base list and pushing current to history
    public func playNow(_ id: Int64, recentering baseSnapshot: [Int64]) {
        log.debug("[playNow] Called with id=\(id), baseSnapshot.count=\(baseSnapshot.count)")
        log.debug("[playNow] BEFORE: current=\(self.current ?? -1), history=\(Array(self.history.prefix(3)))")
        
        // Auto-clear if stale
        if isStale {
            log.debug("[playNow] Session is stale, clearing all")
            clearAll()
        }
        
        // Push current to history
        if let currentId = current {
            log.debug("[playNow] Pushing previous current=\(currentId) to history")
            history.insert(currentId, at: 0)
            trimHistory()
        }
        
        // Clear skipped stack (user made an explicit choice)
        skipped.removeAll()
        
        // Remove from queues if present
        immediate.removeAll { $0 == id }
        deferred.removeAll { $0 == id }
        
        current = id
        
        // Use the full baseSnapshot as context (no more 20-item trim)
        baseList = baseSnapshot
        baseIndex = baseList.firstIndex(of: id) ?? 0
        
        // Check if we need expansion
        checkForExpansion()
        
        log.debug("[playNow] AFTER: current=\(self.current ?? -1), baseList.count=\(self.baseList.count), baseIndex=\(self.baseIndex), history=\(Array(self.history.prefix(3)))")
        
        lastActivityAt = Date()
        save()
    }
    
    /// LIFO: inserts at head of immediate queue. If already queued, moves to front.
    public func playNext(_ id: Int64) {
        guard current != id else { return }
        
        if immediate.contains(id) {
            // Already in immediate, move to front
            immediate.removeAll { $0 == id }
            immediate.insert(id, at: 0)
        } else if deferred.contains(id) {
            // Move from deferred to front of immediate
            deferred.removeAll { $0 == id }
            immediate.insert(id, at: 0)
        } else if immediate.count + deferred.count < maxQueueSize {
            // Add to front of immediate
            immediate.insert(id, at: 0)
        }
        
        lastActivityAt = Date()
        save()
    }
    
    /// FIFO: appends to end of deferred queue. Ignores if already queued or playing.
    public func addToEnd(_ id: Int64) {
        guard !isQueued(id) && current != id else { return }
        guard immediate.count + deferred.count < maxQueueSize else { return }
        
        deferred.append(id)
        lastActivityAt = Date()
        save()
    }
    
    /// Advances to the next item. Returns the new current ID.
    /// Priority: skipped -> immediate (LIFO) -> deferred (FIFO) -> base fallback (towards newer items)
    /// Note: baseList is ordered newest-first (index 0 = newest), so "next" decrements baseIndex
    public func next() -> Int64? {
        log.debug("[next] Called. BEFORE: current=\(self.current ?? -1), skipped=\(self.skipped.count), immediate=\(self.immediate.count), deferred=\(self.deferred.count), baseIndex=\(self.baseIndex)/\(self.baseList.count)")
        
        lastActivityAt = Date()
        
        // Push current to history before moving
        if let currentId = current {
            log.debug("[next] Pushing current=\(currentId) to history")
            history.insert(currentId, at: 0)
            trimHistory()
        }
        
        // 1. First check skipped stack (return to where we were before pressing Previous)
        if !skipped.isEmpty {
            current = skipped.removeFirst()
            log.debug("[next] Took from skipped: \(self.current ?? -1)")
        }
        // 2. Then immediate queue (LIFO - remove from front)
        else if !immediate.isEmpty {
            current = immediate.removeFirst()
            log.debug("[next] Took from immediate: \(self.current ?? -1)")
        }
        // 3. Then deferred queue (FIFO - remove from front)
        else if !deferred.isEmpty {
            current = deferred.removeFirst()
            log.debug("[next] Took from deferred: \(self.current ?? -1)")
        }
        // 4. Then baseList - go towards newer items (lower index)
        else if baseIndex > 0 {
            baseIndex -= 1
            current = baseList[baseIndex]
            log.debug("[next] Took from baseList[\(self.baseIndex)]: \(self.current ?? -1)")
        }
        else {
            log.debug("[next] No more items available")
            current = nil
        }
        
        // Check if we need to expand baseList
        checkForExpansion()
        
        log.debug("[next] AFTER: current=\(self.current ?? -1), history=\(Array(self.history.prefix(3)))")
        save()
        return current
    }
    
    /// Goes to previous item. If position > restartThreshold, restarts current instead.
    /// Returns the ID to play (current for restart, or previous item from history/baseList).
    /// Note: baseList is ordered newest-first, so "previous" goes towards older (higher index)
    public func previous(currentPosition: TimeInterval, restartThreshold: TimeInterval = 3.0) -> Int64? {
        log.debug("[previous] Called. position=\(currentPosition), threshold=\(restartThreshold)")
        
        lastActivityAt = Date()
        
        // If past threshold, restart current (don't change anything)
        if currentPosition > restartThreshold {
            log.debug("[previous] Position > threshold, restarting current")
            save()
            return current
        }
        
        // Push current to skipped stack (so Next can return to it)
        if let currentId = current {
            log.debug("[previous] Pushing current=\(currentId) to skipped")
            skipped.insert(currentId, at: 0)
        }
        
        // Simply traverse baseList backwards (towards older items = higher index)
        // Note: We don't pop from history - history is display-only
        if baseIndex + 1 < baseList.count {
            baseIndex += 1
            current = baseList[baseIndex]
            log.debug("[previous] Traversed to baseList[\(self.baseIndex)]: \(self.current ?? -1)")
        }
        // No previous available - restore current from skipped
        else if !skipped.isEmpty {
            current = skipped.removeFirst()  // Undo the push we just did
            log.debug("[previous] No previous in baseList, restored from skipped: \(self.current ?? -1)")
        }
        
        // Check if we need to expand baseList
        checkForExpansion()
        
        save()
        return current
    }
    
    /// Removes an item from the queue (not from history or current)
    public func remove(_ id: Int64) {
        immediate.removeAll { $0 == id }
        deferred.removeAll { $0 == id }
        save()
    }
    
    /// Removes an item from all lists (queue, history, base, current, skipped)
    /// Used when a discovery is deleted.
    public func removeFromAllLists(_ id: Int64) {
        immediate.removeAll { $0 == id }
        deferred.removeAll { $0 == id }
        history.removeAll { $0 == id }
        skipped.removeAll { $0 == id }
        baseList.removeAll { $0 == id }
        if current == id {
            current = nil
        }
        // Recalculate baseIndex if needed
        if let currentId = current, let newIndex = baseList.firstIndex(of: currentId) {
            baseIndex = newIndex
        } else {
            baseIndex = max(0, min(baseIndex, baseList.count - 1))
        }
        save()
    }
    
    /// Clears the queue (immediate + deferred) but keeps baseList, history, and current intact.
    /// This is called by the "Clear Queue" button in Up Next.
    public func clearQueue() {
        immediate.removeAll()
        deferred.removeAll()
        // NOTE: Do NOT clear baseList, history, skipped, or current
        save()
    }
    
    // MARK: - Base List Management
    
    /// Expands baseList with new IDs. Called by ViewModel after fetching more.
    /// - Parameters:
    ///   - ids: New discovery IDs to add
    ///   - direction: Which end to add them to
    public func expandBaseList(with ids: [Int64], direction: ExpansionDirection) {
        guard !ids.isEmpty else {
            needsExpansion = nil
            return
        }
        
        // Filter out duplicates
        let existingSet = Set(baseList)
        let newIds = ids.filter { !existingSet.contains($0) }
        
        switch direction {
        case .newer:
            // Prepend to front (newer items have lower indices)
            baseList = newIds + baseList
            // Adjust baseIndex since we added items before current
            baseIndex += newIds.count
            log.debug("[expandBaseList] Added \(newIds.count) newer items, baseIndex now \(self.baseIndex)")
            
        case .older:
            // Append to end (older items have higher indices)
            baseList = baseList + newIds
            // baseIndex stays the same
            log.debug("[expandBaseList] Added \(newIds.count) older items")
        }
        
        needsExpansion = nil
        save()
    }
    
    /// Inserts a newly-ready voiceover into baseList at its correct chronological position.
    /// Works for both newer and older items relative to current.
    /// - Parameters:
    ///   - id: The discovery ID with newly-ready voiceover
    ///   - getChronologicalPosition: Returns the position of a discovery in the full ordered list (0 = newest)
    public func insertVoiceoverReady(
        _ id: Int64,
        getChronologicalPosition: (Int64) -> Int?
    ) {
        // Don't insert duplicates
        guard !baseList.contains(id) else { return }
        
        // Get position of the new item
        guard let newPosition = getChronologicalPosition(id) else { return }
        
        // Find correct insertion index in baseList
        var insertionIndex = baseList.count  // Default: end (oldest)
        
        for (index, existingId) in baseList.enumerated() {
            if let existingPosition = getChronologicalPosition(existingId),
               newPosition < existingPosition {
                // newPosition is newer (lower index = newer in our ordering)
                insertionIndex = index
                break
            }
        }
        
        baseList.insert(id, at: insertionIndex)
        
        // Adjust baseIndex if we inserted before or at current position
        if insertionIndex <= baseIndex {
            baseIndex += 1
        }
        
        log.debug("[insertVoiceoverReady] Inserted \(id) at index \(insertionIndex), baseIndex now \(self.baseIndex)")
        save()
    }
    
    /// Validates baseList against current available discoveries.
    /// Called after DiscoveryStore has loaded initial data on app launch.
    /// - Parameter validIds: Set of discovery IDs that currently exist
    public func validateBaseList(validIds: Set<Int64>) {
        let originalCount = baseList.count
        
        // Remove any IDs that no longer exist
        baseList = baseList.filter { validIds.contains($0) }
        immediate = immediate.filter { validIds.contains($0) }
        deferred = deferred.filter { validIds.contains($0) }
        history = history.filter { validIds.contains($0) }
        skipped = skipped.filter { validIds.contains($0) }
        
        // Validate current
        if let currentId = current, !validIds.contains(currentId) {
            current = nil
        }
        
        // Recalculate baseIndex
        if let currentId = current, let newIndex = baseList.firstIndex(of: currentId) {
            baseIndex = newIndex
        } else if !baseList.isEmpty {
            baseIndex = min(baseIndex, baseList.count - 1)
        } else {
            baseIndex = 0
        }
        
        if baseList.count != originalCount {
            log.debug("[validateBaseList] Removed \(originalCount - self.baseList.count) invalid items")
            save()
        }
    }
    
    // MARK: - Stale Session Detection (auto-clear after 24h inactivity)
    
    public var isStale: Bool {
        guard let lastActivity = lastActivityAt else { return false }
        return Date().timeIntervalSince(lastActivity) > staleThreshold
    }
    
    // MARK: - Private Helpers
    
    /// Clears all queues, history, skipped, baseList, and current state.
    /// Used for stale session or development reset.
    public func clearAll() {
        immediate.removeAll()
        deferred.removeAll()
        history.removeAll()
        skipped.removeAll()
        current = nil
        baseList.removeAll()
        baseIndex = 0
        lastActivityAt = nil
        needsExpansion = nil
        save()
    }
    
    private func trimHistory() {
        if history.count > maxHistorySize {
            history = Array(history.prefix(maxHistorySize))
        }
    }
    
    /// Checks if we're near the edge of baseList and need more items
    private func checkForExpansion() {
        // Items ahead in "next" direction (newer, lower indices)
        let itemsAheadNewer = baseIndex
        
        // Items behind in "previous" direction (older, higher indices)
        let itemsAheadOlder = baseList.count - 1 - baseIndex
        
        if itemsAheadNewer < expansionThreshold && itemsAheadNewer >= 0 && baseList.count > 0 {
            // Near the "newest" edge, need more recent items
            needsExpansion = .newer
            log.debug("[checkForExpansion] Near newer edge, requesting expansion")
        } else if itemsAheadOlder < expansionThreshold && itemsAheadOlder >= 0 && baseList.count > 0 {
            // Near the "oldest" edge, need older items
            needsExpansion = .older
            log.debug("[checkForExpansion] Near older edge, requesting expansion")
        } else {
            needsExpansion = nil
        }
    }
    
    // MARK: - Persistence
    
    private struct PersistedState: Codable {
        var immediate: [Int64]
        var deferred: [Int64]
        var baseList: [Int64]
        var baseIndex: Int
        var history: [Int64]
        var skipped: [Int64]
        var current: Int64?
        var autoplayEnabled: Bool
        var lastActivityAt: Date?
        
        // Memberwise initializer
        init(
            immediate: [Int64],
            deferred: [Int64],
            baseList: [Int64],
            baseIndex: Int,
            history: [Int64],
            skipped: [Int64],
            current: Int64?,
            autoplayEnabled: Bool,
            lastActivityAt: Date?
        ) {
            self.immediate = immediate
            self.deferred = deferred
            self.baseList = baseList
            self.baseIndex = baseIndex
            self.history = history
            self.skipped = skipped
            self.current = current
            self.autoplayEnabled = autoplayEnabled
            self.lastActivityAt = lastActivityAt
        }
        
        // Handle migration from old format without skipped
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            immediate = try container.decode([Int64].self, forKey: .immediate)
            deferred = try container.decode([Int64].self, forKey: .deferred)
            baseList = try container.decode([Int64].self, forKey: .baseList)
            baseIndex = try container.decode(Int.self, forKey: .baseIndex)
            history = try container.decode([Int64].self, forKey: .history)
            skipped = try container.decodeIfPresent([Int64].self, forKey: .skipped) ?? []
            current = try container.decodeIfPresent(Int64.self, forKey: .current)
            autoplayEnabled = try container.decode(Bool.self, forKey: .autoplayEnabled)
            lastActivityAt = try container.decodeIfPresent(Date.self, forKey: .lastActivityAt)
        }
    }
    
    private func save() {
        let state = PersistedState(
            immediate: immediate,
            deferred: deferred,
            baseList: baseList,
            baseIndex: baseIndex,
            history: history,
            skipped: skipped,
            current: current,
            autoplayEnabled: autoplayEnabled,
            lastActivityAt: lastActivityAt
        )
        
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.storeKey)
        }
    }
    
    private func load() {
        guard let data = defaults.data(forKey: Self.storeKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        
        // Check staleness before restoring
        if let lastActivity = state.lastActivityAt,
           Date().timeIntervalSince(lastActivity) > staleThreshold {
            // Session is stale, don't restore
            return
        }
        
        immediate = state.immediate
        deferred = state.deferred
        baseList = state.baseList
        baseIndex = state.baseIndex
        history = state.history
        skipped = state.skipped
        current = state.current
        autoplayEnabled = state.autoplayEnabled
        lastActivityAt = state.lastActivityAt
    }
}

