import Foundation
import WhatsThatDomain

#if USE_REMOTE_DEPS && canImport(Supabase)
import Supabase

public final class SupabaseAppConfigRepository: AppConfigRepository, @unchecked Sendable {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func fetchConfig() async throws -> AppConfigResponse {
        do {
            // The SQL function returns a flat table row, which we decode and map to the nested structure
            // Use JSONObject + Supabase's decode() for proper date handling (same pattern as SupabaseDiscoveryRepository)
            let response: PostgrestResponse<[JSONObject]> = try await client.rpc("get_app_config").execute()
            let jsonArray: JSONArray = response.value.map { AnyJSON.object($0) }
            let rows: [AppConfigRow] = try jsonArray.decode(as: AppConfigRow.self)
            guard let row = rows.first else {
                throw AppConfigError.noData
            }
            return row.toAppConfigResponse()
        } catch {
            throw error
        }
    }

    enum AppConfigError: Error {
        case noData
    }

    /// Raw row structure matching the flat RETURNS TABLE from get_app_config()
    private struct AppConfigRow: Decodable {
        // Maintenance
        let maintenanceEnabled: Bool
        let maintenanceMessage: String?
        // ToS
        let tosVersion: String
        let tosMessage: String?
        let tosReleasedAt: Date
        // Privacy
        let privacyVersion: String
        let privacyMessage: String?
        let privacyReleasedAt: Date
        // App
        let appVersion: String
        let appMessage: String?
        let appReleasedAt: Date
        let appUpdateType: String
        let minSupportedVersion: String
        let appStoreUrl: String
        let lastForceVersion: String?
        let lastForceMessage: String?
        // User status
        let needsTosAcceptance: Bool?
        let needsPrivacyAcceptance: Bool?
        let acceptedTosVersion: String?
        let acceptedPrivacyVersion: String?

        enum CodingKeys: String, CodingKey {
            case maintenanceEnabled = "maintenance_enabled"
            case maintenanceMessage = "maintenance_message"
            case tosVersion = "tos_version"
            case tosMessage = "tos_message"
            case tosReleasedAt = "tos_released_at"
            case privacyVersion = "privacy_version"
            case privacyMessage = "privacy_message"
            case privacyReleasedAt = "privacy_released_at"
            case appVersion = "app_version"
            case appMessage = "app_message"
            case appReleasedAt = "app_released_at"
            case appUpdateType = "app_update_type"
            case minSupportedVersion = "min_supported_version"
            case appStoreUrl = "app_store_url"
            case lastForceVersion = "last_force_version"
            case lastForceMessage = "last_force_message"
            case needsTosAcceptance = "needs_tos_acceptance"
            case needsPrivacyAcceptance = "needs_privacy_acceptance"
            case acceptedTosVersion = "accepted_tos_version"
            case acceptedPrivacyVersion = "accepted_privacy_version"
        }

        func toAppConfigResponse() -> AppConfigResponse {
            let maintenance = MaintenanceConfig(
                enabled: maintenanceEnabled,
                message: maintenanceMessage
            )

            let tos = VersionInfo(
                version: tosVersion,
                message: tosMessage,
                releasedAt: tosReleasedAt
            )

            let privacy = VersionInfo(
                version: privacyVersion,
                message: privacyMessage,
                releasedAt: privacyReleasedAt
            )

            let updateType = UpdateType(rawValue: appUpdateType) ?? .soft
            let app = AppVersionInfo(
                version: appVersion,
                message: appMessage,
                releasedAt: appReleasedAt,
                appUpdateType: updateType,
                minSupportedVersion: minSupportedVersion,
                appStoreUrl: appStoreUrl,
                lastForceVersion: lastForceVersion,
                lastForceMessage: lastForceMessage
            )

            // User status is nil if not authenticated (all fields will be null)
            let userStatus: UserComplianceStatus?
            if let needsTos = needsTosAcceptance, let needsPrivacy = needsPrivacyAcceptance {
                userStatus = UserComplianceStatus(
                    needsTosAcceptance: needsTos,
                    needsPrivacyAcceptance: needsPrivacy,
                    acceptedTosVersion: acceptedTosVersion,
                    acceptedPrivacyVersion: acceptedPrivacyVersion
                )
            } else {
                userStatus = nil
            }

            return AppConfigResponse(
                maintenance: maintenance,
                tos: tos,
                privacy: privacy,
                app: app,
                userStatus: userStatus
            )
        }
    }

    public func acceptTerms(tosVersion: String?, privacyVersion: String?) async throws -> AcceptTermsResponse {
        struct Params: Encodable {
            let p_tos_version: String?
            let p_privacy_version: String?
        }

        print("[AcceptTerms] Calling RPC with p_tos_version=\(tosVersion ?? "nil"), p_privacy_version=\(privacyVersion ?? "nil")")

        do {
            let response: AcceptTermsResponse = try await client
                .rpc("accept_terms", params: Params(p_tos_version: tosVersion, p_privacy_version: privacyVersion))
                .execute()
                .value

            print("[AcceptTerms] Success: \(response)")
            return response
        } catch {
            print("[AcceptTerms] ERROR: \(error)")
            print("[AcceptTerms] Error type: \(type(of: error))")
            if let localizedError = error as? LocalizedError {
                print("[AcceptTerms] LocalizedDescription: \(localizedError.localizedDescription)")
                print("[AcceptTerms] FailureReason: \(localizedError.failureReason ?? "nil")")
            }
            throw error
        }
    }
}
#endif
