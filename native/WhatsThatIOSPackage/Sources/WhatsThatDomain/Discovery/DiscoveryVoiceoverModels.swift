import Foundation

public enum DiscoveryVoiceoverStatus: Equatable, Sendable {
    case none
    case processing
    case ready
    case failed
    case missing
}

public struct DiscoveryVoiceoverAsset: Equatable, Sendable {
    public let discoveryId: Int64
    public let status: DiscoveryVoiceoverStatus
    public let audioURL: URL?
    public let provider: String?
    public let ttsModel: String?
    public let voiceModelId: String?
    public let fileName: String?
    public let fileExtension: String?
    public let requestedAt: Date?
    public let updatedAt: Date?
    public let errorReason: String?
    public let wasExistingResponse: Bool
    public let wasRefunded: Bool
    public let creditBalance: Int?
    public var modelIdentifier: String? { voiceModelId }

    public init(
        discoveryId: Int64,
        status: DiscoveryVoiceoverStatus,
        audioURL: URL?,
        provider: String?,
        ttsModel: String?,
        voiceModelId: String?,
        fileName: String?,
        fileExtension: String?,
        requestedAt: Date?,
        updatedAt: Date?,
        errorReason: String?,
        wasExistingResponse: Bool,
        wasRefunded: Bool,
        creditBalance: Int? = nil
    ) {
        self.discoveryId = discoveryId
        self.status = status
        self.audioURL = audioURL
        self.provider = provider
        self.ttsModel = ttsModel
        self.voiceModelId = voiceModelId
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.requestedAt = requestedAt
        self.updatedAt = updatedAt
        self.errorReason = errorReason
        self.wasExistingResponse = wasExistingResponse
        self.wasRefunded = wasRefunded
        self.creditBalance = creditBalance
    }
}

public protocol DiscoveryVoiceoverRepository: Sendable {
    func fetchVoiceovers(for discoveryIds: [Int64]) async -> [DiscoveryVoiceoverAsset]
    func requestVoiceover(for discoveryId: Int64,
                         voiceModelId: String,
                         ttsModel: String) async -> DiscoveryVoiceoverAsset
    
    /// Counts how many voiceovers the current user has (for intro tracker sync).
    /// Returns 0 if count cannot be determined.
    func countUserVoiceovers() async -> Int
}

public struct VoiceModelOption: Equatable, Sendable {
    public let voiceModelId: String
    public let displayName: String
    public let ttsModel: String

    public init(voiceModelId: String, displayName: String, ttsModel: String) {
        self.voiceModelId = voiceModelId
        self.displayName = displayName
        self.ttsModel = ttsModel
    }
}

public struct VoiceoverPreferences: Equatable, Sendable {
    public var autoEnabled: Bool
    public var voiceModelId: String
    public var ttsModel: String

    public init(
        autoEnabled: Bool,
        voiceModelId: String,
        ttsModel: String
    ) {
        self.autoEnabled = autoEnabled
        self.voiceModelId = voiceModelId
        self.ttsModel = ttsModel
    }
}
