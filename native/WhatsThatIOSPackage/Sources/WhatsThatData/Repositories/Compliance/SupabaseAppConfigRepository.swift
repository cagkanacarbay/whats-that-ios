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
            let response: AppConfigResponse = try await client.rpc("get_app_config").execute().value
            print("[FetchConfig] Success - tos: \(response.tos.version), privacy: \(response.privacy.version)")
            print("[FetchConfig] UserStatus: \(String(describing: response.userStatus))")
            return response
        } catch {
            print("[FetchConfig] ERROR: \(error)")
            throw error
        }
    }

    public func acceptTerms(tosVersion: String?, privacyVersion: String?) async throws -> AcceptTermsResponse {
        struct Params: Encodable {
            let p_tos_version: String?
            let p_privacy_version: String?
        }

        print("[AcceptTerms] Calling RPC with tosVersion=\(tosVersion ?? "nil"), privacyVersion=\(privacyVersion ?? "nil")")

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
