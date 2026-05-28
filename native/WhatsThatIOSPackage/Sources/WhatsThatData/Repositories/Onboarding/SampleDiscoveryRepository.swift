import Foundation
import WhatsThatDomain

#if USE_REMOTE_DEPS && canImport(Supabase)
import OSLog
import Supabase
import WhatsThatInfrastructure
import WhatsThatShared

private let logger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "SampleDiscoveryRepository"
)

/// Buffer time before URL expiration to trigger a refresh (5 minutes)
private let urlExpirationBufferSeconds: TimeInterval = 300

public actor SampleDiscoveryRepository: SampleDiscoveryService {
    private let client: SupabaseClient
    private let signedURLTTL: TimeInterval
    /// Cache of voiceover paths keyed by discovery ID (populated during fetchSampleDiscoveries)
    private var voiceoverPaths: [Int64: String] = [:]
    /// Cache of signed voiceover URLs with expiration times
    private var signedVoiceoverURLs: [Int64: (url: URL, expiresAt: Date)] = [:]

    public init(
        client: SupabaseClient,
        signedURLTTL: TimeInterval = 60 * 60 * 24 // 24 hours for onboarding samples
    ) {
        self.client = client
        self.signedURLTTL = signedURLTTL
    }

    public func fetchSampleDiscoveries() async throws -> [DiscoverySummary] {
        do {
            // Call RPC with no parameters
            let builder = try client.rpc("get_sample_discoveries")
            let response: PostgrestResponse<[JSONObject]> = try await builder.execute()

            let jsonArray: JSONArray = response.value.map { AnyJSON.object($0) }
            let records: [SampleDiscoveryRow]
            do {
                records = try jsonArray.decode(as: SampleDiscoveryRow.self)
            } catch {
                if let payload = response.string() {
                    logger.error("Failed to decode sample discoveries payload: \(payload, privacy: .public)")
                }
                throw SampleDiscoveryError.failedToLoad
            }

            guard !records.isEmpty else {
                throw SampleDiscoveryError.noSamplesAvailable
            }

            // Sign URLs in parallel and convert to DiscoverySummary
            // Also cache voiceover paths for later use
            let results = try await withThrowingTaskGroup(of: (DiscoverySummary, String?).self) { group in
                for record in records {
                    group.addTask {
                        let summary = try await self.makeDiscoverySummary(from: record)
                        return (summary, record.voiceoverPath?.trimmed.nonEmpty)
                    }
                }

                var summaries: [DiscoverySummary] = []
                var paths: [Int64: String] = [:]
                summaries.reserveCapacity(records.count)

                for try await (summary, voiceoverPath) in group {
                    summaries.append(summary)
                    if let path = voiceoverPath {
                        paths[summary.id] = path
                    }
                }

                return (summaries, paths)
            }

            // Cache voiceover paths for later fetching (actor-isolated)
            self.voiceoverPaths = results.1

            // Sort by id (which reflects display_order since RPC returns ordered by display_order)
            return results.0.sorted(by: { $0.id < $1.id })
        } catch let error as SampleDiscoveryError {
            throw error
        } catch {
            // Check if task was cancelled - don't log as error
            if Task.isCancelled {
                throw CancellationError()
            }
            logger.error("Failed to fetch sample discoveries: \(error.localizedDescription, privacy: .public)")
            throw SampleDiscoveryError.failedToLoad
        }
    }

    private func makeDiscoverySummary(from record: SampleDiscoveryRow) async throws -> DiscoverySummary {
        let discoveryId = Int64(record.id)
        let storagePath = record.imagePath.trimmed
        let signedImageURL = try await loadSignedImageURL(from: record.imagePath, discoveryId: discoveryId, storagePath: storagePath)
        let shortDescription = record.shortDescription?.trimmed.nonEmpty
        let detailDescription = record.description?.trimmed.nonEmpty
        let fallbackHighlight = shortDescription ?? detailDescription?.prefix(200).description ?? "Explore this discovery"

        return DiscoverySummary(
            id: discoveryId,
            title: record.title.trimmed.nonEmpty ?? "Discovery",
            highlight: fallbackHighlight,
            shortDescription: shortDescription,
            detailDescription: detailDescription,
            capturedAt: record.createdAt,
            imagePath: signedImageURL,  // Only use signed URL, nil if signing failed
            imageStoragePath: storagePath.nonEmpty,
            shareToken: nil,    // No sharing for samples
            location: nil       // No location for samples
        )
    }

    private func loadSignedImageURL(
        from imagePath: String?,
        discoveryId: Int64,
        storagePath: String
    ) async throws -> String? {
        guard let imagePath,
              !imagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let trimmedPath = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it's already a full URL, return as-is
        if let url = URL(string: trimmedPath), url.scheme != nil, url.host != nil {
            return trimmedPath
        }

        do {
            // Check for cancellation before starting network request
            try Task.checkCancellation()

            let signedURL = try await client.storage
                .from("discovery_images")
                .createSignedURL(
                    path: trimmedPath,
                    expiresIn: Int(signedURLTTL)
                )

            // Register with the asset cache so images can be stored after download
            let expiresAt = Date().addingTimeInterval(signedURLTTL)
            await DiscoveryAssetCache.shared.storeSignedURL(
                signedURL,
                expiresAt: expiresAt,
                discoveryId: discoveryId,
                storagePath: storagePath
            )

            return signedURL.absoluteString
        } catch {
            // Don't log cancellation errors - they're expected during view recreation
            if !Task.isCancelled {
                logger.error("Failed to create signed URL for \(trimmedPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    public func fetchSampleVoiceovers(for discoveryIds: [Int64]) async throws -> [DiscoveryVoiceoverAsset] {
        guard !discoveryIds.isEmpty else { return [] }

        return await withTaskGroup(of: DiscoveryVoiceoverAsset?.self) { group in
            for discoveryId in discoveryIds {
                guard let voiceoverPath = voiceoverPaths[discoveryId] else { continue }

                group.addTask {
                    await self.makeVoiceoverAsset(discoveryId: discoveryId, voiceoverPath: voiceoverPath)
                }
            }

            var assets: [DiscoveryVoiceoverAsset] = []
            for await asset in group {
                if let asset {
                    assets.append(asset)
                }
            }
            return assets
        }
    }

    private func makeVoiceoverAsset(discoveryId: Int64, voiceoverPath: String) async -> DiscoveryVoiceoverAsset? {
        do {
            try Task.checkCancellation()

            // Check if we have a cached URL that's still valid (with buffer before expiration)
            if let cached = signedVoiceoverURLs[discoveryId],
               cached.expiresAt.timeIntervalSinceNow > urlExpirationBufferSeconds {
                return makeAsset(discoveryId: discoveryId, url: cached.url, voiceoverPath: voiceoverPath)
            }

            let signedURL = try await client.storage
                .from("voiceovers")
                .createSignedURL(
                    path: voiceoverPath,
                    expiresIn: Int(signedURLTTL)
                )

            // Cache the signed URL with expiration
            let expiresAt = Date().addingTimeInterval(signedURLTTL)
            signedVoiceoverURLs[discoveryId] = (url: signedURL, expiresAt: expiresAt)

            return makeAsset(discoveryId: discoveryId, url: signedURL, voiceoverPath: voiceoverPath)
        } catch {
            if !Task.isCancelled {
                logger.error("Failed to sign voiceover URL for discovery \(discoveryId): \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    private func makeAsset(discoveryId: Int64, url: URL, voiceoverPath: String) -> DiscoveryVoiceoverAsset {
        DiscoveryVoiceoverAsset(
            discoveryId: discoveryId,
            status: .ready,
            audioURL: url,
            provider: "sample",
            ttsModel: nil,
            voiceModelId: nil,
            fileName: (voiceoverPath as NSString).lastPathComponent,
            fileExtension: (voiceoverPath as NSString).pathExtension,
            requestedAt: nil,
            updatedAt: Date(),
            errorReason: nil,
            wasExistingResponse: true,
            wasRefunded: false,
            creditBalance: nil
        )
    }

    /// Refreshes a voiceover URL if it has expired or is about to expire.
    /// Call this when playback fails due to an expired URL.
    /// - Parameter discoveryId: The discovery ID to refresh the voiceover URL for
    /// - Returns: A fresh DiscoveryVoiceoverAsset if successful, nil otherwise
    public func refreshVoiceoverURL(for discoveryId: Int64) async -> DiscoveryVoiceoverAsset? {
        guard let voiceoverPath = voiceoverPaths[discoveryId] else {
            logger.warning("No voiceover path cached for discovery \(discoveryId)")
            return nil
        }

        // Clear cached URL to force refresh
        signedVoiceoverURLs[discoveryId] = nil

        return await makeVoiceoverAsset(discoveryId: discoveryId, voiceoverPath: voiceoverPath)
    }
}

// MARK: - Response Types

private struct SampleDiscoveryRow: Decodable {
    let id: Int
    let title: String
    let shortDescription: String?
    let description: String?
    let imagePath: String
    let voiceoverPath: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case shortDescription = "short_description"
        case description
        case imagePath = "image_path"
        case voiceoverPath = "voiceover_path"
        case createdAt = "created_at"
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

#else
// Stub implementation when Supabase is not available
public struct SampleDiscoveryRepository: SampleDiscoveryService {
    public init() {}

    public func fetchSampleDiscoveries() async throws -> [DiscoverySummary] {
        throw SampleDiscoveryError.failedToLoad
    }

    public func fetchSampleVoiceovers(for discoveryIds: [Int64]) async throws -> [DiscoveryVoiceoverAsset] {
        return []
    }

    public func refreshVoiceoverURL(for discoveryId: Int64) async -> DiscoveryVoiceoverAsset? {
        return nil
    }
}
#endif
