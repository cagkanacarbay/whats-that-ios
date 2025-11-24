import Foundation
import WhatsThatDomain

#if USE_REMOTE_DEPS && canImport(Supabase)
import OSLog
import Supabase
import WhatsThatInfrastructure
import WhatsThatShared

private let supabaseVoiceoverLogger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "SupabaseVoiceoverRepository"
)

public actor SupabaseVoiceoverRepository: DiscoveryVoiceoverRepository {
    private struct CacheEntry {
        let asset: DiscoveryVoiceoverAsset
        let updatedAt: Date?
        let expiresAt: Date?

        var isValid: Bool {
            if let expiresAt {
                return Date() < expiresAt
            }
            return true
        }
    }

    private let client: SupabaseClient
    private let configuration: AppConfiguration
    private let urlSession: URLSession
    private let signedURLTTL: TimeInterval
    private var cache: [Int64: CacheEntry] = [:]

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Self.iso8601FractionalFormatter.date(from: string) {
                return date
            }
            if let date = ISO8601DateFormatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(string)"
            )
        }
        return decoder
    }

    private static let decoder = SupabaseVoiceoverRepository.makeDecoder()

    static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public init(
        client: SupabaseClient,
        configuration: AppConfiguration,
        urlSession: URLSession = .shared,
        signedURLTTL: TimeInterval = 60 * 60 * 24 * 7
    ) {
        self.client = client
        self.configuration = configuration
        self.urlSession = urlSession
        self.signedURLTTL = signedURLTTL
    }

    // Backward-compatible initializer for existing call sites
    public init(
        client: SupabaseClient,
        configuration: AppConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.init(client: client, configuration: configuration, urlSession: urlSession, signedURLTTL: 60 * 60 * 24 * 7)
    }

    public func fetchVoiceovers(for discoveryIds: [Int64]) async -> [DiscoveryVoiceoverAsset] {
        guard !discoveryIds.isEmpty else { return [] }

        do {
            let response: PostgrestResponse<[VoiceoverTableRow]> = try await client
                .from("discovery_voiceovers")
                .select()
                .in("discovery_id", values: discoveryIds.map { Int($0) })
                .execute()
            let rows = response.value

            var mapped: [Int64: DiscoveryVoiceoverAsset] = [:]
            for row in rows {
                let audioURL = await signIfNeeded(
                    discoveryId: row.discovery_id,
                    fileName: row.file_name,
                    status: row.status
                )
                let expiry = audioURL != nil ? Date().addingTimeInterval(signedURLTTL) : nil
                let asset = mapAsset(
                    discoveryId: row.discovery_id,
                    status: row.status,
                    audioURLString: audioURL?.absoluteString,
                    provider: row.provider,
                    ttsModel: row.tts_model,
                    voiceModelId: row.voice_model_id,
                    fileName: row.file_name,
                    fileExtension: row.file_extension,
                    requestedAt: date(from: row.requested_at),
                    updatedAt: date(from: row.updated_at),
                    errorReason: row.error_reason,
                    wasExisting: true,
                    wasRefunded: false
                )
                mapped[row.discovery_id] = asset
                cache[row.discovery_id] = CacheEntry(asset: asset, updatedAt: asset.updatedAt, expiresAt: expiry)
            }

            return discoveryIds.map { id in
                if let asset = mapped[id] {
                    return asset
                }
                return DiscoveryVoiceoverAsset(
                    discoveryId: id,
                    status: .none,
                    audioURL: nil,
                    provider: nil,
                    ttsModel: nil,
                    voiceModelId: nil,
                    fileName: nil,
                    fileExtension: nil,
                    requestedAt: nil,
                    updatedAt: nil,
                    errorReason: nil,
                    wasExistingResponse: false,
                    wasRefunded: false
                )
            }
        } catch {
            supabaseVoiceoverLogger.error("Failed to fetch voiceovers: \(error.localizedDescription, privacy: .public)")
            return discoveryIds.map { id in
                DiscoveryVoiceoverAsset(
                    discoveryId: id,
                    status: .missing,
                    audioURL: nil,
                    provider: nil,
                    ttsModel: nil,
                    voiceModelId: nil,
                    fileName: nil,
                    fileExtension: nil,
                    requestedAt: nil,
                    updatedAt: nil,
                    errorReason: error.localizedDescription,
                    wasExistingResponse: false,
                    wasRefunded: false
                )
            }
        }
    }

    public func requestVoiceover(
        for discoveryId: Int64,
        voiceModelId: String,
        ttsModel: String,
        prosody: VoiceoverProsody?
    ) async -> DiscoveryVoiceoverAsset {
        guard let supabaseURL = configuration.supabaseURL else {
            return DiscoveryVoiceoverAsset(
                discoveryId: discoveryId,
                status: .failed,
                audioURL: nil,
                provider: nil,
                ttsModel: ttsModel,
                voiceModelId: voiceModelId,
                fileName: nil,
                fileExtension: nil,
                requestedAt: nil,
                updatedAt: nil,
                errorReason: "Missing Supabase configuration",
                wasExistingResponse: false,
                wasRefunded: false
            )
        }

        guard let accessToken = client.auth.currentSession?.accessToken else {
            return DiscoveryVoiceoverAsset(
                discoveryId: discoveryId,
                status: .failed,
                audioURL: nil,
                provider: nil,
                ttsModel: ttsModel,
                voiceModelId: voiceModelId,
                fileName: nil,
                fileExtension: nil,
                requestedAt: nil,
                updatedAt: nil,
                errorReason: "Not authenticated",
                wasExistingResponse: false,
                wasRefunded: false
            )
        }

        let baseURL = SupabaseDiscoveryAnalysisClient.functionsBaseURL(from: supabaseURL)
        let requestURL = baseURL.appendingPathComponent("generate-voiceover")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body = VoiceoverRequestBody(
            discovery_id: discoveryId,
            voice_model_id: voiceModelId,
            tts_model: ttsModel,
            prosody: prosody
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            return DiscoveryVoiceoverAsset(
                discoveryId: discoveryId,
                status: .failed,
                audioURL: nil,
                provider: nil,
                ttsModel: ttsModel,
                voiceModelId: voiceModelId,
                fileName: nil,
                fileExtension: nil,
                requestedAt: nil,
                updatedAt: nil,
                errorReason: error.localizedDescription,
                wasExistingResponse: false,
                wasRefunded: false
            )
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 402 {
                return DiscoveryVoiceoverAsset(
                    discoveryId: discoveryId,
                    status: .failed,
                    audioURL: nil,
                    provider: nil,
                    ttsModel: ttsModel,
                    voiceModelId: voiceModelId,
                    fileName: nil,
                    fileExtension: nil,
                    requestedAt: nil,
                    updatedAt: nil,
                    errorReason: "insufficient_credits",
                    wasExistingResponse: false,
                    wasRefunded: false
                )
            }

            if (200..<300).contains(httpResponse.statusCode) {
                do {
                    let response = try Self.decoder.decode(VoiceoverEdgeResponse.self, from: data)
                    let asset = mapAsset(
                        discoveryId: response.discoveryId,
                        status: response.status,
                        audioURLString: response.audioURL,
                        provider: response.provider,
                        ttsModel: response.ttsModel,
                        voiceModelId: response.voiceModelId,
                        fileName: response.fileName,
                        fileExtension: response.fileExtension,
                        requestedAt: response.requestedAt,
                        updatedAt: response.updatedAt,
                        errorReason: response.errorReason,
                        wasExisting: response.wasExisting ?? false,
                        wasRefunded: response.wasRefunded ?? false
                    )
                    cache[asset.discoveryId] = CacheEntry(
                        asset: asset,
                        updatedAt: asset.updatedAt,
                        expiresAt: response.audioURLExpiresAt
                    )
                    return asset
                } catch {
                    let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8-body>"
                    supabaseVoiceoverLogger.error("Voiceover decode failed: \(error.localizedDescription, privacy: .public) body=\(rawBody, privacy: .public)")
                    return DiscoveryVoiceoverAsset(
                        discoveryId: discoveryId,
                        status: .failed,
                        audioURL: nil,
                        provider: nil,
                        ttsModel: ttsModel,
                        voiceModelId: voiceModelId,
                        fileName: nil,
                        fileExtension: nil,
                        requestedAt: nil,
                        updatedAt: nil,
                        errorReason: "decode_error",
                        wasExistingResponse: false,
                        wasRefunded: false
                    )
                }
            }

            let message = decodeErrorMessage(data: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            return DiscoveryVoiceoverAsset(
                discoveryId: discoveryId,
                status: .failed,
                audioURL: nil,
                provider: nil,
                ttsModel: ttsModel,
                voiceModelId: voiceModelId,
                fileName: nil,
                fileExtension: nil,
                requestedAt: nil,
                updatedAt: nil,
                errorReason: message,
                wasExistingResponse: false,
                wasRefunded: false
            )
        } catch {
            supabaseVoiceoverLogger.error("Voiceover request failed: \(error.localizedDescription, privacy: .public)")
            return DiscoveryVoiceoverAsset(
                discoveryId: discoveryId,
                status: .failed,
                audioURL: nil,
                provider: nil,
                ttsModel: ttsModel,
                voiceModelId: voiceModelId,
                fileName: nil,
                fileExtension: nil,
                requestedAt: nil,
                updatedAt: nil,
                errorReason: error.localizedDescription,
                wasExistingResponse: false,
                wasRefunded: false
            )
        }
    }
}

private func date(from string: String?) -> Date? {
    guard let string else { return nil }
    if let date = SupabaseVoiceoverRepository.iso8601FractionalFormatter.date(from: string) {
        return date
    }
    return SupabaseVoiceoverRepository.iso8601Formatter.date(from: string)
}

private extension SupabaseVoiceoverRepository {
    func signIfNeeded(discoveryId: Int64, fileName: String?, status: String) async -> URL? {
        guard status.lowercased() == "ready",
              let fileName,
              !fileName.isEmpty else {
            return nil
        }

        let path = "\(discoveryId)/\(fileName)"
        do {
            let signedURL = try await client.storage
                .from("voiceovers")
                .createSignedURL(
                    path: path,
                    expiresIn: Int(signedURLTTL)
                )
            return signedURL
        } catch {
            supabaseVoiceoverLogger.error("Failed to sign voiceover URL for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func mapAsset(
        discoveryId: Int64,
        status: String,
        audioURLString: String?,
        provider: String?,
        ttsModel: String?,
        voiceModelId: String?,
        fileName: String?,
        fileExtension: String?,
        requestedAt: Date?,
        updatedAt: Date?,
        errorReason: String?,
        wasExisting: Bool,
        wasRefunded: Bool
    ) -> DiscoveryVoiceoverAsset {
        let resolvedStatus = Self.status(from: status)
        let resolvedURL = audioURLString.flatMap { URL(string: $0) }

        return DiscoveryVoiceoverAsset(
            discoveryId: discoveryId,
            status: resolvedURL == nil && resolvedStatus == .ready ? .processing : resolvedStatus,
            audioURL: resolvedURL,
            provider: provider,
            ttsModel: ttsModel,
            voiceModelId: voiceModelId,
            fileName: fileName,
            fileExtension: fileExtension,
            requestedAt: requestedAt,
            updatedAt: updatedAt,
            errorReason: errorReason,
            wasExistingResponse: wasExisting,
            wasRefunded: wasRefunded
        )
    }

    static func status(from rawValue: String?) -> DiscoveryVoiceoverStatus {
        switch rawValue?.lowercased() {
        case "ready":
            return .ready
        case "processing":
            return .processing
        case "failed":
            return .failed
        case "missing":
            return .missing
        default:
            return .missing
        }
    }

    func decodeErrorMessage(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        if let message = json["message"] as? String {
            return message
        }
        if let error = json["error"] as? String {
            return error
        }
        return nil
    }
}

private struct VoiceoverTableRow: Decodable {
    let discovery_id: Int64
    let provider: String?
    let tts_model: String?
    let voice_model_id: String?
    let file_name: String?
    let file_extension: String?
    let status: String
    let error_reason: String?
    let requested_at: String?
    let updated_at: String?
}

private struct VoiceoverRequestBody: Encodable {
    let discovery_id: Int64
    let voice_model_id: String
    let tts_model: String
    let prosody: VoiceoverProsody?
}

private struct VoiceoverEdgeResponse: Decodable {
    let id: Int64
    let discoveryId: Int64
    let provider: String?
    let ttsModel: String?
    let voiceModelId: String?
    let fileName: String?
    let fileExtension: String?
    let status: String
    let errorReason: String?
    let requestedAt: Date?
    let updatedAt: Date?
    let audioURL: String?
    let audioURLExpiresAt: Date?
    let wasRefunded: Bool?
    let wasExisting: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case discoveryId = "discovery_id"
        case provider
        case ttsModel = "tts_model"
        case voiceModelId = "voice_model_id"
        case fileName = "file_name"
        case fileExtension = "file_extension"
        case status
        case errorReason = "error_reason"
        case requestedAt = "requested_at"
        case updatedAt = "updated_at"
        case audioURL = "audio_url"
        case audioURLExpiresAt = "audio_url_expires_at"
        case wasRefunded = "was_refunded"
        case wasExisting = "was_existing"
    }
}

#else
public struct SupabaseVoiceoverRepository: DiscoveryVoiceoverRepository {
    public init() {}

    public func fetchVoiceovers(for discoveryIds: [Int64]) async -> [DiscoveryVoiceoverAsset] {
        discoveryIds.map {
            DiscoveryVoiceoverAsset(
                discoveryId: $0,
                status: .none,
                audioURL: nil,
                provider: nil,
                ttsModel: nil,
                voiceModelId: nil,
                fileName: nil,
                fileExtension: nil,
                requestedAt: nil,
                updatedAt: nil,
                errorReason: nil,
                wasExistingResponse: false,
                wasRefunded: false
            )
        }
    }

    public func requestVoiceover(
        for discoveryId: Int64,
        voiceModelId: String,
        ttsModel: String,
        prosody: VoiceoverProsody?
    ) async -> DiscoveryVoiceoverAsset {
        DiscoveryVoiceoverAsset(
            discoveryId: discoveryId,
            status: .missing,
            audioURL: nil,
            provider: nil,
            ttsModel: ttsModel,
            voiceModelId: voiceModelId,
            fileName: nil,
            fileExtension: nil,
            requestedAt: nil,
            updatedAt: nil,
            errorReason: "Voiceover unavailable",
            wasExistingResponse: false,
            wasRefunded: false
        )
    }
}
#endif
