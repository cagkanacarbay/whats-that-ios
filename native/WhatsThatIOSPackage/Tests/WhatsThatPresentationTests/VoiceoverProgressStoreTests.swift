import XCTest
@testable import WhatsThatPresentation

@MainActor
final class VoiceoverProgressStoreTests: XCTestCase {
    
    private func makeStore() -> VoiceoverProgressStore {
        let suiteName = "test.voiceover.progress.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return VoiceoverProgressStore(defaults: defaults)
    }
    
    // MARK: - Initial State
    
    func testInitialStateIsEmpty() {
        let store = makeStore()
        
        XCTAssertNil(store.position(for: 100))
        XCTAssertNil(store.lastPlayedDate(for: 100))
    }
    
    // MARK: - Update Position
    
    func testUpdatePositionStoresValue() {
        let store = makeStore()
        
        store.updatePosition(0.5, for: 100)
        
        XCTAssertEqual(store.position(for: 100), 0.5)
    }
    
    func testUpdatePositionSetsLastPlayedDate() {
        let store = makeStore()
        let beforeDate = Date()
        
        store.updatePosition(0.5, for: 100)
        
        let lastPlayed = store.lastPlayedDate(for: 100)
        XCTAssertNotNil(lastPlayed)
        XCTAssertGreaterThanOrEqual(lastPlayed!, beforeDate)
    }
    
    func testUpdatePositionOverwritesPreviousValue() {
        let store = makeStore()
        
        store.updatePosition(0.25, for: 100)
        store.updatePosition(0.75, for: 100)
        
        XCTAssertEqual(store.position(for: 100), 0.75)
    }
    
    // MARK: - Clear Position
    
    func testClearPositionRemovesEntry() {
        let store = makeStore()
        
        store.updatePosition(0.5, for: 100)
        XCTAssertNotNil(store.position(for: 100))
        
        store.clearPosition(for: 100)
        
        XCTAssertNil(store.position(for: 100))
        XCTAssertNil(store.lastPlayedDate(for: 100))
    }
    
    func testClearPositionDoesNotAffectOtherEntries() {
        let store = makeStore()
        
        store.updatePosition(0.5, for: 100)
        store.updatePosition(0.7, for: 101)
        
        store.clearPosition(for: 100)
        
        XCTAssertNil(store.position(for: 100))
        XCTAssertEqual(store.position(for: 101), 0.7)
    }
    
    // MARK: - Multiple Entries
    
    func testMultipleDiscoveriesTrackedIndependently() {
        let store = makeStore()
        
        store.updatePosition(0.1, for: 100)
        store.updatePosition(0.2, for: 101)
        store.updatePosition(0.3, for: 102)
        
        XCTAssertEqual(store.position(for: 100), 0.1)
        XCTAssertEqual(store.position(for: 101), 0.2)
        XCTAssertEqual(store.position(for: 102), 0.3)
    }
    
    // MARK: - Edge Cases
    
    func testPositionZero() {
        let store = makeStore()
        
        store.updatePosition(0.0, for: 100)
        
        XCTAssertEqual(store.position(for: 100), 0.0)
    }
    
    func testPositionOne() {
        let store = makeStore()
        
        store.updatePosition(1.0, for: 100)
        
        XCTAssertEqual(store.position(for: 100), 1.0)
    }
}
