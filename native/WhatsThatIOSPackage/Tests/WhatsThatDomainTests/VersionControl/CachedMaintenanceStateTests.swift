import XCTest
@testable import WhatsThatDomain

final class CachedMaintenanceStateTests: XCTestCase {

    // MARK: - isValid Property Tests (3-hour validity window = 10800 seconds)

    func testIsValidReturnsTrueWhenFresh() {
        let state = CachedMaintenanceState(
            isEnabled: true,
            message: "Maintenance",
            cachedAt: Date()
        )
        XCTAssertTrue(state.isValid)
    }

    func testIsValidReturnsTrueAt1Hour() {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let state = CachedMaintenanceState(
            isEnabled: true,
            message: "Maintenance",
            cachedAt: oneHourAgo
        )
        XCTAssertTrue(state.isValid)
    }

    func testIsValidReturnsTrueAt2Hours59Minutes() {
        // 10799 seconds = 2h 59m 59s (just under 3 hours)
        let almostThreeHoursAgo = Date().addingTimeInterval(-10799)
        let state = CachedMaintenanceState(
            isEnabled: true,
            message: "Maintenance",
            cachedAt: almostThreeHoursAgo
        )
        XCTAssertTrue(state.isValid)
    }

    func testIsValidReturnsFalseAtExactly3Hours() {
        // 10800 seconds = exactly 3 hours (boundary condition)
        let exactlyThreeHoursAgo = Date().addingTimeInterval(-10800)
        let state = CachedMaintenanceState(
            isEnabled: true,
            message: "Maintenance",
            cachedAt: exactlyThreeHoursAgo
        )
        XCTAssertFalse(state.isValid)
    }

    func testIsValidReturnsFalseJustOver3Hours() {
        // 10801 seconds = just over 3 hours
        let justOverThreeHoursAgo = Date().addingTimeInterval(-10801)
        let state = CachedMaintenanceState(
            isEnabled: true,
            message: "Maintenance",
            cachedAt: justOverThreeHoursAgo
        )
        XCTAssertFalse(state.isValid)
    }

    func testIsValidReturnsFalseWhenOld24Hours() {
        let twentyFourHoursAgo = Date().addingTimeInterval(-86400)
        let state = CachedMaintenanceState(
            isEnabled: true,
            message: "Maintenance",
            cachedAt: twentyFourHoursAgo
        )
        XCTAssertFalse(state.isValid)
    }

    // MARK: - Initialization Tests

    func testDefaultCachedAtIsNow() {
        let before = Date()
        let state = CachedMaintenanceState(isEnabled: true, message: "Test")
        let after = Date()

        XCTAssertGreaterThanOrEqual(state.cachedAt, before)
        XCTAssertLessThanOrEqual(state.cachedAt, after)
    }

    func testStatePreservesIsEnabled() {
        let enabledState = CachedMaintenanceState(isEnabled: true, message: nil)
        let disabledState = CachedMaintenanceState(isEnabled: false, message: nil)

        XCTAssertTrue(enabledState.isEnabled)
        XCTAssertFalse(disabledState.isEnabled)
    }

    func testStatePreservesMessage() {
        let stateWithMessage = CachedMaintenanceState(isEnabled: true, message: "Custom message")
        let stateWithoutMessage = CachedMaintenanceState(isEnabled: true, message: nil)

        XCTAssertEqual(stateWithMessage.message, "Custom message")
        XCTAssertNil(stateWithoutMessage.message)
    }
}
