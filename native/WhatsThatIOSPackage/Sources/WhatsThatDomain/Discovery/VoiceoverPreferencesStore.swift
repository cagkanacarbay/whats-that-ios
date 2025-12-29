import Foundation

public actor VoiceoverPreferencesStore: Sendable {
    /// Default voice: Adrian (first in sort order)
    public static let defaultVoiceModelId = "bf322df2096a46f18c579d0baa36f41d"
    public static let defaultTtsModel = "s1"

    private let defaults: UserDefaults
    private var currentUserId: String?
    
    public init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
    
    // MARK: - User Binding
    
    /// Binds the store to a specific user. Keys become prefixed with userId.
    public func bind(to userId: String) {
        self.currentUserId = userId
    }
    
    /// Unbinds from the current user. Does NOT delete existing data.
    public func unbind() {
        self.currentUserId = nil
    }
    
    // MARK: - User-Keyed Storage Keys
    
    private func key(_ baseKey: String) -> String {
        guard let userId = currentUserId else {
            return baseKey  // Fallback to non-prefixed key if not bound
        }
        return "voiceover.\(userId).\(baseKey)"
    }
    
    // MARK: - Load / Save / Reset

    public func load(defaultVoiceModelId: String? = nil, defaultTtsModel: String = "s1") -> VoiceoverPreferences {
        let autoEnabled = defaults.object(forKey: key("autoEnabled")) as? Bool ?? true
        // Use saved voiceModelId, then passed default (if non-empty), then Adrian as ultimate fallback
        let savedVoiceModelId = defaults.string(forKey: key("voiceModelId"))
        let effectiveDefault = (defaultVoiceModelId?.isEmpty == false) ? defaultVoiceModelId : nil
        let voiceModelId = savedVoiceModelId 
            ?? effectiveDefault 
            ?? Self.defaultVoiceModelId
        let ttsModel = defaults.string(forKey: key("ttsModel")) ?? defaultTtsModel

        return VoiceoverPreferences(
            autoEnabled: autoEnabled,
            voiceModelId: voiceModelId,
            ttsModel: ttsModel
        )
    }

    public func save(_ preferences: VoiceoverPreferences) {
        defaults.set(preferences.autoEnabled, forKey: key("autoEnabled"))
        defaults.set(preferences.voiceModelId, forKey: key("voiceModelId"))
        defaults.set(preferences.ttsModel, forKey: key("ttsModel"))
    }

    public func reset() {
        defaults.removeObject(forKey: key("autoEnabled"))
        defaults.removeObject(forKey: key("voiceModelId"))
        defaults.removeObject(forKey: key("ttsModel"))
    }
}
