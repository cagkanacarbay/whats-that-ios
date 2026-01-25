import Foundation

/// Protocol for local persistence of compliance-related state
public protocol ComplianceLocalStore: Sendable {
    /// Loads the app update reminder state (soft/force update tracking)
    func loadAppUpdateReminderState() async -> AppUpdateReminderState

    /// Saves the app update reminder state
    func saveAppUpdateReminderState(_ state: AppUpdateReminderState) async

    /// Loads cached maintenance state for offline resilience
    func loadCachedMaintenanceState() async -> CachedMaintenanceState?

    /// Caches maintenance state for offline use
    func cacheMaintenanceState(_ state: CachedMaintenanceState) async

    /// Clears all compliance-related local storage
    /// Note: Does NOT clear maintenance cache (system-wide, not user-specific)
    func clearAll() async
}
