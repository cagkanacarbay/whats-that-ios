import XCTest
@testable import WhatsThatPresentation

@MainActor
final class MiniPlayerPresenceStoreTests: XCTestCase {
    
    // MARK: - Initial State
    
    func testInitialStateIsHidden() {
        let store = MiniPlayerPresenceStore()
        
        XCTAssertEqual(store.height, 0)
        XCTAssertFalse(store.isVisible)
        XCTAssertEqual(store.effectiveInset, 0)
    }
    
    // MARK: - Height Updates
    
    func testUpdateHeightSetsValue() {
        let store = MiniPlayerPresenceStore()
        
        store.update(height: 80)
        
        XCTAssertEqual(store.height, 80)
    }
    
    func testUpdateHeightClampsNegative() {
        let store = MiniPlayerPresenceStore()
        
        store.update(height: -10)
        
        XCTAssertEqual(store.height, 0)
    }
    
    func testUpdateHeightIgnoresSmallDifferences() {
        let store = MiniPlayerPresenceStore()
        
        store.update(height: 80)
        store.update(height: 80.3) // Difference < 0.5
        
        XCTAssertEqual(store.height, 80) // Should not update
    }
    
    func testUpdateHeightAppliesLargeDifferences() {
        let store = MiniPlayerPresenceStore()
        
        store.update(height: 80)
        store.update(height: 85) // Difference > 0.5
        
        XCTAssertEqual(store.height, 85)
    }
    
    func testUpdateHeightConvenienceMethod() {
        let store = MiniPlayerPresenceStore()
        
        store.updateHeight(90)
        
        XCTAssertEqual(store.height, 90)
    }
    
    // MARK: - Visibility
    
    func testSetVisibleTrue() {
        let store = MiniPlayerPresenceStore()
        
        store.setVisible(true)
        
        XCTAssertTrue(store.isVisible)
    }
    
    func testSetVisibleFalse() {
        let store = MiniPlayerPresenceStore()
        store.setVisible(true)
        
        store.setVisible(false)
        
        XCTAssertFalse(store.isVisible)
    }
    
    func testUpdateVisibilityConvenienceMethod() {
        let store = MiniPlayerPresenceStore()
        
        store.updateVisibility(true)
        
        XCTAssertTrue(store.isVisible)
    }
    
    // MARK: - Effective Inset
    
    func testEffectiveInsetWhenVisible() {
        let store = MiniPlayerPresenceStore()
        store.update(height: 80)
        store.setVisible(true)
        
        XCTAssertEqual(store.effectiveInset, 80)
    }
    
    func testEffectiveInsetWhenHidden() {
        let store = MiniPlayerPresenceStore()
        store.update(height: 80)
        store.setVisible(false)
        
        XCTAssertEqual(store.effectiveInset, 0)
    }
    
    func testEffectiveInsetUpdatesWithHeight() {
        let store = MiniPlayerPresenceStore()
        store.setVisible(true)
        
        store.update(height: 60)
        XCTAssertEqual(store.effectiveInset, 60)
        
        store.update(height: 100)
        XCTAssertEqual(store.effectiveInset, 100)
    }
}
