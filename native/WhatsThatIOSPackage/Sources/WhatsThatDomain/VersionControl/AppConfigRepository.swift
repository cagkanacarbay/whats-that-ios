import Foundation

public protocol AppConfigRepository: Sendable {
    /// Fetches the current app configuration including version info and user compliance status
    func fetchConfig() async throws -> AppConfigResponse

    /// Records user acceptance of terms/privacy policy
    /// - Parameters:
    ///   - tosVersion: The ToS version being accepted (nil if not accepting ToS)
    ///   - privacyVersion: The Privacy Policy version being accepted (nil if not accepting privacy)
    /// - Returns: Response indicating success and versions accepted
    func acceptTerms(tosVersion: String?, privacyVersion: String?) async throws -> AcceptTermsResponse
}
