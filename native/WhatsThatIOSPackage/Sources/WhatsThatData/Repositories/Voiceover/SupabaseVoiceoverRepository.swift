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
    private let voiceoverFileCache: VoiceoverFileCache
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
        signedURLTTL: TimeInterval = 60 * 60 * 24 * 7,
        voiceoverFileCache: VoiceoverFileCache = .shared
    ) {
        self.client = client
        self.configuration = configuration
        self.urlSession = urlSession
        self.signedURLTTL = signedURLTTL
        self.voiceoverFileCache = voiceoverFileCache
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
        ttsModel: String
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
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body = VoiceoverRequestBody(
            discovery_id: discoveryId,
            voice_model_id: voiceModelId,
            tts_model: ttsModel
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
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

                if contentType.contains("audio/mpeg") {
                    // DIRECT AUDIO PATH: MP3 bytes in body, metadata in headers
                    return await handleDirectAudioResponse(
                        data: data,
                        headers: httpResponse,
                        discoveryId: discoveryId,
                        ttsModel: ttsModel,
                        voiceModelId: voiceModelId
                    )
                }

                // EXISTING JSON PATH
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
                        wasRefunded: response.wasRefunded ?? false,
                        creditBalance: response.creditBalance
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
    
    public func countUserVoiceovers() async -> Int {
        do {
            // Query discovery_voiceovers for count of user's voiceovers
            // RLS will filter to only the current user's voiceovers
            let response: PostgrestResponse<[VoiceoverCountRow]> = try await client
                .from("discovery_voiceovers")
                .select("id")
                .execute()
            return response.value.count
        } catch {
            supabaseVoiceoverLogger.error("Failed to count voiceovers: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    public nonisolated func streamVoiceover(
        for discoveryId: Int64,
        voiceModelId: String,
        ttsModel: String
    ) -> AsyncStream<VoiceoverStreamEvent> {
        AsyncStream { continuation in
            let task = Task { [client, configuration] in
                guard let supabaseURL = configuration.supabaseURL else {
                    continuation.yield(.failed("Missing Supabase configuration"))
                    continuation.finish()
                    return
                }

                guard let accessToken = client.auth.currentSession?.accessToken else {
                    continuation.yield(.failed("Not authenticated"))
                    continuation.finish()
                    return
                }

                let baseURL = SupabaseDiscoveryAnalysisClient.functionsBaseURL(from: supabaseURL)
                let requestURL = baseURL.appendingPathComponent("generate-voiceover")

                var request = URLRequest(url: requestURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

                let body = VoiceoverRequestBody(
                    discovery_id: discoveryId,
                    voice_model_id: voiceModelId,
                    tts_model: ttsModel
                )

                do {
                    request.httpBody = try JSONEncoder().encode(body)
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                    return
                }

                let delegate = VoiceoverStreamURLSessionDelegate(
                    continuation: continuation,
                    discoveryId: discoveryId,
                    ttsModel: ttsModel,
                    voiceModelId: voiceModelId
                )

                let session = URLSession(
                    configuration: .default,
                    delegate: delegate,
                    delegateQueue: nil
                )

                let dataTask = session.dataTask(with: request)
                dataTask.resume()

                continuation.onTermination = { @Sendable _ in
                    dataTask.cancel()
                    session.invalidateAndCancel()
                }
            }
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
        wasRefunded: Bool,
        creditBalance: Int? = nil
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
            wasRefunded: wasRefunded,
            creditBalance: creditBalance
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

    func handleDirectAudioResponse(
        data: Data,
        headers: HTTPURLResponse,
        discoveryId: Int64,
        ttsModel: String,
        voiceModelId: String
    ) async -> DiscoveryVoiceoverAsset {
        let fileName = headers.value(forHTTPHeaderField: "X-File-Name") ?? "voiceover.mp3"
        let fileExtension = headers.value(forHTTPHeaderField: "X-File-Extension") ?? "mp3"
        let provider = headers.value(forHTTPHeaderField: "X-Provider")
        let headerTtsModel = headers.value(forHTTPHeaderField: "X-TTS-Model") ?? ttsModel
        let headerVoiceModelId = headers.value(forHTTPHeaderField: "X-Voice-Model-Id") ?? voiceModelId
        let wasExisting = headers.value(forHTTPHeaderField: "X-Was-Existing") == "true"
        let wasRefunded = headers.value(forHTTPHeaderField: "X-Was-Refunded") == "true"
        let creditBalance: Int? = headers.value(forHTTPHeaderField: "X-Credit-Balance").flatMap { Int($0) }

        // Store audio bytes directly in file cache
        do {
            _ = try await voiceoverFileCache.store(data: data, discoveryId: discoveryId, fileName: fileName)
            supabaseVoiceoverLogger.info("Stored direct audio bytes in cache: \(data.count) bytes for discovery \(discoveryId)")
        } catch {
            supabaseVoiceoverLogger.error("Failed to cache direct audio: \(error.localizedDescription, privacy: .public)")
        }

        let asset = DiscoveryVoiceoverAsset(
            discoveryId: discoveryId,
            status: .ready,
            audioURL: nil,
            provider: provider,
            ttsModel: headerTtsModel,
            voiceModelId: headerVoiceModelId,
            fileName: fileName,
            fileExtension: fileExtension,
            requestedAt: nil,
            updatedAt: Date(),
            errorReason: nil,
            wasExistingResponse: wasExisting,
            wasRefunded: wasRefunded,
            creditBalance: creditBalance
        )

        cache[discoveryId] = CacheEntry(asset: asset, updatedAt: Date(), expiresAt: nil)
        return asset
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

// MARK: - Streaming URLSession Delegate

final class VoiceoverStreamURLSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: AsyncStream<VoiceoverStreamEvent>.Continuation
    private let discoveryId: Int64
    private let ttsModel: String
    private let voiceModelId: String
    private var didEmitMetadata = false
    private var receivedAudioData = false
    /// Accumulated JSON body when server returns application/json instead of streaming audio
    private var jsonAccumulator = Data()

    init(
        continuation: AsyncStream<VoiceoverStreamEvent>.Continuation,
        discoveryId: Int64,
        ttsModel: String,
        voiceModelId: String
    ) {
        self.continuation = continuation
        self.discoveryId = discoveryId
        self.ttsModel = ttsModel
        self.voiceModelId = voiceModelId
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            continuation.yield(.failed("Invalid response"))
            continuation.finish()
            return
        }

        // Handle non-success status
        if httpResponse.statusCode == 402 {
            completionHandler(.cancel)
            continuation.yield(.failed("insufficient_credits"))
            continuation.finish()
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            completionHandler(.cancel)
            continuation.yield(.failed("Server error: \(httpResponse.statusCode)"))
            continuation.finish()
            return
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

        // If server returned JSON instead of audio, it's a non-streaming response (existing voiceover, etc.)
        if contentType.contains("application/json") {
            // Let data accumulate — we'll parse JSON in didCompleteWithError
            completionHandler(.allow)
            return
        }

        // Parse metadata from X-headers
        let metadata = VoiceoverStreamMetadata(
            voiceoverId: httpResponse.value(forHTTPHeaderField: "X-Voiceover-Id"),
            fileName: httpResponse.value(forHTTPHeaderField: "X-File-Name") ?? "voiceover.mp3",
            fileExtension: httpResponse.value(forHTTPHeaderField: "X-File-Extension") ?? "mp3",
            provider: httpResponse.value(forHTTPHeaderField: "X-Provider"),
            ttsModel: httpResponse.value(forHTTPHeaderField: "X-TTS-Model") ?? ttsModel,
            voiceModelId: httpResponse.value(forHTTPHeaderField: "X-Voice-Model-Id") ?? voiceModelId,
            creditBalance: httpResponse.value(forHTTPHeaderField: "X-Credit-Balance").flatMap { Int($0) },
            wasExisting: httpResponse.value(forHTTPHeaderField: "X-Was-Existing") == "true",
            wasRefunded: httpResponse.value(forHTTPHeaderField: "X-Was-Refunded") == "true"
        )
        didEmitMetadata = true
        continuation.yield(.metadata(metadata))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if didEmitMetadata {
            receivedAudioData = true
            continuation.yield(.audioData(data))
        } else {
            // Accumulating a JSON response body
            jsonAccumulator.append(data)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                continuation.finish()
            } else {
                continuation.yield(.failed(error.localizedDescription))
                continuation.finish()
            }
            return
        }

        if didEmitMetadata {
            // Streaming path completed successfully
            // Build a minimal completed asset — the caller will construct the full asset from metadata + cached data
            let asset = DiscoveryVoiceoverAsset(
                discoveryId: discoveryId,
                status: .ready,
                audioURL: nil,
                provider: nil,
                ttsModel: ttsModel,
                voiceModelId: voiceModelId,
                fileName: nil,
                fileExtension: nil,
                requestedAt: nil,
                updatedAt: Date(),
                errorReason: nil,
                wasExistingResponse: false,
                wasRefunded: false
            )
            continuation.yield(.completed(asset))
        } else {
            // JSON path — server returned JSON instead of streaming audio.
            // Parse the response to determine if this is an existing ready voiceover,
            // an already-processing voiceover, or an error.
            handleJSONResponse()
        }
        continuation.finish()
    }

    /// Parses a JSON response from the server when it doesn't stream audio.
    /// This happens when the voiceover already exists (ready or processing).
    private func handleJSONResponse() {
        guard let json = try? JSONSerialization.jsonObject(with: jsonAccumulator) as? [String: Any] else {
            continuation.yield(.failed("Invalid server response"))
            return
        }

        let status = (json["status"] as? String)?.lowercased()
        let creditBalance = json["credit_balance"] as? Int
        let wasExisting = json["was_existing"] as? Bool ?? false
        let wasRefunded = json["was_refunded"] as? Bool ?? false
        let errorReason = json["error_reason"] as? String

        if status == "ready" {
            // Voiceover already exists and is ready — emit as completed
            let audioURLString = json["audio_url"] as? String
            let fileName = json["file_name"] as? String
            let fileExtension = json["file_extension"] as? String
            let provider = json["provider"] as? String
            let serverTtsModel = json["tts_model"] as? String
            let serverVoiceModelId = json["voice_model_id"] as? String

            let asset = DiscoveryVoiceoverAsset(
                discoveryId: discoveryId,
                status: .ready,
                audioURL: audioURLString.flatMap { URL(string: $0) },
                provider: provider,
                ttsModel: serverTtsModel ?? ttsModel,
                voiceModelId: serverVoiceModelId ?? voiceModelId,
                fileName: fileName,
                fileExtension: fileExtension,
                requestedAt: nil,
                updatedAt: Date(),
                errorReason: nil,
                wasExistingResponse: wasExisting,
                wasRefunded: wasRefunded,
                creditBalance: creditBalance
            )
            continuation.yield(.completed(asset))
        } else if status == "processing" {
            // Voiceover is already being generated by another request.
            // Emit as completed with .processing status — the controller's polling
            // mechanism will track it to .ready.
            let asset = DiscoveryVoiceoverAsset(
                discoveryId: discoveryId,
                status: .processing,
                audioURL: nil,
                provider: nil,
                ttsModel: ttsModel,
                voiceModelId: voiceModelId,
                fileName: nil,
                fileExtension: nil,
                requestedAt: nil,
                updatedAt: Date(),
                errorReason: nil,
                wasExistingResponse: wasExisting,
                wasRefunded: wasRefunded,
                creditBalance: creditBalance
            )
            continuation.yield(.completed(asset))
        } else if status == "failed" {
            // Server-side failure
            continuation.yield(.failed(errorReason ?? "voiceover_failed"))
        } else {
            // Unknown status — check for error fields
            if let errorMessage = json["error"] as? String ?? json["message"] as? String {
                continuation.yield(.failed(errorMessage))
            } else {
                continuation.yield(.failed("Unexpected server response"))
            }
        }
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

private struct VoiceoverCountRow: Decodable {
    let id: Int64
}

private struct VoiceoverRequestBody: Encodable {
    let discovery_id: Int64
    let voice_model_id: String
    let tts_model: String
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
    let creditBalance: Int?

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
        case creditBalance = "credit_balance"
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
        ttsModel: String
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

    public func countUserVoiceovers() async -> Int {
        0
    }

    // Uses default protocol extension fallback
}
#endif
