import Foundation

/// Shared actor cache for discoveries. Both Discoveries and Audio Guides pages
/// read from this store to avoid re-fetching and re-rendering.
public actor DiscoveryStore {
    private var cache: [Int64: DiscoverySummary] = [:]
    private var orderedIds: [Int64] = []
    private let repository: DiscoveryRepository
    
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
        return page
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
