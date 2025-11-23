import Foundation

public actor VoiceoverPreferencesStore: Sendable {
    private enum Keys {
        static let autoEnabled = "voiceover.autoEnabled"
        static let voiceModelId = "voiceover.voiceModelId"
        static let ttsModel = "voiceover.ttsModel"
        static let prosodySpeed = "voiceover.prosody.speed"
        static let prosodyVolume = "voiceover.prosody.volume"
    }

    private let defaults: UserDefaults

    public init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func load(defaultVoiceModelId: String? = nil, defaultTtsModel: String = "s1") -> VoiceoverPreferences {
        let autoEnabled = defaults.object(forKey: Keys.autoEnabled) as? Bool ?? false
        let voiceModelId = defaults.string(forKey: Keys.voiceModelId) ?? defaultVoiceModelId ?? ""
        let ttsModel = defaults.string(forKey: Keys.ttsModel) ?? defaultTtsModel

        let storedSpeed = defaults.object(forKey: Keys.prosodySpeed) as? Double
        let storedVolume = defaults.object(forKey: Keys.prosodyVolume) as? Double

        let speed = clamp(storedSpeed, to: 0.5...2.0) ?? 1.0
        let volume = clamp(storedVolume, to: -20.0...20.0) ?? 0.0

        return VoiceoverPreferences(
            autoEnabled: autoEnabled,
            voiceModelId: voiceModelId,
            ttsModel: ttsModel,
            prosody: VoiceoverProsody(speed: speed, volume: volume)
        )
    }

    public func save(_ preferences: VoiceoverPreferences) {
        defaults.set(preferences.autoEnabled, forKey: Keys.autoEnabled)
        defaults.set(preferences.voiceModelId, forKey: Keys.voiceModelId)
        defaults.set(preferences.ttsModel, forKey: Keys.ttsModel)

        if let speed = clamp(preferences.prosody.speed, to: 0.5...2.0) {
            defaults.set(speed, forKey: Keys.prosodySpeed)
        } else {
            defaults.removeObject(forKey: Keys.prosodySpeed)
        }

        if let volume = clamp(preferences.prosody.volume, to: -20.0...20.0) {
            defaults.set(volume, forKey: Keys.prosodyVolume)
        } else {
            defaults.removeObject(forKey: Keys.prosodyVolume)
        }
    }

    public func reset() {
        defaults.removeObject(forKey: Keys.autoEnabled)
        defaults.removeObject(forKey: Keys.voiceModelId)
        defaults.removeObject(forKey: Keys.ttsModel)
        defaults.removeObject(forKey: Keys.prosodySpeed)
        defaults.removeObject(forKey: Keys.prosodyVolume)
    }

    private func clamp(_ value: Double?, to range: ClosedRange<Double>) -> Double? {
        guard let value else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
