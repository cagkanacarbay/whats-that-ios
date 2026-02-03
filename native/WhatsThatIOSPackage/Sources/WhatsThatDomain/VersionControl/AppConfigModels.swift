import Foundation

// MARK: - App Config Response (from get_app_config RPC)

public struct AppConfigResponse: Codable, Sendable, Equatable {
    public let maintenance: MaintenanceConfig
    public let tos: VersionInfo
    public let privacy: VersionInfo
    public let app: AppVersionInfo
    public let userStatus: UserComplianceStatus?

    public init(
        maintenance: MaintenanceConfig,
        tos: VersionInfo,
        privacy: VersionInfo,
        app: AppVersionInfo,
        userStatus: UserComplianceStatus?
    ) {
        self.maintenance = maintenance
        self.tos = tos
        self.privacy = privacy
        self.app = app
        self.userStatus = userStatus
    }

    enum CodingKeys: String, CodingKey {
        case maintenance, tos, privacy, app
        case userStatus = "user_status"
    }
}

public struct MaintenanceConfig: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let message: String?

    public init(enabled: Bool, message: String?) {
        self.enabled = enabled
        self.message = message
    }
}

public struct VersionInfo: Codable, Sendable, Equatable {
    public let version: String
    public let message: String?
    public let releasedAt: Date

    public init(version: String, message: String?, releasedAt: Date) {
        self.version = version
        self.message = message
        self.releasedAt = releasedAt
    }

    enum CodingKeys: String, CodingKey {
        case version, message
        case releasedAt = "released_at"
    }
}

public struct AppVersionInfo: Codable, Sendable, Equatable {
    public let version: String
    public let message: String?
    public let releasedAt: Date
    public let appUpdateType: UpdateType
    public let minSupportedVersion: String
    public let appStoreUrl: String
    public let lastForceVersion: String?
    public let lastForceMessage: String?

    public init(
        version: String,
        message: String?,
        releasedAt: Date,
        appUpdateType: UpdateType,
        minSupportedVersion: String,
        appStoreUrl: String,
        lastForceVersion: String?,
        lastForceMessage: String? = nil
    ) {
        self.version = version
        self.message = message
        self.releasedAt = releasedAt
        self.appUpdateType = appUpdateType
        self.minSupportedVersion = minSupportedVersion
        self.appStoreUrl = appStoreUrl
        self.lastForceVersion = lastForceVersion
        self.lastForceMessage = lastForceMessage
    }

    enum CodingKeys: String, CodingKey {
        case version, message
        case releasedAt = "released_at"
        case appUpdateType = "app_update_type"
        case minSupportedVersion = "min_supported_version"
        case appStoreUrl = "app_store_url"
        case lastForceVersion = "last_force_version"
        case lastForceMessage = "last_force_message"
    }
}

public enum UpdateType: String, Codable, Sendable {
    case soft
    case force
}

public struct UserComplianceStatus: Codable, Sendable, Equatable {
    public let needsTosAcceptance: Bool
    public let needsPrivacyAcceptance: Bool
    public let acceptedTosVersion: String?
    public let acceptedPrivacyVersion: String?

    public init(
        needsTosAcceptance: Bool,
        needsPrivacyAcceptance: Bool,
        acceptedTosVersion: String?,
        acceptedPrivacyVersion: String?
    ) {
        self.needsTosAcceptance = needsTosAcceptance
        self.needsPrivacyAcceptance = needsPrivacyAcceptance
        self.acceptedTosVersion = acceptedTosVersion
        self.acceptedPrivacyVersion = acceptedPrivacyVersion
    }

    enum CodingKeys: String, CodingKey {
        case needsTosAcceptance = "needs_tos_acceptance"
        case needsPrivacyAcceptance = "needs_privacy_acceptance"
        case acceptedTosVersion = "accepted_tos_version"
        case acceptedPrivacyVersion = "accepted_privacy_version"
    }
}

// MARK: - Accept Terms Response

public struct AcceptTermsResponse: Codable, Sendable {
    public let success: Bool
    public let acceptedTosVersion: String?
    public let acceptedPrivacyVersion: String?

    public init(success: Bool, acceptedTosVersion: String?, acceptedPrivacyVersion: String?) {
        self.success = success
        self.acceptedTosVersion = acceptedTosVersion
        self.acceptedPrivacyVersion = acceptedPrivacyVersion
    }

    enum CodingKeys: String, CodingKey {
        case success
        case acceptedTosVersion = "accepted_tos_version"
        case acceptedPrivacyVersion = "accepted_privacy_version"
    }
}

// MARK: - Local Cache Structures

public struct AppUpdateReminderState: Codable, Sendable, Equatable {
    public var softUpdateVersion: String?
    public var lastReminderDate: Date?
    public var reminderCount: Int
    public var forceGracePeriodStartDate: Date?
    public var forceGracePeriodDismissedDate: Date?

    public init(
        softUpdateVersion: String? = nil,
        lastReminderDate: Date? = nil,
        reminderCount: Int = 0,
        forceGracePeriodStartDate: Date? = nil,
        forceGracePeriodDismissedDate: Date? = nil
    ) {
        self.softUpdateVersion = softUpdateVersion
        self.lastReminderDate = lastReminderDate
        self.reminderCount = reminderCount
        self.forceGracePeriodStartDate = forceGracePeriodStartDate
        self.forceGracePeriodDismissedDate = forceGracePeriodDismissedDate
    }
}

public struct CachedMaintenanceState: Codable, Sendable {
    public let isEnabled: Bool
    public let message: String?
    public let cachedAt: Date

    public init(isEnabled: Bool, message: String?, cachedAt: Date = Date()) {
        self.isEnabled = isEnabled
        self.message = message
        self.cachedAt = cachedAt
    }

    public var isValid: Bool {
        Date().timeIntervalSince(cachedAt) < 10800 // 3 hours
    }
}

// MARK: - Blocking State

public enum ComplianceBlockingState: Equatable, Sendable {
    case maintenance(message: String?)
    case forceUpdateImmediate(targetVersion: String, appStoreUrl: String, message: String?)
    case forceUpdateExpired(targetVersion: String, appStoreUrl: String, message: String?)
    case legalAcceptance(
        needsTos: Bool,
        needsPrivacy: Bool,
        tosVersion: String?,
        privacyVersion: String?,
        tosMessage: String?,
        privacyMessage: String?
    )
}

public enum ComplianceNonBlockingState: Equatable, Sendable {
    case forceUpdateGrace(targetVersion: String, daysRemaining: Int, appStoreUrl: String, message: String?)
    case softUpdateReminder(targetVersion: String, appStoreUrl: String, message: String?)
}
