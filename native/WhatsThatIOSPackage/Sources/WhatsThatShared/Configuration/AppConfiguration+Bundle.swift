import Foundation

public extension AppConfiguration {
    /// Loads configuration values from the provided bundle (defaults to `.main`).
    /// Crashes with a clear message if required keys are missing/invalid.
    static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
        func value(for key: String) -> String? {
            (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let supabaseURLString = value(for: "SUPABASE_URL")
        let supabaseAnonKey = value(for: "SUPABASE_ANON_KEY")
        let googleClientID = value(for: "GOOGLE_CLIENT_ID")
        let googleReversedClientID = value(for: "GOOGLE_REVERSED_CLIENT_ID")
        let redirectString = value(for: "SUPABASE_PASSWORD_RESET_REDIRECT_URL")

        let missing: [String] = [
            supabaseURLString == nil || supabaseURLString?.isEmpty == true ? "SUPABASE_URL" : nil,
            supabaseAnonKey == nil || supabaseAnonKey?.isEmpty == true ? "SUPABASE_ANON_KEY" : nil,
            googleClientID == nil || googleClientID?.isEmpty == true ? "GOOGLE_CLIENT_ID" : nil,
            googleReversedClientID == nil || googleReversedClientID?.isEmpty == true ? "GOOGLE_REVERSED_CLIENT_ID" : nil
        ].compactMap { $0 }

        if !missing.isEmpty {
            preconditionFailure("Missing Info.plist keys: \(missing.joined(separator: ", ")). Ensure xcconfig/Info.plist is configured.")
        }

        guard let supabaseURLString, let supabaseURL = URL(string: supabaseURLString) else {
            preconditionFailure("Invalid SUPABASE_URL format. Ensure Info.plist contains a valid URL string.")
        }

        // DEBUG: Print the Supabase URL being used
        print("[AppConfiguration] SUPABASE_URL = \(supabaseURLString)")
        print("[AppConfiguration] Expected DEV = cywshvmspnvimucwqarc.supabase.co")

        let passwordResetRedirectURL: URL?
        if let redirectString, !redirectString.isEmpty, let redirectURL = URL(string: redirectString) {
            passwordResetRedirectURL = redirectURL
        } else {
            passwordResetRedirectURL = nil
        }

        return AppConfiguration(
            supabaseURL: supabaseURL,
            supabaseAnonKey: supabaseAnonKey ?? "",
            googleClientID: googleClientID,
            googleReversedClientID: googleReversedClientID,
            passwordResetRedirectURL: passwordResetRedirectURL
        )
    }
}
