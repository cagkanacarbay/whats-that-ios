import Foundation
import WhatsThatDomain

@MainActor
final class VoiceoverSettingsViewModel: ObservableObject {
    @Published var voiceOptions: [VoiceModelOption] = []
    @Published var preferences: VoiceoverPreferences
    @Published var isLoading = false

    private let loadPreferences: () async -> VoiceoverPreferences
    private let savePreferences: (VoiceoverPreferences) async -> Void
    private let fetchVoiceOptions: () async -> [VoiceModelOption]

    init(
        initialPreferences: VoiceoverPreferences,
        loadPreferences: @escaping () async -> VoiceoverPreferences,
        savePreferences: @escaping (VoiceoverPreferences) async -> Void,
        fetchVoiceOptions: @escaping () async -> [VoiceModelOption]
    ) {
        self.preferences = initialPreferences
        self.loadPreferences = loadPreferences
        self.savePreferences = savePreferences
        self.fetchVoiceOptions = fetchVoiceOptions
    }

    func load() async {
        isLoading = true
        let fetchedOptions = await fetchVoiceOptions()
        let stored = await loadPreferences()
        await MainActor.run {
            voiceOptions = fetchedOptions
            var resolved = stored
            if resolved.voiceModelId.isEmpty, let first = fetchedOptions.first {
                resolved.voiceModelId = first.voiceModelId
                resolved.ttsModel = first.ttsModel
            }
            preferences = resolved
        }
        await persist()
        isLoading = false
    }

    func selectVoice(withId voiceModelId: String) async {
        guard let option = voiceOptions.first(where: { $0.voiceModelId == voiceModelId }) else { return }
        preferences.voiceModelId = option.voiceModelId
        preferences.ttsModel = option.ttsModel
        await persist()
    }

    func updateAutoEnabled(_ enabled: Bool) async {
        preferences.autoEnabled = enabled
        await persist()
    }

    private func persist() async {
        await savePreferences(preferences)
    }
}
