#if USE_REMOTE_DEPS && canImport(Supabase)
import Foundation
import Supabase
import WhatsThatDomain
import WhatsThatShared

public final class SupabaseNearbyPlacesFetcher: NearbyPlacesFetching {
    private let client: SupabaseClient
    private let configuration: AppConfiguration
    private let urlSession: URLSession

    public init(
        client: SupabaseClient,
        configuration: AppConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.client = client
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func fetchNearbyPlaces(
        latitude: Double,
        longitude: Double,
        radius: Double
    ) async throws -> [NearbyPlace] {
        guard let supabaseURL = configuration.supabaseURL else {
            throw NearbyPlacesFetcherError.invalidConfiguration
        }

        guard let accessToken = client.auth.currentSession?.accessToken else {
            throw NearbyPlacesFetcherError.unauthenticated
        }

        let requestURL = Self.functionsBaseURL(from: supabaseURL)
            .appendingPathComponent("nearby-places")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "radius": radius
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NearbyPlacesFetcherError.unexpectedResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NearbyPlacesFetcherError.httpStatus(httpResponse.statusCode)
        }

        let edgeResponse = try JSONDecoder.nearbyPlacesDecoder.decode(
            NearbyPlacesEdgeResponse.self,
            from: data
        )
        return edgeResponse.places ?? []
    }

    private static func functionsBaseURL(from supabaseURL: URL) -> URL {
        var components = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false)
        components?.host = supabaseURL
            .host?
            .replacingOccurrences(of: ".supabase.co", with: ".functions.supabase.co")
        return components?.url ?? supabaseURL
    }
}

private struct NearbyPlacesEdgeResponse: Decodable {
    let places: [NearbyPlace]?
}

private extension JSONDecoder {
    static let nearbyPlacesDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
#endif
