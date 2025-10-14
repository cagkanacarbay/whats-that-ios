#if USE_REMOTE_DEPS && canImport(Supabase)
import Foundation
import Supabase
import WhatsThatDomain
import WhatsThatInfrastructure
import WhatsThatShared

public enum SupabaseDiscoveryRepositoryError: LocalizedError {
    case decodingFailure

    public var errorDescription: String? {
        switch self {
        case .decodingFailure:
            return "The discovery response could not be decoded."
        }
    }
}

public struct SupabaseDiscoveryRepository: DiscoveryRepository {
    private let client: SupabaseClient

    public init(
        configuration: AppConfiguration,
        session: URLSession = .shared
    ) throws {
        self.client = try SupabaseClientFactory.makeClient(
            configuration: configuration,
            session: session
        )
    }

    public func fetchDiscoveries(limit: Int, before discoveryId: Int64?) async throws -> [DiscoverySummary] {
        do {
            var builder = client
                .from("discoveries")
                .select("""
                    id,
                    user_id,
                    title,
                    short_description,
                    description,
                    image_url,
                    created_at,
                    country,
                    locality,
                    street_name,
                    closest_place,
                    share_token,
                    ST_AsText(location) as location_text
                """, head: false)

            if let discoveryId,
               let cursor = Int(exactly: discoveryId) {
                builder = builder.lt("id", value: cursor)
            }

            let response: PostgrestResponse<[DiscoveryRecord]> = try await builder
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()

            let records = response.value

            return try await withThrowingTaskGroup(of: DiscoverySummary?.self) { group in
                for record in records {
                    group.addTask {
                        try await self.makeDiscoverySummary(from: record)
                    }
                }

                var summaries: [DiscoverySummary] = []
                summaries.reserveCapacity(records.count)

                for try await summary in group {
                    if let summary {
                        summaries.append(summary)
                    }
                }

                return summaries.sorted(by: { $0.capturedAt > $1.capturedAt })
            }
        } catch {
            throw DiscoveryFeedError.failedToLoad
        }
    }
}

private struct DiscoveryRecord: Decodable {
    let id: Int64
    let userId: UUID?
    let title: String?
    let shortDescription: String?
    let description: String?
    let imageURL: String?
    let createdAt: Date
    let country: String?
    let locality: String?
    let streetName: String?
    let closestPlace: String?
    let shareToken: UUID?
    let locationText: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case shortDescription = "short_description"
        case description
        case imageURL = "image_url"
        case createdAt = "created_at"
        case country
        case locality
        case streetName = "street_name"
        case closestPlace = "closest_place"
        case shareToken = "share_token"
        case locationText = "location_text"
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension DiscoveryRecord {
    func makeLocation() -> DiscoveryLocation? {
        guard let locationText else {
            return nil
        }

        let trimmed = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("POINT("), trimmed.hasSuffix(")") else {
            return nil
        }

        let inner = trimmed.dropFirst("POINT(".count).dropLast()
        let components = inner.split(whereSeparator: { $0 == " " || $0 == "," })

        guard components.count >= 2,
              let longitude = Double(components[0]),
              let latitude = Double(components[1]) else {
            return nil
        }

        return DiscoveryLocation(
            latitude: latitude,
            longitude: longitude,
            country: country?.nonEmpty,
            locality: locality?.nonEmpty,
            streetName: streetName?.nonEmpty,
            closestPlace: closestPlace?.nonEmpty
        )
    }
}

private extension SupabaseDiscoveryRepository {
    func makeDiscoverySummary(from record: DiscoveryRecord) async throws -> DiscoverySummary {
        let signedImageURL = try await loadSignedImageURL(from: record.imageURL)

        return DiscoverySummary(
            id: record.id,
            title: record.title?.trimmed.nonEmpty ?? "Discovery",
            highlight: record.shortDescription?.trimmed.nonEmpty ?? record.description?.trimmed.nonEmpty ?? "No summary available yet.",
            capturedAt: record.createdAt,
            imagePath: signedImageURL ?? record.imageURL?.trimmed.nonEmpty,
            shareToken: record.shareToken,
            location: record.makeLocation()
        )
    }

    func loadSignedImageURL(from imagePath: String?) async throws -> String? {
        guard let imagePath,
              !imagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        do {
            let signedURL = try await client.storage
                .from("discovery_images")
                .createSignedURL(
                    path: imagePath,
                    expiresIn: 60 * 60 * 24 * 7 // 7 days
                )
            return signedURL.absoluteString
        } catch {
            return nil
        }
    }
}
#endif
