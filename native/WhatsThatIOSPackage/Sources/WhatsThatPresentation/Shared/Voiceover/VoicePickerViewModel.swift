import Foundation
import SwiftUI
import AVFoundation
import WhatsThatDomain
import WhatsThatShared

@MainActor
public class VoicePickerViewModel: ObservableObject {
    @Published public var voices: [VoiceModelOption] = []
    @Published public var selectedVoiceId: String?
    @Published public var isAutoEnabled: Bool = true
    @Published public var isPlaying: Bool = false
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObserver: NSKeyValueObservation?
    
    private let loadVoiceoverPreferences: () async -> VoiceoverPreferences
    private let saveVoiceoverPreferences: (VoiceoverPreferences) async -> Void
    private let fetchVoiceOptions: () async -> [VoiceModelOption]
    private let fetchVoiceSampleURL: (String) async -> URL?
    
    public init(
        loadVoiceoverPreferences: @escaping () async -> VoiceoverPreferences,
        saveVoiceoverPreferences: @escaping (VoiceoverPreferences) async -> Void,
        fetchVoiceOptions: @escaping () async -> [VoiceModelOption],
        fetchVoiceSampleURL: @escaping (String) async -> URL?
    ) {
        self.loadVoiceoverPreferences = loadVoiceoverPreferences
        self.saveVoiceoverPreferences = saveVoiceoverPreferences
        self.fetchVoiceOptions = fetchVoiceOptions
        self.fetchVoiceSampleURL = fetchVoiceSampleURL
    }
    
    public func load() async {
        let options = await fetchVoiceOptions()
        
        // Define preferred order
        let sortOrder = ["Adrian", "Laura", "Ethan", "Sarah"]
        
        self.voices = options.sorted { v1, v2 in
            let index1 = sortOrder.firstIndex(of: v1.displayName) ?? Int.max
            let index2 = sortOrder.firstIndex(of: v2.displayName) ?? Int.max
            
            if index1 != index2 {
                return index1 < index2
            }
            return v1.displayName < v2.displayName
        }
        
        let prefs = await loadVoiceoverPreferences()
        self.isAutoEnabled = prefs.autoEnabled
        
        if !prefs.voiceModelId.isEmpty, options.contains(where: { $0.voiceModelId == prefs.voiceModelId }) {
            self.selectedVoiceId = prefs.voiceModelId
        } else if let first = options.first {
            self.selectedVoiceId = first.voiceModelId
            // Save default immediately so we have a valid state
            await saveCurrentPreferences()
        }
    }
    
    public func selectVoice(id: String) {
        guard selectedVoiceId != id else { return }
        selectedVoiceId = id
        
        Task {
            await saveCurrentPreferences()
            if isAutoEnabled {
                await playCurrentVoice()
            }
        }
    }
    
    public func toggleAutoPlay() {
        isAutoEnabled.toggle()
        Task {
            await saveCurrentPreferences()
        }
    }
    
    private func saveCurrentPreferences() async {
        guard let selectedVoiceId else { return }
        guard let voice = voices.first(where: { $0.voiceModelId == selectedVoiceId }) else { return }
        
        let prefs = VoiceoverPreferences(
            autoEnabled: isAutoEnabled,
            voiceModelId: voice.voiceModelId,
            ttsModel: voice.ttsModel
        )
        await saveVoiceoverPreferences(prefs)
    }
    
    public func playCurrentVoice() async {
        guard let selectedVoiceId else { return }
        guard let voice = voices.first(where: { $0.voiceModelId == selectedVoiceId }) else { return }
        
        // Stop existing
        stop()
        
        guard let url = await fetchVoiceSampleURL(voice.displayName) else {
            print("Could not get sample URL for \(voice.displayName)")
            return
        }
        
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        playerItem = item
        
        // Observe status to know when ready to play if needed, usually play() is enough
        statusObserver = item.observe(\.status, options: [.new, .old]) { [weak self] item, _ in
            guard let self else { return }
            if item.status == .readyToPlay {
                Task { @MainActor in
                    self.player?.play()
                    self.isPlaying = true
                }
            } else if item.status == .failed {
                Task { @MainActor in
                    self.isPlaying = false
                }
            }
        }
        
        // Watch for end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        
        player?.play()
        isPlaying = true
    }
    
    public func stop() {
        player?.pause()
        player = nil
        playerItem = nil
        statusObserver = nil // invalidate
        isPlaying = false
    }
    
    @objc private func playerDidFinishPlaying(note: NSNotification) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }
}
