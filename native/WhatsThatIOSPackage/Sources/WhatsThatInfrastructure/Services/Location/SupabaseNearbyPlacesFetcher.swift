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
        print("[Nearby] Requesting Edge nearby-places: lat=\(latitude), lon=\(longitude), radius=\(radius)")
        guard let supabaseURL = configuration.supabaseURL else {
            print("[Nearby] ERROR: Invalid configuration - no supabaseURL")
            throw NearbyPlacesFetcherError.invalidConfiguration
        }

        guard let accessToken = client.auth.currentSession?.accessToken else {
            print("[Nearby] ERROR: No access token - user not authenticated")
            throw NearbyPlacesFetcherError.unauthenticated
        }

        let requestURL = Self.functionsBaseURL(from: supabaseURL)
            .appendingPathComponent("nearby-places")

        // DEBUG: Log the full URL and token info
        print("[Nearby] Full URL: \(requestURL.absoluteString)")
        print("[Nearby] Token prefix: \(String(accessToken.prefix(20)))...")
        print("[Nearby] Supabase base URL: \(supabaseURL.absoluteString)")

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
            print("[Nearby] ERROR: Unexpected response type")
            throw NearbyPlacesFetcherError.unexpectedResponse
        }

        print("[Nearby] Response status: \(httpResponse.statusCode)")

        guard (200..<300).contains(httpResponse.statusCode) else {
            // Log error response body
            let errorBody = String(data: data, encoding: .utf8) ?? "Unable to decode"
            print("[Nearby] ERROR body: \(errorBody)")
            throw NearbyPlacesFetcherError.httpStatus(httpResponse.statusCode)
        }

        let edgeResponse = try JSONDecoder.nearbyPlacesDecoder.decode(
            NearbyPlacesEdgeResponse.self,
            from: data
        )
        let places = edgeResponse.places ?? []
        print("[Nearby] Result returned: places=\(places.count)")
        for (idx, place) in places.enumerated() {
            if let loc = place.location {
                print("[Nearby]  • Place[\(idx)]: lat=\(loc.latitude), lon=\(loc.longitude)")
            } else {
                print("[Nearby]  • Place[\(idx)]: no coordinates")
            }
        }
        return places
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
