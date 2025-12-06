import XCTest
@testable import WhatsThatDomain
import WhatsThatData

final class DiscoveryStoreTests: XCTestCase {
    
    private func makeStore() async -> DiscoveryStore {
        let repository = StubDiscoveryRepository()
        return DiscoveryStore(repository: repository)
    }
    
    // MARK: - Initial State
    
    func testInitialStateIsEmpty() async {
        let store = await makeStore()
        
        let cached = await store.allCached()
        XCTAssertTrue(cached.isEmpty)
        
        let count = await store.cachedCount()
        XCTAssertEqual(count, 0)
    }
    
    // MARK: - Load More
    
    func testLoadMoreReturnsDiscoveries() async throws {
        let store = await makeStore()
        
        let discoveries = try await store.loadMore(limit: 3, before: nil)
        
        XCTAssertEqual(discoveries.count, 3)
    }
    
    func testLoadMoreCachesDiscoveries() async throws {
        let store = await makeStore()
        
        try await _ = store.loadMore(limit: 3, before: nil)
        
        let cached = await store.allCached()
        XCTAssertEqual(cached.count, 3)
    }
    
    func testLoadMoreWithCursorReturnsPreviousPage() async throws {
        let store = await makeStore()
        
        let firstPage = try await store.loadMore(limit: 2, before: nil)
        let cursor = firstPage.last?.id
        
        let secondPage = try await store.loadMore(limit: 2, before: cursor)
        
        // Second page should have different items
        let firstPageIds = Set(firstPage.map(\.id))
        let secondPageIds = Set(secondPage.map(\.id))
        XCTAssertTrue(firstPageIds.isDisjoint(with: secondPageIds))
    }
    
    // MARK: - Query Methods
    
    func testGetReturnsNilForUnknown() async throws {
        let store = await makeStore()
        
        let result = await store.get(id: 99999)
        
        XCTAssertNil(result)
    }
    
    func testGetReturnsCachedDiscovery() async throws {
        let store = await makeStore()
        
        let loaded = try await store.loadMore(limit: 2, before: nil)
        let expectedId = loaded.first!.id
        
        let result = await store.get(id: expectedId)
        
        XCTAssertEqual(result?.id, expectedId)
    }
    
    func testAllCachedIdsMatchesAllCached() async throws {
        let store = await makeStore()
        
        try await _ = store.loadMore(limit: 3, before: nil)
        
        let cached = await store.allCached()
        let cachedIds = await store.allCachedIds()
        
        XCTAssertEqual(cachedIds.count, cached.count)
        XCTAssertEqual(Set(cachedIds), Set(cached.map(\.id)))
    }
    
    // MARK: - Mutation Methods
    
    func testUpsertAddsNewDiscovery() async throws {
        let store = await makeStore()
        
        let newDiscovery = DiscoverySummary(
            id: 999,
            title: "New Discovery",
            highlight: "A new discovery",
            capturedAt: Date()
        )
        
        await store.upsert(newDiscovery)
        
        let result = await store.get(id: 999)
        XCTAssertEqual(result?.title, "New Discovery")
    }
    
    func testUpsertUpdatesExistingDiscovery() async throws {
        let store = await makeStore()
        
        try await _ = store.loadMore(limit: 2, before: nil)
        let cached = await store.allCached()
        let existing = cached.first!
        
        let updated = DiscoverySummary(
            id: existing.id,
            title: "Updated Title",
            highlight: existing.highlight,
            capturedAt: existing.capturedAt
        )
        
        await store.upsert(updated)
        
        let result = await store.get(id: existing.id)
        XCTAssertEqual(result?.title, "Updated Title")
    }
    
    func testRemoveDeletesFromCache() async throws {
        let store = await makeStore()
        
        let loaded = try await store.loadMore(limit: 2, before: nil)
        let idToRemove = loaded.first!.id
        
        await store.remove(id: idToRemove)
        
        let result = await store.get(id: idToRemove)
        XCTAssertNil(result)
        
        let count = await store.cachedCount()
        XCTAssertEqual(count, 1)
    }
    
    func testClearAllRemovesEverything() async throws {
        let store = await makeStore()
        
        try await _ = store.loadMore(limit: 3, before: nil)
        
        await store.clearAll()
        
        let count = await store.cachedCount()
        XCTAssertEqual(count, 0)
    }
    
    // MARK: - Batch Operations
    
    func testUpsertBatchAddsMultiple() async throws {
        let store = await makeStore()
        
        let discoveries = [
            DiscoverySummary(id: 100, title: "A", highlight: "A", capturedAt: Date()),
            DiscoverySummary(id: 101, title: "B", highlight: "B", capturedAt: Date().addingTimeInterval(-1)),
            DiscoverySummary(id: 102, title: "C", highlight: "C", capturedAt: Date().addingTimeInterval(-2))
        ]
        
        await store.upsertBatch(discoveries)
        
        let count = await store.cachedCount()
        XCTAssertEqual(count, 3)
    }
    
    // MARK: - Ordering
    
    func testAllCachedMaintainsRecencyOrder() async throws {
        let store = await makeStore()
        
        let oldDate = Date().addingTimeInterval(-1000)
        let newDate = Date()
        
        let discoveries = [
            DiscoverySummary(id: 100, title: "Old", highlight: "Old", capturedAt: oldDate),
            DiscoverySummary(id: 101, title: "New", highlight: "New", capturedAt: newDate)
        ]
        
        await store.upsertBatch(discoveries)
        
        let cached = await store.allCached()
        
        // Most recent first
        XCTAssertEqual(cached.first?.id, 101)
        XCTAssertEqual(cached.last?.id, 100)
    }
}
