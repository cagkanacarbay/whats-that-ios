import Foundation

/// Use case for managing app compliance (version control, legal acceptance)
public actor ComplianceUseCase {
    private let repository: AppConfigRepository
    private let localStore: ComplianceLocalStore

    private var cachedConfig: AppConfigResponse?
    private var lastFetchTime: Date?
    private let stalenessThreshold: TimeInterval = 3600 // 1 hour

    public init(repository: AppConfigRepository, localStore: ComplianceLocalStore) {
        self.repository = repository
        self.localStore = localStore
    }

    // MARK: - Config Fetching

    /// Fetches app configuration, using cache if available and not stale
    /// - Parameter forceFresh: If true, bypasses cache and fetches from server
    /// - Returns: The app configuration
    public func fetchConfig(forceFresh: Bool = false) async throws -> AppConfigResponse {
        if !forceFresh, let cached = cachedConfig, let lastFetch = lastFetchTime {
            if Date().timeIntervalSince(lastFetch) < stalenessThreshold {
                return cached
            }
        }

        let config = try await repository.fetchConfig()
        cachedConfig = config
        lastFetchTime = Date()

        // Cache maintenance state for offline resilience
        await localStore.cacheMaintenanceState(
            CachedMaintenanceState(
                isEnabled: config.maintenance.enabled,
                message: config.maintenance.message
            )
        )

        return config
    }

    /// Returns true if the cached config is stale or doesn't exist
    public func isConfigStale() -> Bool {
        guard let lastFetch = lastFetchTime else { return true }
        return Date().timeIntervalSince(lastFetch) >= stalenessThreshold
    }

    /// Returns the cached config without fetching
    public func getCachedConfig() -> AppConfigResponse? {
        cachedConfig
    }

    /// Clears all cached state
    public func clearCache() {
        cachedConfig = nil
        lastFetchTime = nil
    }

    // MARK: - Terms Acceptance

    /// Records user acceptance of terms/privacy policy
    /// - Parameters:
    ///   - tosVersion: The ToS version being accepted (nil if not accepting ToS)
    ///   - privacyVersion: The Privacy Policy version being accepted (nil if not accepting privacy)
    /// - Returns: Response indicating success and versions accepted
    public func acceptTerms(tosVersion: String?, privacyVersion: String?) async throws -> AcceptTermsResponse {
        let response = try await repository.acceptTerms(tosVersion: tosVersion, privacyVersion: privacyVersion)

        // Refresh config to update user_status
        _ = try? await fetchConfig(forceFresh: true)

        return response
    }

    // MARK: - Blocking State Determination

    /// Determines if there's a blocking condition that prevents app usage
    /// - Parameters:
    ///   - config: The app configuration
    ///   - userAppVersion: The user's current app version
    /// - Returns: The blocking state if one exists, nil otherwise
    public func determineBlockingState(
        config: AppConfigResponse,
        userAppVersion: String
    ) async -> ComplianceBlockingState? {
        // Priority 1: Maintenance mode
        if config.maintenance.enabled {
            return .maintenance(message: config.maintenance.message)
        }

        // Priority 2: Below minimum supported version (immediate block)
        if userAppVersion.isVersionLessThan(config.app.minSupportedVersion) {
            return .forceUpdateImmediate(
                targetVersion: config.app.minSupportedVersion,
                appStoreUrl: config.app.appStoreUrl,
                message: config.app.message
            )
        }

        // Priority 3: Check last_force_version with grace period
        if let lastForceVersion = config.app.lastForceVersion,
           userAppVersion.isVersionLessThan(lastForceVersion) {
            var state = await localStore.loadAppUpdateReminderState()

            // Reset grace period if a NEW force version is released
            if state.forceUpdateVersion != lastForceVersion {
                state.forceGracePeriodStartDate = Date()
                state.forceGracePeriodDismissedDate = nil
                state.forceUpdateVersion = lastForceVersion
                await localStore.saveAppUpdateReminderState(state)
            }

            if isForceGracePeriodExpired(state: state) {
                return .forceUpdateExpired(
                    targetVersion: lastForceVersion,
                    appStoreUrl: config.app.appStoreUrl,
                    message: config.app.lastForceMessage ?? config.app.message
                )
            }
        }

        // Priority 4: Legal acceptance required
        if let userStatus = config.userStatus,
           (userStatus.needsTosAcceptance || userStatus.needsPrivacyAcceptance) {
            return .legalAcceptance(
                needsTos: userStatus.needsTosAcceptance,
                needsPrivacy: userStatus.needsPrivacyAcceptance,
                tosVersion: config.tos.version,
                privacyVersion: config.privacy.version,
                tosMessage: config.tos.message,
                privacyMessage: config.privacy.message
            )
        }

        return nil
    }

    // MARK: - Non-Blocking State Determination

    /// Determines if there's a non-blocking notification to show
    /// - Parameters:
    ///   - config: The app configuration
    ///   - userAppVersion: The user's current app version
    /// - Returns: The non-blocking state if one exists, nil otherwise
    public func determineNonBlockingState(
        config: AppConfigResponse,
        userAppVersion: String
    ) async -> ComplianceNonBlockingState? {
        // Force update within grace period (dismissible warning)
        if let lastForceVersion = config.app.lastForceVersion,
           userAppVersion.isVersionLessThan(lastForceVersion) {
            let state = await localStore.loadAppUpdateReminderState()
            let expired = isForceGracePeriodExpired(state: state)
            if !expired,
               let startDate = state.forceGracePeriodStartDate {
                // Check if user dismissed within last 24 hours
                // (The blocking check resets dismissedDate when a new version is detected)
                if let dismissedDate = state.forceGracePeriodDismissedDate,
                   Date().timeIntervalSince(dismissedDate) < 86400 {
                    // Don't show, dismissed recently
                } else {
                    let daysRemaining = max(0, 7 - Int(Date().timeIntervalSince(startDate) / 86400))
                    return .forceUpdateGrace(
                        targetVersion: config.app.version,
                        daysRemaining: daysRemaining,
                        appStoreUrl: config.app.appStoreUrl,
                        message: config.app.lastForceMessage ?? config.app.message
                    )
                }
            }
        }

        // Soft update reminder
        if config.app.appUpdateType == .soft,
           userAppVersion.isVersionLessThan(config.app.version) {
            var state = await localStore.loadAppUpdateReminderState()

            // Reset tracking for new version
            if state.softUpdateVersion != config.app.version {
                state.softUpdateVersion = config.app.version
                state.lastReminderDate = nil
                state.reminderCount = 0
                await localStore.saveAppUpdateReminderState(state)
            }

            if shouldShowSoftReminder(state: state) {
                return .softUpdateReminder(
                    targetVersion: config.app.version,
                    appStoreUrl: config.app.appStoreUrl,
                    message: config.app.message
                )
            }
        }

        return nil
    }

    /// Marks that a soft update reminder was shown to the user
    public func markSoftReminderShown() async {
        var state = await localStore.loadAppUpdateReminderState()
        state.lastReminderDate = Date()
        state.reminderCount += 1
        await localStore.saveAppUpdateReminderState(state)
    }

    /// Records that the user dismissed the force grace period reminder
    public func dismissForceGracePeriodReminder() async {
        var state = await localStore.loadAppUpdateReminderState()
        state.forceGracePeriodDismissedDate = Date()
        await localStore.saveAppUpdateReminderState(state)
    }

    /// Clears the force grace period when user updates their app
    public func clearForceGracePeriodIfUpdated(userVersion: String, lastForceVersion: String?) async {
        guard let forceVersion = lastForceVersion else { return }
        // If user is now at or above the last force version, clear the grace period
        if !userVersion.isVersionLessThan(forceVersion) {
            var state = await localStore.loadAppUpdateReminderState()
            state.forceGracePeriodStartDate = nil
            await localStore.saveAppUpdateReminderState(state)
        }
    }

    // MARK: - Offline Handling

    /// Gets cached maintenance state for offline scenarios
    /// - Returns: The cached maintenance state if valid and maintenance was enabled, nil otherwise
    public func getMaintenanceStateForOffline() async -> CachedMaintenanceState? {
        let cached = await localStore.loadCachedMaintenanceState()
        guard let cached, cached.isValid, cached.isEnabled else {
            return nil
        }
        return cached
    }

    // MARK: - Private Helpers

    private func isForceGracePeriodExpired(state: AppUpdateReminderState) -> Bool {
        guard let startDate = state.forceGracePeriodStartDate else {
            return false
        }
        let gracePeriodSeconds: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        return Date().timeIntervalSince(startDate) > gracePeriodSeconds
    }

    private func shouldShowSoftReminder(state: AppUpdateReminderState) -> Bool {
        // Stop after 3 reminders (day 1, 3, 7)
        guard state.reminderCount < 3 else { return false }

        // First reminder: always show
        guard let lastReminder = state.lastReminderDate else { return true }

        let daysSinceLastReminder = Int(Date().timeIntervalSince(lastReminder) / 86400)

        switch state.reminderCount {
        case 0: return true // Day 1 - should have been caught above
        case 1: return daysSinceLastReminder >= 2 // Day 3 (2 days after day 1)
        case 2: return daysSinceLastReminder >= 4 // Day 7 (4 days after day 3)
        default: return false
        }
    }
}
