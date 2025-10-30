import Foundation

public protocol NearbyPlacesFetching: Sendable {
    func fetchNearbyPlaces(
        latitude: Double,
        longitude: Double,
        radius: Double
    ) async throws -> [NearbyPlace]
}

public enum NearbyPlacesFetcherError: Error, LocalizedError {
    case unauthenticated
    case invalidConfiguration
    case unexpectedResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Authentication is required before fetching nearby places."
        case .invalidConfiguration:
            return "Supabase configuration is missing or invalid."
        case .unexpectedResponse:
            return "Nearby places response could not be parsed."
        case let .httpStatus(code):
            return "Nearby places request failed with status \(code)."
        }
    }
}
