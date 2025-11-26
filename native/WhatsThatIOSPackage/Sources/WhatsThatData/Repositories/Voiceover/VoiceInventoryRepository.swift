import Foundation
import WhatsThatDomain

#if USE_REMOTE_DEPS && canImport(Supabase)
import OSLog
import Supabase

private let voiceInventoryLogger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "VoiceInventoryRepository"
)

public actor VoiceInventoryRepository: VoiceInventoryService {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func fetchVoiceOptions() async -> [VoiceModelOption] {
        do {
            let builder = try client.rpc("get_voice_options", params: EmptyParams())
            let response: PostgrestResponse<[VoiceInventoryRow]> = try await builder.execute()
            return response.value.map {
                VoiceModelOption(
                    voiceModelId: $0.voice_model_id,
                    displayName: $0.display_name,
                    ttsModel: $0.tts_model ?? "s1"
                )
            }
        } catch {
            voiceInventoryLogger.error("Failed to fetch voice inventory: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func fetchVoiceSampleURL(voiceName: String) async -> URL? {
        do {
            // Path: onboarding/<DisplayName>.mp3
            // e.g. onboarding/Adrian.mp3
            let path = "onboarding/\(voiceName.capitalized).mp3"
            let url = try await client.storage
                .from("voiceovers")
                .createSignedURL(path: path, expiresIn: 3600)
            return url
        } catch {
            voiceInventoryLogger.error("Failed to sign sample URL for \(voiceName): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

private struct EmptyParams: Encodable {}

private struct VoiceInventoryRow: Decodable {
    let voice_model_id: String
    let display_name: String
    let tts_model: String?
}

#else
public actor VoiceInventoryRepository: VoiceInventoryService {
    public init() {}
    public func fetchVoiceOptions() async -> [VoiceModelOption] { [] }
    public func fetchVoiceSampleURL(voiceName: String) async -> URL? { nil }
}
#endif
