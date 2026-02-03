import Foundation
@testable import WhatsThatDomain

/// Mock local store for testing ComplianceUseCase
actor MockComplianceLocalStore: ComplianceLocalStore {
    var reminderState = AppUpdateReminderState()
    var maintenanceState: CachedMaintenanceState?

    private(set) var saveReminderStateCallCount = 0
    private(set) var cacheMaintenanceCallCount = 0
    private(set) var clearAllCallCount = 0

    func loadAppUpdateReminderState() async -> AppUpdateReminderState {
        reminderState
    }

    func saveAppUpdateReminderState(_ state: AppUpdateReminderState) async {
        reminderState = state
        saveReminderStateCallCount += 1
    }

    func loadCachedMaintenanceState() async -> CachedMaintenanceState? {
        maintenanceState
    }

    func cacheMaintenanceState(_ state: CachedMaintenanceState) async {
        maintenanceState = state
        cacheMaintenanceCallCount += 1
    }

    func clearAll() async {
        reminderState = AppUpdateReminderState()
        clearAllCallCount += 1
    }

    func corruptForTesting() async {
        // No-op for mock
    }

    // MARK: - Test Helpers

    func setReminderState(_ state: AppUpdateReminderState) async {
        reminderState = state
    }

    func setMaintenanceState(_ state: CachedMaintenanceState?) async {
        maintenanceState = state
    }
}
