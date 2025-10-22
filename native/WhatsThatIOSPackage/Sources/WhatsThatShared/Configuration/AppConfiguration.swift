import Foundation

/// Top-level environment values required to configure the application.
public struct AppConfiguration: Sendable, Equatable {
    public let supabaseURL: URL?
    public let supabaseAnonKey: String
    public let googleClientID: String?
    public let googleReversedClientID: String?

    public init(
        supabaseURL: URL?,
        supabaseAnonKey: String,
        googleClientID: String?,
        googleReversedClientID: String?
    ) {
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.googleClientID = googleClientID
        self.googleReversedClientID = googleReversedClientID
    }
}

public extension AppConfiguration {
    /// Lightweight configuration used for previews and early bootstrap until secrets are injected.
    static let preview = AppConfiguration(
        supabaseURL: nil,
        supabaseAnonKey: "",
        googleClientID: nil,
        googleReversedClientID: nil
    )
}
