import XCTest
@testable import WhatsThatDomain
import WhatsThatData

@MainActor
final class DiscoveryStoreObserverTests: XCTestCase {
    
    private func makeStore() -> DiscoveryStore {
        let repository = StubDiscoveryRepository()
        return DiscoveryStore(repository: repository)
    }
    
    func testLoadInitialIfNeededTransitionsToLoadedState() async throws {
        let store = makeStore()
        let observer = DiscoveryStoreObserver(store: store)

        await observer.loadInitialIfNeeded()

        XCTAssertEqual(observer.loadState, .loaded)
        XCTAssertFalse(observer.discoveries.isEmpty)
        XCTAssertEqual(observer.discoveries.first?.title, "Golden Gate Bridge")
    }

    func testUpsertUpdatesPublishedDiscoveries() async throws {
        let store = makeStore()
        let observer = DiscoveryStoreObserver(store: store)

        let newDiscovery = DiscoverySummary(
            id: 999,
            title: "New Discovery",
            highlight: "Hero highlight",
            capturedAt: Date()
        )

        await observer.upsert(newDiscovery)

        XCTAssertTrue(observer.discoveries.contains(where: { $0.id == 999 }))
        XCTAssertEqual(observer.discoveries.first?.id, 999) // Should be first as it's newest
    }

    func testRemoveUpdatesPublishedDiscoveries() async throws {
        let store = makeStore()
        let observer = DiscoveryStoreObserver(store: store)

        await observer.loadInitialIfNeeded()
        let firstId = try XCTUnwrap(observer.discoveries.first?.id)

        await observer.remove(id: firstId)

        XCTAssertFalse(observer.discoveries.contains(where: { $0.id == firstId }))
    }
    
    func testRefreshUpdatesDiscoveries() async throws {
        let store = makeStore()
        let observer = DiscoveryStoreObserver(store: store)
        
        await observer.loadInitialIfNeeded()
        let initialCount = observer.discoveries.count
        
        await observer.refresh()
        
        XCTAssertEqual(observer.discoveries.count, initialCount)
        XCTAssertFalse(observer.isRefreshing)
    }
}
