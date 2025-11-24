#if USE_REMOTE_DEPS && canImport(Supabase)
import Foundation
import OSLog
import Supabase
import WhatsThatDomain
import WhatsThatInfrastructure
import WhatsThatShared

private let supabaseDiscoveryLogger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "SupabaseDiscoveryRepository"
)

public enum SupabaseDiscoveryRepositoryError: LocalizedError {
    case decodingFailure

    public var errorDescription: String? {
        switch self {
        case .decodingFailure:
            return "The discovery response could not be decoded."
        }
    }
}

public struct SupabaseDiscoveryRepository: DiscoveryRepository, DiscoveryHistoryRepository {
    private let client: SupabaseClient
    private let assetCache: DiscoveryAssetCache
    private let signedURLTTL: TimeInterval

    public init(
        client: SupabaseClient,
        assetCache: DiscoveryAssetCache = .shared,
        signedURLTTL: TimeInterval = 60 * 60 * 24 * 7
    ) {
        self.client = client
        self.assetCache = assetCache
        self.signedURLTTL = signedURLTTL
    }

    public init(
        configuration: AppConfiguration,
        session: URLSession = .shared
    ) throws {
        let client = try SupabaseClientFactory.makeClient(
            configuration: configuration,
            session: session
        )
        self.init(client: client)
    }

    public func fetchDiscoveries(limit: Int, before discoveryId: Int64?) async throws -> [DiscoverySummary] {
        guard client.auth.currentUser?.id != nil else {
            supabaseDiscoveryLogger.error("Attempted to fetch discoveries without an authenticated Supabase user.")
            throw DiscoveryFeedError.unauthorized
        }

        // supabaseDiscoveryLogger.debug(
        //     "fetchDiscoveries start limit=\(limit, privacy: .public) cursor=\(String(describing: discoveryId), privacy: .public) taskCancelled=\(Task.isCancelled, privacy: .public)"
        // )

        do {
            let params = GetDiscoveriesParams(
                p_limit: limit,
                p_last_id: discoveryId
            )

            let builder = try client.rpc(
                "get_discoveries_with_location",
                params: params
            )

            let response: PostgrestResponse<[JSONObject]> = try await builder.execute()

            let jsonArray: JSONArray = response.value.map { AnyJSON.object($0) }
            let records: [DiscoveryRecord]
            do {
                records = try jsonArray.decode(as: DiscoveryRecord.self)
            } catch {
                if let payload = response.string() {
                    supabaseDiscoveryLogger.error("Failed to decode discoveries payload: \(payload, privacy: .public)")
                }
                throw error
            }

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
            let nsError = error as NSError
            if error.isCancellationError {
                supabaseDiscoveryLogger.error(
                    """
                    Discovery fetch cancelled unexpectedly: \(error.localizedDescription, privacy: .public) \
                    domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \
                    underlying=\(String(describing: nsError.userInfo[NSUnderlyingErrorKey]), privacy: .public) \
                    taskCancelled=\(Task.isCancelled, privacy: .public)
                    """
                )
            } else {
                supabaseDiscoveryLogger.error(
                    """
                    Failed to fetch discoveries: \(error.localizedDescription, privacy: .public) \
                    domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \
                    underlying=\(String(describing: nsError.userInfo[NSUnderlyingErrorKey]), privacy: .public)
                    """
                )
            }
            throw DiscoveryFeedError.failedToLoad
        }
    }
}

public extension SupabaseDiscoveryRepository {
    func fetchRecentDiscoveries(limit: Int) async throws -> [DiscoverySummary] {
        try await fetchDiscoveries(limit: limit, before: nil)
    }

    func deleteDiscovery(_ summary: DiscoverySummary) async throws {
        guard let userId = client.auth.currentUser?.id else {
            supabaseDiscoveryLogger.error("Attempted to delete discovery \(summary.id, privacy: .public) without an authenticated Supabase user.")
            throw DiscoveryFeedError.unauthorized
        }

        do {
            _ = try await client
                .from("discoveries")
                .delete(returning: .minimal)
                .eq("id", value: Int(summary.id))
                .eq("user_id", value: userId.uuidString)
                .execute()
        } catch {
            supabaseDiscoveryLogger.error("Failed to delete discovery \(summary.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }

        await assetCache.invalidateSignedURL(for: summary.id)

        guard let storagePath = resolveStoragePath(for: summary) else {
            return
        }

        do {
            _ = try await client.storage
                .from("discovery_images")
                .remove(paths: [storagePath])
        } catch {
            supabaseDiscoveryLogger.warning("Deleted discovery \(summary.id, privacy: .public) but failed to remove image \(storagePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct GetDiscoveriesParams: Encodable {
    let p_limit: Int
    let p_last_id: Int64?
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
    let location: String?

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
        case location
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
        guard let location,
              location.hasPrefix("POINT("),
              location.hasSuffix(")") else {
            return nil
        }

        let inner = location
            .dropFirst("POINT(".count)
            .dropLast()
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
        let signedImageURL = try await loadSignedImageURL(
            for: record.id,
            from: record.imageURL
        )
        let shortDescription = record.shortDescription?.trimmed.nonEmpty
        let detailDescription = record.description?.trimmed.nonEmpty
        let fallbackHighlight = shortDescription ?? detailDescription ?? "No summary available yet."

        return DiscoverySummary(
            id: record.id,
            title: record.title?.trimmed.nonEmpty ?? "Discovery",
            highlight: fallbackHighlight,
            shortDescription: shortDescription,
            detailDescription: detailDescription,
            capturedAt: record.createdAt,
            imagePath: signedImageURL ?? record.imageURL?.trimmed.nonEmpty,
            imageStoragePath: record.imageURL?.trimmed.nonEmpty,
            shareToken: record.shareToken,
            location: record.makeLocation()
        )
    }

    func loadSignedImageURL(
        for discoveryId: Int64,
        from imagePath: String?
    ) async throws -> String? {
        guard let imagePath,
              !imagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let trimmedPath = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmedPath), url.scheme != nil, url.host != nil {
            return trimmedPath
        }

        if let cachedURL = await assetCache.cachedSignedURL(
            for: discoveryId,
            storagePath: trimmedPath
        ) {
            return cachedURL.absoluteString
        }

        do {
            let signedURL = try await client.storage
                .from("discovery_images")
                .createSignedURL(
                    path: trimmedPath,
                    expiresIn: Int(signedURLTTL)
                )

            let expirationDate = Date().addingTimeInterval(signedURLTTL)
            await assetCache.storeSignedURL(
                signedURL,
                expiresAt: expirationDate,
                discoveryId: discoveryId,
                storagePath: trimmedPath
            )

            return signedURL.absoluteString
        } catch {
            supabaseDiscoveryLogger.error("Failed to create signed URL for \(trimmedPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            await assetCache.invalidateSignedURL(for: discoveryId)
            return nil
        }
    }

    private func resolveStoragePath(for summary: DiscoverySummary) -> String? {
        if let directPath = summary.imageStoragePath?.nonEmpty {
            return directPath
        }
        guard let imagePath = summary.imagePath else {
            return nil
        }
        return resolveStoragePath(from: imagePath)
    }

    private func resolveStoragePath(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let range = trimmed.range(of: "/discovery_images/", options: .caseInsensitive) {
            var path = String(trimmed[range.upperBound...])
            if let queryIndex = path.firstIndex(of: "?") {
                path = String(path[..<queryIndex])
            }
            path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return path.removingPercentEncoding?.nonEmpty ?? path.nonEmpty
        }

        return trimmed.nonEmpty
    }
}

private extension Error {
    var isCancellationError: Bool {
        if self is CancellationError {
            return true
        }

        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return underlying.isCancellationError
        }

        return false
    }
}
#endif
