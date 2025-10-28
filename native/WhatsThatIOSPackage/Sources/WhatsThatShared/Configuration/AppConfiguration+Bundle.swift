import Foundation

public extension AppConfiguration {
    /// Loads configuration values from the provided bundle (defaults to `.main`).
    /// Triggers a `preconditionFailure` when required keys are missing so misconfigured
    /// environments surface immediately during development.
    static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
        guard
            let supabaseURLString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let supabaseURL = URL(string: supabaseURLString)
        else {
            preconditionFailure("Missing SUPABASE_URL in bundle. Check xcconfig environment configuration.")
        }

        guard
            let supabaseAnonKey = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            supabaseAnonKey.isEmpty == false
        else {
            preconditionFailure("Missing SUPABASE_ANON_KEY in bundle. Check xcconfig environment configuration.")
        }

        guard
            let googleClientID = bundle.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String,
            googleClientID.isEmpty == false
        else {
            preconditionFailure("Missing GOOGLE_CLIENT_ID in bundle. Provide a configured Google client ID.")
        }

        guard
            let googleReversedClientID = bundle.object(forInfoDictionaryKey: "GOOGLE_REVERSED_CLIENT_ID") as? String,
            googleReversedClientID.isEmpty == false
        else {
            preconditionFailure("Missing GOOGLE_REVERSED_CLIENT_ID in bundle. Configure URL types for Google Sign-In.")
        }

        let passwordResetRedirectURL: URL?
        if let redirectString = bundle.object(forInfoDictionaryKey: "SUPABASE_PASSWORD_RESET_REDIRECT_URL") as? String,
           redirectString.isEmpty == false,
           let redirectURL = URL(string: redirectString)
        {
            passwordResetRedirectURL = redirectURL
        } else {
            passwordResetRedirectURL = nil
        }

        return AppConfiguration(
            supabaseURL: supabaseURL,
            supabaseAnonKey: supabaseAnonKey,
            googleClientID: googleClientID,
            googleReversedClientID: googleReversedClientID,
            passwordResetRedirectURL: passwordResetRedirectURL
        )
    }
}
