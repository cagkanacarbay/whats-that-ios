import Foundation
import WhatsThatDomain

public actor UserDefaultsComplianceLocalStore: ComplianceLocalStore {
    // UserDefaults.standard is thread-safe per Apple documentation
    private nonisolated(unsafe) let userDefaults: UserDefaults = .standard
    private let appUpdateReminderKey = "com.whatsthat.app_update_reminder_state"
    private let maintenanceCacheKey = "com.whatsthat.cached_maintenance_state"

    // Encoder/decoder are Sendable, so nonisolated is sufficient
    private nonisolated let encoder: JSONEncoder
    private nonisolated let decoder: JSONDecoder

    public init() {
        // Configure encoder/decoder for date handling
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func loadAppUpdateReminderState() async -> AppUpdateReminderState {
        guard let data = userDefaults.data(forKey: appUpdateReminderKey),
              let state = try? decoder.decode(AppUpdateReminderState.self, from: data) else {
            return AppUpdateReminderState()
        }
        return state
    }

    public func saveAppUpdateReminderState(_ state: AppUpdateReminderState) async {
        guard let data = try? encoder.encode(state) else { return }
        userDefaults.set(data, forKey: appUpdateReminderKey)
    }

    public func loadCachedMaintenanceState() async -> CachedMaintenanceState? {
        guard let data = userDefaults.data(forKey: maintenanceCacheKey),
              let state = try? decoder.decode(CachedMaintenanceState.self, from: data) else {
            return nil
        }
        return state
    }

    public func cacheMaintenanceState(_ state: CachedMaintenanceState) async {
        guard let data = try? encoder.encode(state) else { return }
        userDefaults.set(data, forKey: maintenanceCacheKey)
    }

    public func clearAll() async {
        userDefaults.removeObject(forKey: appUpdateReminderKey)
        // Note: Don't clear maintenance cache on sign-out (system-wide, not user-specific)
    }
}
