import SwiftUI
import WhatsThatDomain

/// Container for post-purchase configuration closures.
/// Used to pass voiceover and IPOP preference closures through the environment
/// so that CreditsView can show the post-purchase configuration flow from anywhere.
public final class PostPurchaseConfigProvider: ObservableObject {
    public let loadVoiceoverPreferences: () async -> VoiceoverPreferences
    public let saveVoiceoverPreferences: (VoiceoverPreferences) async -> Void
    public let fetchVoiceOptions: () async -> [VoiceModelOption]
    public let fetchVoiceSampleURL: (String) async -> URL?
    public let loadIPoPPreferences: () async -> IPoPPreferences?
    public let saveIPoPPreferences: (IPoPPreferences) async -> Void

    public init(
        loadVoiceoverPreferences: @escaping () async -> VoiceoverPreferences,
        saveVoiceoverPreferences: @escaping (VoiceoverPreferences) async -> Void,
        fetchVoiceOptions: @escaping () async -> [VoiceModelOption],
        fetchVoiceSampleURL: @escaping (String) async -> URL?,
        loadIPoPPreferences: @escaping () async -> IPoPPreferences?,
        saveIPoPPreferences: @escaping (IPoPPreferences) async -> Void
    ) {
        self.loadVoiceoverPreferences = loadVoiceoverPreferences
        self.saveVoiceoverPreferences = saveVoiceoverPreferences
        self.fetchVoiceOptions = fetchVoiceOptions
        self.fetchVoiceSampleURL = fetchVoiceSampleURL
        self.loadIPoPPreferences = loadIPoPPreferences
        self.saveIPoPPreferences = saveIPoPPreferences
    }
}

// MARK: - Environment Key

private struct PostPurchaseConfigKey: EnvironmentKey {
    static let defaultValue: PostPurchaseConfigProvider? = nil
}

public extension EnvironmentValues {
    var postPurchaseConfig: PostPurchaseConfigProvider? {
        get { self[PostPurchaseConfigKey.self] }
        set { self[PostPurchaseConfigKey.self] = newValue }
    }
}
