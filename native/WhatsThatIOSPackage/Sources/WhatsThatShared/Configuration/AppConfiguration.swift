import Foundation

/// Top-level environment values required to configure the application.
public struct AppConfiguration: Sendable, Equatable {
    public let supabaseURL: URL?
    public let supabaseAnonKey: String
    public let googleClientID: String?
    public let googleReversedClientID: String?
    public let passwordResetRedirectURL: URL?

    public init(
        supabaseURL: URL?,
        supabaseAnonKey: String,
        googleClientID: String?,
        googleReversedClientID: String?,
        passwordResetRedirectURL: URL? = nil
    ) {
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.googleClientID = googleClientID
        self.googleReversedClientID = googleReversedClientID
        self.passwordResetRedirectURL = passwordResetRedirectURL
    }
}

public extension AppConfiguration {
    /// Lightweight configuration used for previews and early bootstrap until secrets are injected.
    static let preview = AppConfiguration(
        supabaseURL: nil,
        supabaseAnonKey: "",
        googleClientID: nil,
        googleReversedClientID: nil,
        passwordResetRedirectURL: nil
    )

    // MARK: - Website & Legal URLs

    /// The app's website domain (single source of truth for all web URLs).
    static let websiteDomain = "whats-that.app"

    /// Base URL for the website.
    static var websiteBaseURL: URL {
        URL(string: "https://\(websiteDomain)")!
    }

    /// URL to the Terms and Conditions page.
    static var termsAndConditionsURL: URL {
        websiteBaseURL.appendingPathComponent("legal/terms-and-conditions")
    }

    /// URL to the Privacy Policy page.
    static var privacyPolicyURL: URL {
        websiteBaseURL.appendingPathComponent("legal/privacy-policy")
    }
}
