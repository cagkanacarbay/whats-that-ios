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
    
    /// Credit balance store (optional, for showing credits in confirmation dialogs)
    public let creditBalanceStore: CreditBalanceStore?
    
    // MARK: - Playback Controller
    
    /// Shared playback controller (created with container dependencies)
    public let playbackController: VoiceoverPlaybackController
    
    // MARK: - Toast State
    
    /// Queue of toasts to show when generation completes (stacked card effect)
    @Published public var pendingGenerationToasts: [GenerationCompleteToast] = []
    
    /// Convenience property for the current (frontmost) toast
    public var pendingGenerationToast: GenerationCompleteToast? {
        pendingGenerationToasts.first
    }
    
    /// Number of pending toasts (for stacked card visual)
    public var pendingToastCount: Int {
        pendingGenerationToasts.count
    }
    
    // MARK: - Init
    
    public init(
        discoveryStore: DiscoveryStore,
        voiceoverRepository: DiscoveryVoiceoverRepository,
        creditBalanceStore: CreditBalanceStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        // Create stores
        self.queueStore = AudioGuidesQueueStore(defaults: defaults)
        self.speedStore = VoiceoverPlaybackSpeedStore(defaults: defaults)
        self.progressStore = VoiceoverProgressStore(defaults: defaults)
        self.miniPlayerPresence = MiniPlayerPresenceStore()
        self.discoveryStore = discoveryStore
        self.fileCache = VoiceoverFileCache.shared
        self.networkMonitor = NetworkMonitor()
        self.preferencesStore = VoiceoverPreferencesStore()
        self.creditBalanceStore = creditBalanceStore
        
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
            progressStore: progressStore,
            discoveryStore: discoveryStore,
            miniPlayerPresence: miniPlayerPresence
        )
        
        // Wire up generation complete callback to show toast
        playbackController.onGenerationComplete = { [weak self] discovery in
            self?.showGenerationCompleteToast(for: discovery)
        }
        
        // Wire up credit balance sync callback
        playbackController.onCreditBalanceUpdated = { [weak self] serverBalance in
            guard let creditStore = self?.creditBalanceStore else { return }
            Task {
                _ = await creditStore.set(serverBalance)
            }
        }
    }
    
    // MARK: - Toast Actions
    
    /// Shows a generation complete toast for the given discovery (adds to stack)
    public func showGenerationCompleteToast(for discovery: DiscoverySummary) {
        // Avoid duplicates
        guard !pendingGenerationToasts.contains(where: { $0.discovery.id == discovery.id }) else { return }
        pendingGenerationToasts.append(GenerationCompleteToast(discovery: discovery))
    }
    
    /// Dismisses the current (frontmost) toast, revealing the next one
    public func dismissGenerationToast() {
        guard !pendingGenerationToasts.isEmpty else { return }
        pendingGenerationToasts.removeFirst()
    }
    
    /// Handles "Play Now" action from toast
    public func handleToastPlayNow() {
        guard let toast = pendingGenerationToast else { return }
        playbackController.togglePlayback(for: toast.discovery)
        dismissGenerationToast()
    }
    
    /// Handles "Play Next" action from toast
    public func handleToastPlayNext() {
        guard let toast = pendingGenerationToast else { return }
        queueStore.playNext(toast.discovery.id)
        dismissGenerationToast()
    }
    
    /// Handles "Add to Queue" action from toast
    public func handleToastAddToQueue() {
        guard let toast = pendingGenerationToast else { return }
        queueStore.addToEnd(toast.discovery.id)
        dismissGenerationToast()
    }
    
    // MARK: - User Data Clearing
    
    /// Clears all user-specific audio/playback data. Called during sign-out.
    public func clearAllUserData() async {
        // Stop any active playback first
        playbackController.stop()
        
        // Clear all queue and progress state
        queueStore.clearAll()
        progressStore.clearAll()
        
        // Clear pending toasts
        pendingGenerationToasts.removeAll()
        
        // Clear cached audio files
        await fileCache.clearAll()
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
