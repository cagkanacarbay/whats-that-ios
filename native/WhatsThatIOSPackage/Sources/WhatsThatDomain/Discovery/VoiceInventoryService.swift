import Foundation

public protocol VoiceInventoryService: Sendable {
    func fetchVoiceOptions() async -> [VoiceModelOption]
    func fetchVoiceSampleURL(voiceName: String) async -> URL?
}
