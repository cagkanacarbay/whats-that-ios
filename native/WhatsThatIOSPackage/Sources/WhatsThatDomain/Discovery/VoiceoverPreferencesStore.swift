import Foundation

public actor VoiceoverPreferencesStore: Sendable {
    private enum Keys {
        static let autoEnabled = "voiceover.autoEnabled"
        static let voiceModelId = "voiceover.voiceModelId"
        static let ttsModel = "voiceover.ttsModel"
    }

    private let defaults: UserDefaults

    public init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func load(defaultVoiceModelId: String? = nil, defaultTtsModel: String = "s1") -> VoiceoverPreferences {
        let autoEnabled = defaults.object(forKey: Keys.autoEnabled) as? Bool ?? false
        let voiceModelId = defaults.string(forKey: Keys.voiceModelId) ?? defaultVoiceModelId ?? ""
        let ttsModel = defaults.string(forKey: Keys.ttsModel) ?? defaultTtsModel

        return VoiceoverPreferences(
            autoEnabled: autoEnabled,
            voiceModelId: voiceModelId,
            ttsModel: ttsModel
        )
    }

    public func save(_ preferences: VoiceoverPreferences) {
        defaults.set(preferences.autoEnabled, forKey: Keys.autoEnabled)
        defaults.set(preferences.voiceModelId, forKey: Keys.voiceModelId)
        defaults.set(preferences.ttsModel, forKey: Keys.ttsModel)
    }

    public func reset() {
        defaults.removeObject(forKey: Keys.autoEnabled)
        defaults.removeObject(forKey: Keys.voiceModelId)
        defaults.removeObject(forKey: Keys.ttsModel)
    }
}
