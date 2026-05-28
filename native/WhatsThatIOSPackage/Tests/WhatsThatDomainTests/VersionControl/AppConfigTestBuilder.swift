import Foundation
@testable import WhatsThatDomain

/// Factory for creating test fixtures with sensible defaults
struct AppConfigTestBuilder {
    // MARK: - Default Values

    static let defaultAppStoreUrl = "https://apps.apple.com/app/whats-that/id123456789"
    static let defaultDate = Date(timeIntervalSince1970: 1700000000) // Fixed date for testing

    // MARK: - Full Config Builder

    static func makeConfig(
        maintenanceEnabled: Bool = false,
        maintenanceMessage: String? = nil,
        tosVersion: String = "1.0",
        tosMessage: String? = nil,
        privacyVersion: String = "1.0",
        privacyMessage: String? = nil,
        appVersion: String = "1.0.0",
        appMessage: String? = nil,
        appUpdateType: UpdateType = .soft,
        minSupportedVersion: String = "1.0.0",
        appStoreUrl: String = defaultAppStoreUrl,
        lastForceVersion: String? = nil,
        needsTosAcceptance: Bool = false,
        needsPrivacyAcceptance: Bool = false,
        acceptedTosVersion: String? = "1.0",
        acceptedPrivacyVersion: String? = "1.0",
        includeUserStatus: Bool = true
    ) -> AppConfigResponse {
        let maintenance = MaintenanceConfig(
            enabled: maintenanceEnabled,
            message: maintenanceMessage
        )

        let tos = VersionInfo(
            version: tosVersion,
            message: tosMessage,
            releasedAt: defaultDate
        )

        let privacy = VersionInfo(
            version: privacyVersion,
            message: privacyMessage,
            releasedAt: defaultDate
        )

        let app = AppVersionInfo(
            version: appVersion,
            message: appMessage,
            releasedAt: defaultDate,
            appUpdateType: appUpdateType,
            minSupportedVersion: minSupportedVersion,
            appStoreUrl: appStoreUrl,
            lastForceVersion: lastForceVersion
        )

        let userStatus: UserComplianceStatus? = includeUserStatus ? UserComplianceStatus(
            needsTosAcceptance: needsTosAcceptance,
            needsPrivacyAcceptance: needsPrivacyAcceptance,
            acceptedTosVersion: acceptedTosVersion,
            acceptedPrivacyVersion: acceptedPrivacyVersion
        ) : nil

        return AppConfigResponse(
            maintenance: maintenance,
            tos: tos,
            privacy: privacy,
            app: app,
            userStatus: userStatus
        )
    }

    // MARK: - Convenience Builders

    /// Config with maintenance enabled
    static func maintenanceConfig(message: String? = "System maintenance in progress") -> AppConfigResponse {
        makeConfig(maintenanceEnabled: true, maintenanceMessage: message)
    }

    /// Config that requires force update (below min supported version)
    static func forceUpdateImmediateConfig(
        minSupportedVersion: String = "2.0.0",
        message: String? = "Please update to continue"
    ) -> AppConfigResponse {
        makeConfig(
            appMessage: message,
            minSupportedVersion: minSupportedVersion
        )
    }

    /// Config with lastForceVersion set (for grace period testing)
    static func forceUpdateGraceConfig(
        lastForceVersion: String = "1.5.0",
        message: String? = "Update required soon"
    ) -> AppConfigResponse {
        makeConfig(
            appMessage: message,
            lastForceVersion: lastForceVersion
        )
    }

    /// Config that requires legal acceptance
    static func legalAcceptanceConfig(
        needsTos: Bool = true,
        needsPrivacy: Bool = true,
        tosVersion: String = "2.0",
        privacyVersion: String = "2.0"
    ) -> AppConfigResponse {
        makeConfig(
            tosVersion: tosVersion,
            privacyVersion: privacyVersion,
            needsTosAcceptance: needsTos,
            needsPrivacyAcceptance: needsPrivacy
        )
    }

    /// Config with soft update available
    static func softUpdateConfig(
        currentVersion: String = "1.5.0",
        message: String? = "A new version is available"
    ) -> AppConfigResponse {
        makeConfig(
            appVersion: currentVersion,
            appMessage: message,
            appUpdateType: .soft
        )
    }

    /// Clean config with no blocking states
    static func cleanConfig() -> AppConfigResponse {
        makeConfig()
    }

    // MARK: - Accept Terms Response Builder

    static func makeAcceptTermsResponse(
        success: Bool = true,
        acceptedTosVersion: String? = "1.0",
        acceptedPrivacyVersion: String? = "1.0"
    ) -> AcceptTermsResponse {
        AcceptTermsResponse(
            success: success,
            acceptedTosVersion: acceptedTosVersion,
            acceptedPrivacyVersion: acceptedPrivacyVersion
        )
    }
}
