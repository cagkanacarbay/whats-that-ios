import XCTest
@testable import WhatsThatDomain

final class ComplianceUseCaseTests: XCTestCase {

    private var mockRepository: MockAppConfigRepository!
    private var mockLocalStore: MockComplianceLocalStore!
    private var useCase: ComplianceUseCase!

    override func setUp() async throws {
        mockRepository = MockAppConfigRepository()
        mockLocalStore = MockComplianceLocalStore()
        useCase = ComplianceUseCase(repository: mockRepository, localStore: mockLocalStore)
    }

    // MARK: - Config Fetching & Caching Tests

    func testFetchConfigReturnsFreshConfigFromRepository() async throws {
        let expectedConfig = AppConfigTestBuilder.cleanConfig()
        await mockRepository.setFetchConfigResult(.success(expectedConfig))

        let config = try await useCase.fetchConfig()

        XCTAssertEqual(config, expectedConfig)
        let callCount = await mockRepository.fetchConfigCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testFetchConfigReturnsCachedConfigWithinStalenessThreshold() async throws {
        let expectedConfig = AppConfigTestBuilder.cleanConfig()
        await mockRepository.setFetchConfigResult(.success(expectedConfig))

        // First fetch
        _ = try await useCase.fetchConfig()

        // Second fetch should use cache
        _ = try await useCase.fetchConfig()

        let callCount = await mockRepository.fetchConfigCallCount
        XCTAssertEqual(callCount, 1, "Should only call repository once when cache is fresh")
    }

    func testFetchConfigFetchesFreshWhenCacheIsStale() async throws {
        let config1 = AppConfigTestBuilder.makeConfig(appVersion: "1.0.0")
        let config2 = AppConfigTestBuilder.makeConfig(appVersion: "1.1.0")

        await mockRepository.setFetchConfigResult(.success(config1))
        _ = try await useCase.fetchConfig()

        // We can't easily simulate time passing, but we can test forceFresh
        await mockRepository.setFetchConfigResult(.success(config2))
        let freshConfig = try await useCase.fetchConfig(forceFresh: true)

        XCTAssertEqual(freshConfig.app.version, "1.1.0")
        let callCount = await mockRepository.fetchConfigCallCount
        XCTAssertEqual(callCount, 2)
    }

    func testFetchConfigWithForceFreshBypassesCache() async throws {
        let expectedConfig = AppConfigTestBuilder.cleanConfig()
        await mockRepository.setFetchConfigResult(.success(expectedConfig))

        // First fetch
        _ = try await useCase.fetchConfig()

        // Force fresh should bypass cache
        _ = try await useCase.fetchConfig(forceFresh: true)

        let callCount = await mockRepository.fetchConfigCallCount
        XCTAssertEqual(callCount, 2)
    }

    func testFetchConfigCachesMaintenanceStateToLocalStore() async throws {
        let config = AppConfigTestBuilder.maintenanceConfig(message: "System update")
        await mockRepository.setFetchConfigResult(.success(config))

        _ = try await useCase.fetchConfig()

        let cachedState = await mockLocalStore.maintenanceState
        XCTAssertNotNil(cachedState)
        XCTAssertTrue(cachedState!.isEnabled)
        XCTAssertEqual(cachedState!.message, "System update")
    }

    func testIsConfigStaleReturnsTrueWhenNoCache() async {
        let isStale = await useCase.isConfigStale()
        XCTAssertTrue(isStale)
    }

    func testIsConfigStaleReturnsFalseAfterFetch() async throws {
        await mockRepository.setFetchConfigResult(.success(AppConfigTestBuilder.cleanConfig()))
        _ = try await useCase.fetchConfig()

        let isStale = await useCase.isConfigStale()
        XCTAssertFalse(isStale)
    }

    func testGetCachedConfigReturnsNilBeforeFetch() async {
        let cached = await useCase.getCachedConfig()
        XCTAssertNil(cached)
    }

    func testGetCachedConfigReturnsConfigAfterFetch() async throws {
        let expectedConfig = AppConfigTestBuilder.cleanConfig()
        await mockRepository.setFetchConfigResult(.success(expectedConfig))
        _ = try await useCase.fetchConfig()

        let cached = await useCase.getCachedConfig()
        XCTAssertEqual(cached, expectedConfig)
    }

    func testClearCacheRemovesCachedConfig() async throws {
        await mockRepository.setFetchConfigResult(.success(AppConfigTestBuilder.cleanConfig()))
        _ = try await useCase.fetchConfig()

        await useCase.clearCache()

        let cached = await useCase.getCachedConfig()
        XCTAssertNil(cached)
        let isStale = await useCase.isConfigStale()
        XCTAssertTrue(isStale)
    }

    // MARK: - Terms Acceptance Tests

    func testAcceptTermsCallsRepository() async throws {
        await mockRepository.setFetchConfigResult(.success(AppConfigTestBuilder.cleanConfig()))
        await mockRepository.setAcceptTermsResult(.success(
            AppConfigTestBuilder.makeAcceptTermsResponse(
                acceptedTosVersion: "2.0",
                acceptedPrivacyVersion: "2.0"
            )
        ))

        let response = try await useCase.acceptTerms(tosVersion: "2.0", privacyVersion: "2.0")

        XCTAssertTrue(response.success)
        let callCount = await mockRepository.acceptTermsCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testAcceptTermsRefreshesConfigAfterSuccess() async throws {
        await mockRepository.setFetchConfigResult(.success(AppConfigTestBuilder.cleanConfig()))
        await mockRepository.setAcceptTermsResult(.success(
            AppConfigTestBuilder.makeAcceptTermsResponse()
        ))

        _ = try await useCase.acceptTerms(tosVersion: "2.0", privacyVersion: nil)

        // Should have called fetchConfig to refresh after acceptance
        let fetchCount = await mockRepository.fetchConfigCallCount
        XCTAssertEqual(fetchCount, 1)
    }

    // MARK: - Blocking State Priority Tests

    // Priority 1: Maintenance

    func testMaintenanceEnabledReturnsMaintenanceBlockingState() async {
        let config = AppConfigTestBuilder.maintenanceConfig(message: "System maintenance")
        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        XCTAssertEqual(state, .maintenance(message: "System maintenance"))
    }

    func testMaintenanceDisabledDoesNotReturnMaintenanceState() async {
        let config = AppConfigTestBuilder.cleanConfig()
        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        if case .maintenance = state {
            XCTFail("Should not return maintenance state when disabled")
        }
    }

    // Priority 2: Force Update Immediate (Below Min Supported)

    func testBelowMinSupportedVersionReturnsForceUpdateImmediate() async {
        let config = AppConfigTestBuilder.forceUpdateImmediateConfig(
            minSupportedVersion: "2.0.0",
            message: "Critical update required"
        )

        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        if case .forceUpdateImmediate(let targetVersion, let url, let message) = state {
            XCTAssertEqual(targetVersion, "2.0.0")
            XCTAssertEqual(url, AppConfigTestBuilder.defaultAppStoreUrl)
            XCTAssertEqual(message, "Critical update required")
        } else {
            XCTFail("Expected forceUpdateImmediate, got \(String(describing: state))")
        }
    }

    func testAtMinSupportedVersionDoesNotReturnForceUpdateImmediate() async {
        let config = AppConfigTestBuilder.makeConfig(minSupportedVersion: "1.0.0")
        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        if case .forceUpdateImmediate = state {
            XCTFail("Should not return forceUpdateImmediate when at min version")
        }
    }

    func testAboveMinSupportedVersionDoesNotReturnForceUpdateImmediate() async {
        let config = AppConfigTestBuilder.makeConfig(minSupportedVersion: "1.0.0")
        let state = await useCase.determineBlockingState(config: config, userAppVersion: "2.0.0")

        if case .forceUpdateImmediate = state {
            XCTFail("Should not return forceUpdateImmediate when above min version")
        }
    }

    // Priority 3: Force Update Expired (Grace Period Exceeded)

    func testBelowLastForceVersionWithExpiredGraceReturnsForceUpdateExpired() async {
        let config = AppConfigTestBuilder.forceUpdateGraceConfig(
            lastForceVersion: "1.5.0",
            message: "Update now required"
        )

        // Set grace period that started 8 days ago (expired)
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        await mockLocalStore.setReminderState(AppUpdateReminderState(
            forceGracePeriodStartDate: eightDaysAgo
        ))

        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        if case .forceUpdateExpired(let targetVersion, let url, let message) = state {
            XCTAssertEqual(targetVersion, "1.5.0")
            XCTAssertEqual(url, AppConfigTestBuilder.defaultAppStoreUrl)
            XCTAssertEqual(message, "Update now required")
        } else {
            XCTFail("Expected forceUpdateExpired, got \(String(describing: state))")
        }
    }

    // Priority 4: Legal Acceptance

    func testNeedsTosAcceptanceReturnsLegalAcceptanceState() async {
        let config = AppConfigTestBuilder.legalAcceptanceConfig(
            needsTos: true,
            needsPrivacy: false,
            tosVersion: "2.0"
        )

        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        if case .legalAcceptance(let needsTos, let needsPrivacy, let tosVersion, _, _, _) = state {
            XCTAssertTrue(needsTos)
            XCTAssertFalse(needsPrivacy)
            XCTAssertEqual(tosVersion, "2.0")
        } else {
            XCTFail("Expected legalAcceptance, got \(String(describing: state))")
        }
    }

    func testNeedsPrivacyAcceptanceReturnsLegalAcceptanceState() async {
        let config = AppConfigTestBuilder.legalAcceptanceConfig(
            needsTos: false,
            needsPrivacy: true,
            privacyVersion: "2.0"
        )

        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        if case .legalAcceptance(let needsTos, let needsPrivacy, _, let privacyVersion, _, _) = state {
            XCTAssertFalse(needsTos)
            XCTAssertTrue(needsPrivacy)
            XCTAssertEqual(privacyVersion, "2.0")
        } else {
            XCTFail("Expected legalAcceptance, got \(String(describing: state))")
        }
    }

    func testNoBothAcceptancesDoesNotReturnLegalState() async {
        let config = AppConfigTestBuilder.makeConfig(
            needsTosAcceptance: false,
            needsPrivacyAcceptance: false
        )

        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        if case .legalAcceptance = state {
            XCTFail("Should not return legalAcceptance when nothing needs acceptance")
        }
    }

    func testNoUserStatusDoesNotReturnLegalState() async {
        let config = AppConfigTestBuilder.makeConfig(includeUserStatus: false)

        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        if case .legalAcceptance = state {
            XCTFail("Should not return legalAcceptance when no userStatus")
        }
    }

    // MARK: - Priority Override Tests

    func testMaintenanceWinsOverForceUpdateImmediate() async {
        let config = AppConfigTestBuilder.makeConfig(
            maintenanceEnabled: true,
            maintenanceMessage: "Down for maintenance",
            minSupportedVersion: "999.0.0" // Would trigger force update
        )

        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        XCTAssertEqual(state, .maintenance(message: "Down for maintenance"))
    }

    func testMaintenanceWinsOverLegalAcceptance() async {
        let config = AppConfigTestBuilder.makeConfig(
            maintenanceEnabled: true,
            needsTosAcceptance: true,
            needsPrivacyAcceptance: true
        )

        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        if case .maintenance = state {
            // Expected
        } else {
            XCTFail("Maintenance should win over legal acceptance")
        }
    }

    func testForceUpdateImmediateWinsOverLegalAcceptance() async {
        let config = AppConfigTestBuilder.makeConfig(
            minSupportedVersion: "2.0.0",
            needsTosAcceptance: true
        )

        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        if case .forceUpdateImmediate = state {
            // Expected
        } else {
            XCTFail("Force update immediate should win over legal acceptance")
        }
    }

    func testForceUpdateExpiredWinsOverLegalAcceptance() async {
        let config = AppConfigTestBuilder.makeConfig(
            lastForceVersion: "1.5.0",
            needsTosAcceptance: true
        )

        // Expired grace period
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        await mockLocalStore.setReminderState(AppUpdateReminderState(
            forceGracePeriodStartDate: eightDaysAgo
        ))

        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        if case .forceUpdateExpired = state {
            // Expected
        } else {
            XCTFail("Force update expired should win over legal acceptance")
        }
    }

    // MARK: - Grace Period Tests

    func testGracePeriodStartDateSetWhenFirstSeen() async {
        let config = AppConfigTestBuilder.forceUpdateGraceConfig(lastForceVersion: "1.5.0")

        // Start with no grace period set
        await mockLocalStore.setReminderState(AppUpdateReminderState())

        _ = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        let state = await mockLocalStore.reminderState
        XCTAssertNotNil(state.forceGracePeriodStartDate)
    }

    func testGracePeriodStartDateNotResetIfAlreadySet() async {
        let config = AppConfigTestBuilder.forceUpdateGraceConfig(lastForceVersion: "1.5.0")

        let originalDate = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        await mockLocalStore.setReminderState(AppUpdateReminderState(
            forceGracePeriodStartDate: originalDate
        ))

        _ = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        let state = await mockLocalStore.reminderState
        XCTAssertEqual(state.forceGracePeriodStartDate, originalDate)
    }

    func testGracePeriodJustOver7DaysExpired() async {
        let config = AppConfigTestBuilder.forceUpdateGraceConfig(lastForceVersion: "1.5.0")

        // Just over 7 days = 604801 seconds
        let justOverSevenDaysAgo = Date().addingTimeInterval(-604801)
        await mockLocalStore.setReminderState(AppUpdateReminderState(
            forceGracePeriodStartDate: justOverSevenDaysAgo
        ))

        let state = await useCase.determineBlockingState(config: config, userAppVersion: "1.0.0")

        if case .forceUpdateExpired = state {
            // Expected
        } else {
            XCTFail("Grace period should be expired just after 7 days")
        }
    }

    // MARK: - Non-Blocking State Tests

    func testSoftReminderShownOnDay1() async {
        let config = AppConfigTestBuilder.softUpdateConfig(currentVersion: "1.5.0")

        // No previous reminder state
        await mockLocalStore.setReminderState(AppUpdateReminderState())

        let state = await useCase.determineNonBlockingState(config: config, userAppVersion: "1.0.0")

        if case .softUpdateReminder(let targetVersion, _, _) = state {
            XCTAssertEqual(targetVersion, "1.5.0")
        } else {
            XCTFail("Expected softUpdateReminder, got \(String(describing: state))")
        }
    }

    func testSoftReminderNotShownBeforeDay3() async {
        let config = AppConfigTestBuilder.softUpdateConfig(currentVersion: "1.5.0")

        // First reminder was shown 1 day ago (needs 2 days gap for count 1)
        let oneDayAgo = Date().addingTimeInterval(-1 * 24 * 60 * 60)
        await mockLocalStore.setReminderState(AppUpdateReminderState(
            softUpdateVersion: "1.5.0",
            lastReminderDate: oneDayAgo,
            reminderCount: 1
        ))

        let state = await useCase.determineNonBlockingState(config: config, userAppVersion: "1.0.0")

        XCTAssertNil(state, "Should not show reminder before day 3")
    }

    func testSoftReminderShownOnDay3() async {
        let config = AppConfigTestBuilder.softUpdateConfig(currentVersion: "1.5.0")

        // First reminder was shown 2+ days ago
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        await mockLocalStore.setReminderState(AppUpdateReminderState(
            softUpdateVersion: "1.5.0",
            lastReminderDate: twoDaysAgo,
            reminderCount: 1
        ))

        let state = await useCase.determineNonBlockingState(config: config, userAppVersion: "1.0.0")

        if case .softUpdateReminder = state {
            // Expected
        } else {
            XCTFail("Should show reminder on day 3")
        }
    }

    func testSoftReminderShownOnDay7() async {
        let config = AppConfigTestBuilder.softUpdateConfig(currentVersion: "1.5.0")

        // Second reminder was shown 4+ days ago
        let fourDaysAgo = Date().addingTimeInterval(-4 * 24 * 60 * 60)
        await mockLocalStore.setReminderState(AppUpdateReminderState(
            softUpdateVersion: "1.5.0",
            lastReminderDate: fourDaysAgo,
            reminderCount: 2
        ))

        let state = await useCase.determineNonBlockingState(config: config, userAppVersion: "1.0.0")

        if case .softUpdateReminder = state {
            // Expected
        } else {
            XCTFail("Should show reminder on day 7")
        }
    }

    func testSoftReminderStopsAfter3Reminders() async {
        let config = AppConfigTestBuilder.softUpdateConfig(currentVersion: "1.5.0")

        // Already shown 3 reminders
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        await mockLocalStore.setReminderState(AppUpdateReminderState(
            softUpdateVersion: "1.5.0",
            lastReminderDate: tenDaysAgo,
            reminderCount: 3
        ))

        let state = await useCase.determineNonBlockingState(config: config, userAppVersion: "1.0.0")

        XCTAssertNil(state, "Should stop reminders after 3 times")
    }

    func testSoftReminderResetsForNewVersion() async {
        let config = AppConfigTestBuilder.softUpdateConfig(currentVersion: "1.6.0")

        // Previous tracking was for 1.5.0
        await mockLocalStore.setReminderState(AppUpdateReminderState(
            softUpdateVersion: "1.5.0",
            lastReminderDate: Date(),
            reminderCount: 3
        ))

        let state = await useCase.determineNonBlockingState(config: config, userAppVersion: "1.0.0")

        if case .softUpdateReminder(let targetVersion, _, _) = state {
            XCTAssertEqual(targetVersion, "1.6.0")
        } else {
            XCTFail("Should show reminder for new version")
        }
    }

    func testNoNonBlockingStateWhenAtCurrentVersion() async {
        let config = AppConfigTestBuilder.makeConfig(appVersion: "1.0.0", appUpdateType: .soft)

        let state = await useCase.determineNonBlockingState(config: config, userAppVersion: "1.0.0")

        XCTAssertNil(state, "Should not show any reminder when at current version")
    }

    // MARK: - Action Methods Tests

    func testMarkSoftReminderShownIncrementsCountAndSetsDate() async {
        await mockLocalStore.setReminderState(AppUpdateReminderState(reminderCount: 1))

        await useCase.markSoftReminderShown()

        let state = await mockLocalStore.reminderState
        XCTAssertEqual(state.reminderCount, 2)
        XCTAssertNotNil(state.lastReminderDate)
    }

    func testDismissForceGracePeriodReminderSetsDismissedDate() async {
        await mockLocalStore.setReminderState(AppUpdateReminderState())

        await useCase.dismissForceGracePeriodReminder()

        let state = await mockLocalStore.reminderState
        XCTAssertNotNil(state.forceGracePeriodDismissedDate)
    }

    func testClearForceGracePeriodIfUpdatedClearsWhenAtOrAboveForceVersion() async {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        await mockLocalStore.setReminderState(AppUpdateReminderState(
            forceGracePeriodStartDate: threeDaysAgo
        ))

        await useCase.clearForceGracePeriodIfUpdated(userVersion: "1.5.0", lastForceVersion: "1.5.0")

        let state = await mockLocalStore.reminderState
        XCTAssertNil(state.forceGracePeriodStartDate)
    }

    func testClearForceGracePeriodIfUpdatedDoesNotClearWhenBelowForceVersion() async {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        await mockLocalStore.setReminderState(AppUpdateReminderState(
            forceGracePeriodStartDate: threeDaysAgo
        ))

        await useCase.clearForceGracePeriodIfUpdated(userVersion: "1.0.0", lastForceVersion: "1.5.0")

        let state = await mockLocalStore.reminderState
        XCTAssertNotNil(state.forceGracePeriodStartDate)
    }

    func testClearForceGracePeriodIfUpdatedIgnoresNilLastForceVersion() async {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        await mockLocalStore.setReminderState(AppUpdateReminderState(
            forceGracePeriodStartDate: threeDaysAgo
        ))

        await useCase.clearForceGracePeriodIfUpdated(userVersion: "1.5.0", lastForceVersion: nil)

        let state = await mockLocalStore.reminderState
        XCTAssertNotNil(state.forceGracePeriodStartDate)
    }

    // MARK: - Offline Handling Tests

    func testGetMaintenanceStateForOfflineReturnsNilIfNoCache() async {
        await mockLocalStore.setMaintenanceState(nil)

        let state = await useCase.getMaintenanceStateForOffline()

        XCTAssertNil(state)
    }

    func testGetMaintenanceStateForOfflineReturnsNilIfCacheInvalid() async {
        // Cache from 4 hours ago (> 3 hours)
        let fourHoursAgo = Date().addingTimeInterval(-4 * 60 * 60)
        await mockLocalStore.setMaintenanceState(CachedMaintenanceState(
            isEnabled: true,
            message: "Maintenance",
            cachedAt: fourHoursAgo
        ))

        let state = await useCase.getMaintenanceStateForOffline()

        XCTAssertNil(state)
    }

    func testGetMaintenanceStateForOfflineReturnsNilIfMaintenanceDisabled() async {
        await mockLocalStore.setMaintenanceState(CachedMaintenanceState(
            isEnabled: false,
            message: nil,
            cachedAt: Date()
        ))

        let state = await useCase.getMaintenanceStateForOffline()

        XCTAssertNil(state)
    }

    func testGetMaintenanceStateForOfflineReturnsCachedStateIfValidAndEnabled() async {
        let validCache = CachedMaintenanceState(
            isEnabled: true,
            message: "System maintenance",
            cachedAt: Date()
        )
        await mockLocalStore.setMaintenanceState(validCache)

        let state = await useCase.getMaintenanceStateForOffline()

        XCTAssertNotNil(state)
        XCTAssertTrue(state!.isEnabled)
        XCTAssertEqual(state!.message, "System maintenance")
    }

    func testGetMaintenanceStateForOfflineReturnsValidCacheAt2Hours59Minutes() async {
        let almostThreeHoursAgo = Date().addingTimeInterval(-10799)
        await mockLocalStore.setMaintenanceState(CachedMaintenanceState(
            isEnabled: true,
            message: "Maintenance",
            cachedAt: almostThreeHoursAgo
        ))

        let state = await useCase.getMaintenanceStateForOffline()

        XCTAssertNotNil(state)
    }

    func testGetMaintenanceStateForOfflineReturnsNilAtExactly3Hours() async {
        let exactlyThreeHoursAgo = Date().addingTimeInterval(-10800)
        await mockLocalStore.setMaintenanceState(CachedMaintenanceState(
            isEnabled: true,
            message: "Maintenance",
            cachedAt: exactlyThreeHoursAgo
        ))

        let state = await useCase.getMaintenanceStateForOffline()

        XCTAssertNil(state)
    }
}
