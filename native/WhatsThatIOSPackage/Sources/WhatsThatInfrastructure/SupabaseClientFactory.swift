#if USE_REMOTE_DEPS && canImport(Supabase)
import Foundation
import Supabase
import WhatsThatShared

public enum SupabaseClientFactoryError: LocalizedError {
    case missingURL
    case missingAnonKey

    public var errorDescription: String? {
        switch self {
        case .missingURL:
            return "Supabase configuration is missing the project URL."
        case .missingAnonKey:
            return "Supabase configuration is missing the anon key."
        }
    }
}

public struct SupabaseClientFactory {
    public static func makeClient(
        configuration: AppConfiguration,
        session: URLSession = .shared
    ) throws -> SupabaseClient {
        guard let supabaseURL = configuration.supabaseURL else {
            throw SupabaseClientFactoryError.missingURL
        }

        guard configuration.supabaseAnonKey.isEmpty == false else {
            throw SupabaseClientFactoryError.missingAnonKey
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let options = SupabaseClientOptions(
            db: .init(encoder: encoder, decoder: decoder),
            global: .init(session: session)
        )

        return SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: configuration.supabaseAnonKey,
            options: options
        )
    }
}
#endif
