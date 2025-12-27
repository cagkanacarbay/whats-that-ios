import Foundation
import OSLog
import WhatsThatShared

private let logger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "DiscoveryStore"
)

/// Shared actor cache for discoveries. Both Discoveries and Audio Guides pages
/// read from this store to avoid re-fetching and re-rendering.
public actor DiscoveryStore {
    private var cache: [Int64: DiscoverySummary] = [:]
    private var orderedIds: [Int64] = []
    private let repository: DiscoveryRepository
    
    // MARK: - Debug Flags
    
    /// Set to true to simulate missing discoveries after initial load (removes 1st and 3rd items).
    /// This helps test that refresh properly re-fetches missing items.
    /// CHANGE THIS TO FALSE WHEN DONE TESTING
    public static var debugRemoveItemsAfterInitialLoad: Bool = false
    private var hasAppliedDebugRemoval: Bool = false
    
    public init(repository: DiscoveryRepository) {
        self.repository = repository
    }
    
    // MARK: - Fetching
    
    /// Fetches more discoveries and caches them. Returns newly fetched items.
    public func loadMore(limit: Int, before cursor: Int64?) async throws -> [DiscoverySummary] {
        let page = try await repository.fetchDiscoveries(limit: limit, before: cursor)
        for item in page {
            if cache[item.id] == nil {
                orderedIds.append(item.id)
            }
            cache[item.id] = item
        }
        
        // Debug: remove 1st and 3rd items after initial load to test refresh
        if DiscoveryStore.debugRemoveItemsAfterInitialLoad && !hasAppliedDebugRemoval && cursor == nil {
            hasAppliedDebugRemoval = true
            applyDebugRemoval()
        }
        
        return page
    }
    
    /// Refreshes discoveries by fetching fresh data from the database and merging with cache.
    /// This properly detects any items missing from the cache and adds them.
    /// Returns newly added items (items that were in DB but missing from cache).
    public func refreshAndMerge(limit: Int) async throws -> [DiscoverySummary] {
        // Fetch the latest items from the database (no cursor = from the start)
        let freshItems = try await repository.fetchDiscoveries(limit: limit, before: nil)
        
        logger.info("refreshAndMerge: fetched \(freshItems.count) items from database")
        
        // Find items that are in freshItems but not in our cache
        var newlyAddedItems: [DiscoverySummary] = []
        
        for item in freshItems {
            if cache[item.id] == nil {
                // This item was missing from cache - add it
                logger.info("refreshAndMerge: found missing item id=\(item.id)")
                newlyAddedItems.append(item)
            }
            // Update cache regardless (data might have changed)
            cache[item.id] = item
        }
        
        // Add missing IDs to orderedIds
        for item in newlyAddedItems {
            if !orderedIds.contains(item.id) {
                orderedIds.append(item.id)
            }
        }
        
        // Re-sort by capturedAt descending to ensure correct order
        orderedIds.sort {
            (cache[$0]?.capturedAt ?? .distantPast) > (cache[$1]?.capturedAt ?? .distantPast)
        }
        
        logger.info("refreshAndMerge: added \(newlyAddedItems.count) missing items, total cached=\(self.cache.count)")
        
        return newlyAddedItems
    }
    
    /// Debug helper to remove 1st and 3rd items from cache to simulate missing items
    private func applyDebugRemoval() {
        guard orderedIds.count >= 3 else {
            logger.warning("applyDebugRemoval: not enough items to remove (count=\(self.orderedIds.count))")
            return
        }
        
        let firstId = orderedIds[0]
        let thirdId = orderedIds[2]
        
        logger.warning("DEBUG: Removing items 1st (id=\(firstId)) and 3rd (id=\(thirdId)) to simulate missing discoveries")
        
        cache.removeValue(forKey: firstId)
        cache.removeValue(forKey: thirdId)
        orderedIds.removeAll { $0 == firstId || $0 == thirdId }
    }
    
    // MARK: - Query
    
    /// Returns cached discovery by ID, nil if not cached.
    public func get(id: Int64) -> DiscoverySummary? {
        cache[id]
    }
    
    /// Returns all cached discoveries in recency order.
    public func allCached() -> [DiscoverySummary] {
        orderedIds.compactMap { cache[$0] }
    }
    
    /// Returns all cached discovery IDs in recency order.
    public func allCachedIds() -> [Int64] {
        orderedIds
    }
    
    /// Returns the count of cached discoveries.
    public func cachedCount() -> Int {
        cache.count
    }
    
    // MARK: - Mutation
    
    /// Upserts a discovery (e.g., after creation). Re-sorts by capturedAt descending.
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
    
    /// Clears all cached discoveries.
    public func clearAll() {
        cache.removeAll()
        orderedIds.removeAll()
    }
    
    /// Bulk upsert of discoveries (e.g., from initial load).
    public func upsertBatch(_ summaries: [DiscoverySummary]) {
        for summary in summaries {
            if cache[summary.id] == nil {
                orderedIds.append(summary.id)
            }
            cache[summary.id] = summary
        }
        
        // Re-sort by capturedAt descending
        orderedIds.sort {
            (cache[$0]?.capturedAt ?? .distantPast) > (cache[$1]?.capturedAt ?? .distantPast)
        }
    }
}

// MARK: - UserDataClearable

extension DiscoveryStore: UserDataClearable {
    public func clearUserData() async {
        clearAll()
    }
}
