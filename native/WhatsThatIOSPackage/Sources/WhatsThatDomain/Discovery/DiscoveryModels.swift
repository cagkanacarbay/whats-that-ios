import Foundation
import WhatsThatShared

public struct DiscoveryLocation: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let country: String?
    public let locality: String?
    public let streetName: String?
    public let closestPlace: String?

    public init(
        latitude: Double,
        longitude: Double,
        country: String?,
        locality: String?,
        streetName: String?,
        closestPlace: String?
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.country = country
        self.locality = locality
        self.streetName = streetName
        self.closestPlace = closestPlace
    }
}

public struct DiscoverySummary: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let title: String
    public let highlight: String
    public let shortDescription: String?
    public let detailDescription: String?
    public let capturedAt: Date
    public let imagePath: String?
    public let imageStoragePath: String?
    public let shareToken: UUID?
    public let location: DiscoveryLocation?

    public init(
        id: Int64,
        title: String,
        highlight: String,
        shortDescription: String? = nil,
        detailDescription: String? = nil,
        capturedAt: Date,
        imagePath: String? = nil,
        imageStoragePath: String? = nil,
        shareToken: UUID? = nil,
        location: DiscoveryLocation? = nil
    ) {
        self.id = id
        self.title = title
        self.highlight = highlight
        self.shortDescription = shortDescription
        self.detailDescription = detailDescription
        self.capturedAt = capturedAt
        self.imagePath = imagePath
        self.imageStoragePath = imageStoragePath
        self.shareToken = shareToken
        self.location = location
    }
}

public protocol DiscoveryRepository: Sendable {
    func fetchDiscoveries(limit: Int, before discoveryId: Int64?) async throws -> [DiscoverySummary]
    func deleteDiscovery(_ summary: DiscoverySummary) async throws
}

public enum DiscoveryFeedError: LocalizedError, Equatable {
    case failedToLoad
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case .failedToLoad:
            return "We couldn’t refresh your discoveries. Try again in a moment."
        case .unauthorized:
            return "Please sign in to view your discoveries."
        }
    }
}

public actor DiscoveryFeedUseCase: Sendable {
    private let repository: DiscoveryRepository

    public init(repository: DiscoveryRepository) {
        self.repository = repository
    }

    public func loadPage(limit: Int = 10, before discoveryId: Int64? = nil) async throws -> [DiscoverySummary] {
        try await repository.fetchDiscoveries(limit: limit, before: discoveryId)
    }
}
