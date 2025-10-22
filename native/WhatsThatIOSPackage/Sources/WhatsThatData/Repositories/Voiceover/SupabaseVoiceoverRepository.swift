#if USE_REMOTE_DEPS && canImport(Supabase)
import Foundation
import OSLog
import Supabase
import WhatsThatDomain

private let supabaseVoiceoverLogger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "SupabaseVoiceoverRepository"
)

public actor SupabaseVoiceoverRepository: DiscoveryVoiceoverRepository {
    private struct CacheEntry {
        let asset: DiscoveryVoiceoverAsset
        let expirationDate: Date

        var isValid: Bool {
            Date() < expirationDate
        }
    }

    private let client: SupabaseClient
    private let bucketName: String
    private let audioExtension: String
    private let timingExtension: String
    private let voiceoverModels: [String]
    private let signedURLTTL: TimeInterval
    private let metadataCacheInterval: TimeInterval
    private let minVoiceoverDiscoveryId: Int64
    private var cache: [Int64: CacheEntry] = [:]

    public init(
        client: SupabaseClient,
        bucketName: String = "voiceovers",
        audioExtension: String = ".wav",
        timingExtension: String = ".json",
        voiceoverModels: [String] = [
            "kittentts-nano-0.2-expr-voice-3-m",
            "kittentts-nano-0.1-expr-voice-3-m",
            "kittentts-0.1.0-expr-voice-4-m"
        ],
        signedURLTTL: TimeInterval = 60 * 60 * 24 * 7,
        metadataCacheInterval: TimeInterval = 60,
        minVoiceoverDiscoveryId: Int64 = 868
    ) {
        self.client = client
        self.bucketName = bucketName
        self.audioExtension = audioExtension
        self.timingExtension = timingExtension
        self.voiceoverModels = voiceoverModels
        self.signedURLTTL = signedURLTTL
        self.metadataCacheInterval = metadataCacheInterval
        self.minVoiceoverDiscoveryId = minVoiceoverDiscoveryId
    }

    public func ensureVoiceoverAsset(
        for discoveryId: Int64,
        options: DiscoveryVoiceoverRequestOptions
    ) async -> DiscoveryVoiceoverAsset {
        if !options.forceRefresh,
           let cached = cache[discoveryId],
           cached.isValid {
            return cached.asset
        }

        if discoveryId < minVoiceoverDiscoveryId {
            let asset = DiscoveryVoiceoverAsset(
                discoveryId: discoveryId,
                status: .missing,
                audioURL: nil,
                modelIdentifier: nil,
                fetchedAt: Date(),
                errorDescription: nil
            )
            cache[discoveryId] = CacheEntry(
                asset: asset,
                expirationDate: Date().addingTimeInterval(metadataCacheInterval)
            )
            return asset
        }

        do {
            let files = try await client.storage
                .from(bucketName)
                .list(
                    path: "\(discoveryId)",
                    options: SearchOptions(limit: 50)
                )

            let names = files.map(\.name)
            let resolved = VoiceoverAssetResolver.resolve(
                availableFileNames: names,
                voiceoverModels: voiceoverModels,
                audioExtension: audioExtension,
                timingExtension: timingExtension
            )

            guard let audioFileName = resolved.audioFileName else {
                let asset = DiscoveryVoiceoverAsset(
                    discoveryId: discoveryId,
                    status: .missing,
                    audioURL: nil,
                    modelIdentifier: nil,
                    fetchedAt: Date(),
                    errorDescription: nil
                )
                cache[discoveryId] = CacheEntry(
                    asset: asset,
                    expirationDate: Date().addingTimeInterval(metadataCacheInterval)
                )
                return asset
            }

            let objectPath = "\(discoveryId)/\(audioFileName)"
            do {
                let signedURL = try await client.storage
                    .from(bucketName)
                    .createSignedURL(
                        path: objectPath,
                        expiresIn: Int(signedURLTTL)
                    )

                let asset = DiscoveryVoiceoverAsset(
                    discoveryId: discoveryId,
                    status: .available,
                    audioURL: signedURL,
                    modelIdentifier: resolved.modelIdentifier,
                    fetchedAt: Date(),
                    errorDescription: nil
                )
                cache[discoveryId] = CacheEntry(
                    asset: asset,
                    expirationDate: Date().addingTimeInterval(signedURLTTL * 0.9)
                )
                return asset
            } catch {
                if isNotFoundError(error) {
                    supabaseVoiceoverLogger.debug(
                        "Signed URL missing for \(objectPath, privacy: .public)"
                    )
                    let asset = DiscoveryVoiceoverAsset(
                        discoveryId: discoveryId,
                        status: .missing,
                        audioURL: nil,
                        modelIdentifier: resolved.modelIdentifier,
                        fetchedAt: Date(),
                        errorDescription: nil
                    )
                    cache[discoveryId] = CacheEntry(
                        asset: asset,
                        expirationDate: Date().addingTimeInterval(metadataCacheInterval)
                    )
                    return asset
                }

                supabaseVoiceoverLogger.error(
                    "Failed to create signed URL for \(objectPath, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                let asset = DiscoveryVoiceoverAsset(
                    discoveryId: discoveryId,
                    status: .error,
                    audioURL: nil,
                    modelIdentifier: resolved.modelIdentifier,
                    fetchedAt: Date(),
                    errorDescription: error.localizedDescription
                )
                cache[discoveryId] = CacheEntry(
                    asset: asset,
                    expirationDate: Date().addingTimeInterval(metadataCacheInterval)
                )
                return asset
            }
        } catch {
            supabaseVoiceoverLogger.error(
                "Failed to list voiceover assets for discovery \(discoveryId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            let asset = DiscoveryVoiceoverAsset(
                discoveryId: discoveryId,
                status: isNotFoundError(error) ? .missing : .error,
                audioURL: nil,
                modelIdentifier: nil,
                fetchedAt: Date(),
                errorDescription: error.localizedDescription
            )
            cache[discoveryId] = CacheEntry(
                asset: asset,
                expirationDate: Date().addingTimeInterval(metadataCacheInterval)
            )
            return asset
        }
    }

    private func isNotFoundError(_ error: Error) -> Bool {
        if let storageError = error as? StorageError {
            return storageError.statusCode == "404"
                || storageError.message.lowercased().contains("not found")
        }

        let description = error.localizedDescription.lowercased()
        if description.contains("404") || description.contains("not found") {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return false
        }

        return nsError.code == 404
    }
}

@usableFromInline
struct VoiceoverAssetResolver {
    let availableFileNames: [String]
    let voiceoverModels: [String]
    let audioExtension: String
    let timingExtension: String

    init(
        availableFileNames: [String],
        voiceoverModels: [String],
        audioExtension: String,
        timingExtension: String
    ) {
        self.availableFileNames = availableFileNames
        self.voiceoverModels = voiceoverModels
        self.audioExtension = audioExtension
        self.timingExtension = timingExtension
    }

    var audioFileName: String? {
        for model in voiceoverModels {
            let candidate = model + audioExtension
            if availableFileNames.contains(candidate) {
                return candidate
            }
        }

        return availableFileNames.first { $0.hasSuffix(audioExtension) }
    }

    var modelIdentifier: String? {
        guard let audioFileName else { return nil }
        let trimmed = audioFileName.replacingOccurrences(of: audioExtension, with: "")
        return trimmed.isEmpty ? nil : trimmed
    }

    var timingFileName: String? {
        if let modelIdentifier {
            let candidate = modelIdentifier + timingExtension
            if availableFileNames.contains(candidate) {
                return candidate
            }
        }

        guard let audioFileName else { return nil }
        let base = audioFileName.replacingOccurrences(of: audioExtension, with: "")
        let fallback = base + timingExtension
        return availableFileNames.contains(fallback) ? fallback : nil
    }

    static func resolve(
        availableFileNames: [String],
        voiceoverModels: [String],
        audioExtension: String,
        timingExtension: String
    ) -> (audioFileName: String?, modelIdentifier: String?, timingFileName: String?) {
        let resolver = VoiceoverAssetResolver(
            availableFileNames: availableFileNames,
            voiceoverModels: voiceoverModels,
            audioExtension: audioExtension,
            timingExtension: timingExtension
        )
        return (
            resolver.audioFileName,
            resolver.modelIdentifier,
            resolver.timingFileName
        )
    }
}
#else
import Foundation
import WhatsThatDomain

public struct SupabaseVoiceoverRepository: DiscoveryVoiceoverRepository {
    public init() {}

    public func ensureVoiceoverAsset(
        for discoveryId: Int64,
        options _: DiscoveryVoiceoverRequestOptions
    ) async -> DiscoveryVoiceoverAsset {
        DiscoveryVoiceoverAsset(
            discoveryId: discoveryId,
            status: .missing,
            audioURL: nil,
            modelIdentifier: nil,
            fetchedAt: Date(),
            errorDescription: nil
        )
    }
}
#endif
