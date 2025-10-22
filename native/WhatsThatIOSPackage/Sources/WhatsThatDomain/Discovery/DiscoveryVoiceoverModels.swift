import Foundation

public enum DiscoveryVoiceoverStatus: Equatable, Sendable {
    case available
    case missing
    case error
}

public struct DiscoveryVoiceoverAsset: Equatable, Sendable {
    public let discoveryId: Int64
    public let status: DiscoveryVoiceoverStatus
    public let audioURL: URL?
    public let modelIdentifier: String?
    public let fetchedAt: Date
    public let errorDescription: String?

    public init(
        discoveryId: Int64,
        status: DiscoveryVoiceoverStatus,
        audioURL: URL?,
        modelIdentifier: String? = nil,
        fetchedAt: Date = Date(),
        errorDescription: String? = nil
    ) {
        self.discoveryId = discoveryId
        self.status = status
        self.audioURL = audioURL
        self.modelIdentifier = modelIdentifier
        self.fetchedAt = fetchedAt
        self.errorDescription = errorDescription
    }
}

public struct DiscoveryVoiceoverRequestOptions: Equatable, Sendable {
    public var forceRefresh: Bool

    public init(forceRefresh: Bool = false) {
        self.forceRefresh = forceRefresh
    }
}

public protocol DiscoveryVoiceoverRepository: Sendable {
    func ensureVoiceoverAsset(
        for discoveryId: Int64,
        options: DiscoveryVoiceoverRequestOptions
    ) async -> DiscoveryVoiceoverAsset
}
