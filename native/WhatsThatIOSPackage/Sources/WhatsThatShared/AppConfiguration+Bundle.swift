import Foundation

public extension AppConfiguration {
    /// Loads configuration values from the provided bundle (defaults to `.main`).
    /// Falls back to `.preview` when the required entries are missing or malformed.
    static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
        let supabaseURLString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let supabaseURL = supabaseURLString.flatMap { URL(string: $0) }

        let supabaseAnonKey = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
        let googleClientID = bundle.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String
        let googleReversedClientID = bundle.object(forInfoDictionaryKey: "GOOGLE_REVERSED_CLIENT_ID") as? String

        guard let url = supabaseURL, supabaseAnonKey.isEmpty == false else {
            return .preview
        }

        return AppConfiguration(
            supabaseURL: url,
            supabaseAnonKey: supabaseAnonKey,
            googleClientID: googleClientID,
            googleReversedClientID: googleReversedClientID
        )
    }
}
