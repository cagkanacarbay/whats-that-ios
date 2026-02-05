import Foundation

/// Service protocol for fetching sample discoveries used in pre-onboarding.
/// These discoveries demonstrate the app's capabilities before sign-up.
public protocol SampleDiscoveryService: Sendable {
    /// Fetches all sample discoveries from the server.
    /// - Returns: An array of `DiscoverySummary` objects ordered by display order.
    func fetchSampleDiscoveries() async throws -> [DiscoverySummary]

    /// Fetches voiceover assets for sample discoveries.
    /// - Parameter discoveryIds: The IDs of discoveries to fetch voiceovers for.
    /// - Returns: An array of `DiscoveryVoiceoverAsset` objects for available voiceovers.
    func fetchSampleVoiceovers(for discoveryIds: [Int64]) async throws -> [DiscoveryVoiceoverAsset]

    /// Refreshes a voiceover URL if it has expired or is about to expire.
    /// Call this when playback fails due to an expired URL.
    /// - Parameter discoveryId: The discovery ID to refresh the voiceover URL for
    /// - Returns: A fresh DiscoveryVoiceoverAsset if successful, nil otherwise
    func refreshVoiceoverURL(for discoveryId: Int64) async -> DiscoveryVoiceoverAsset?
}

public enum SampleDiscoveryError: LocalizedError, Equatable {
    case failedToLoad
    case noSamplesAvailable

    public var errorDescription: String? {
        switch self {
        case .failedToLoad:
            return "We couldn't load sample discoveries. Please check your connection."
        case .noSamplesAvailable:
            return "No sample discoveries are available at this time."
        }
    }
}
