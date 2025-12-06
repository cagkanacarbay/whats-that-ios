import Foundation
import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// Central container for all audio/voiceover-related services.
/// Created once at app launch and injected via environment.
@MainActor
public final class AudioServicesContainer: ObservableObject {
    
    // MARK: - Stores
    
    /// Queue, history, autoplay state for Audio Guides
    public let queueStore: AudioGuidesQueueStore
    
    /// Global playback speed (shared across all voiceover surfaces)
    public let speedStore: VoiceoverPlaybackSpeedStore
    
    /// Per-discovery playback position (display-only)
    public let progressStore: VoiceoverProgressStore
    
    /// Mini player visibility and height for scroll insets
    public let miniPlayerPresence: MiniPlayerPresenceStore
    
    /// Shared discovery cache
    public let discoveryStore: DiscoveryStore
    
    /// Audio file cache with in-flight tracking
    public let fileCache: VoiceoverFileCache
    
    /// Network connectivity monitor
    public let networkMonitor: NetworkMonitor
    
    /// User's voiceover preferences (voice model, auto-generate, etc.)
    public let preferencesStore: VoiceoverPreferencesStore
    
    // MARK: - Playback Controller
    
    /// Shared playback controller (created with container dependencies)
    public let playbackController: VoiceoverPlaybackController
    
    // MARK: - Init
    
    public init(
        repository: DiscoveryRepository,
        voiceoverRepository: DiscoveryVoiceoverRepository,
        defaults: UserDefaults = .standard
    ) {
        // Create stores
        self.queueStore = AudioGuidesQueueStore(defaults: defaults)
        self.speedStore = VoiceoverPlaybackSpeedStore(defaults: defaults)
        self.progressStore = VoiceoverProgressStore(defaults: defaults)
        self.miniPlayerPresence = MiniPlayerPresenceStore()
        self.discoveryStore = DiscoveryStore(repository: repository)
        self.fileCache = VoiceoverFileCache.shared
        self.networkMonitor = NetworkMonitor()
        self.preferencesStore = VoiceoverPreferencesStore()
        
        // Create playback controller with store references
        self.playbackController = VoiceoverPlaybackController(
            repository: voiceoverRepository,
            voiceoverCache: fileCache,
            preferencesStore: preferencesStore
        )
        
        // Wire up stores to controller
        playbackController.configure(
            queueStore: queueStore,
            speedStore: speedStore,
            progressStore: progressStore
        )
    }
}

// MARK: - Environment Key

private struct AudioServicesKey: EnvironmentKey {
    static let defaultValue: AudioServicesContainer? = nil
}

public extension EnvironmentValues {
    var audioServices: AudioServicesContainer? {
        get { self[AudioServicesKey.self] }
        set { self[AudioServicesKey.self] = newValue }
    }
}

public extension View {
    func audioServices(_ container: AudioServicesContainer) -> some View {
        environment(\.audioServices, container)
    }
}
