import XCTest
@testable import WhatsThatPresentation

@MainActor
final class VoiceoverPlaybackSpeedStoreTests: XCTestCase {
    
    private func makeStore() -> VoiceoverPlaybackSpeedStore {
        let suiteName = "test.voiceover.speed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return VoiceoverPlaybackSpeedStore(defaults: defaults)
    }
    
    // MARK: - Initial State
    
    func testInitialSpeedIsDefault() {
        let store = makeStore()
        
        XCTAssertEqual(store.speed, 1.0)
    }
    
    // MARK: - Valid Speed Presets
    
    func testValidRatesContainsExpectedValues() {
        let expected: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        XCTAssertEqual(VoiceoverPlaybackSpeedStore.validRates, expected)
    }
    
    func testSetValidSpeed() {
        let store = makeStore()
        
        store.speed = 1.5
        
        XCTAssertEqual(store.speed, 1.5)
    }
    
    func testSetInvalidSpeedResetsToDefault() {
        let store = makeStore()
        
        store.speed = 1.5
        store.speed = 1.3 // Invalid
        
        XCTAssertEqual(store.speed, 1.0)
    }
    
    // MARK: - Cycle Speed
    
    func testCycleSpeedFromDefault() {
        let store = makeStore()
        
        store.cycleSpeed()
        
        XCTAssertEqual(store.speed, 1.25) // Next after 1.0
    }
    
    func testCycleSpeedWrapsAround() {
        let store = makeStore()
        
        store.speed = 2.0
        store.cycleSpeed()
        
        XCTAssertEqual(store.speed, 0.5) // Wraps to first
    }
    
    func testCycleSpeedFullLoop() {
        let store = makeStore()
        let startSpeed = store.speed
        
        for _ in 0..<VoiceoverPlaybackSpeedStore.validRates.count {
            store.cycleSpeed()
        }
        
        // Should be back to start after full cycle
        XCTAssertEqual(store.speed, startSpeed)
    }
    
    // MARK: - Display String
    
    func testDisplayStringForWholeNumber() {
        let store = makeStore()
        
        store.speed = 1.0
        XCTAssertEqual(store.displayString, "1x")
        
        store.speed = 2.0
        XCTAssertEqual(store.displayString, "2x")
    }
    
    func testDisplayStringForDecimal() {
        let store = makeStore()
        
        store.speed = 0.5
        XCTAssertEqual(store.displayString, "0.5x")
        
        store.speed = 0.75
        XCTAssertEqual(store.displayString, "0.75x")
        
        store.speed = 1.25
        XCTAssertEqual(store.displayString, "1.2x")
        
        store.speed = 1.5
        XCTAssertEqual(store.displayString, "1.5x")
    }
}
