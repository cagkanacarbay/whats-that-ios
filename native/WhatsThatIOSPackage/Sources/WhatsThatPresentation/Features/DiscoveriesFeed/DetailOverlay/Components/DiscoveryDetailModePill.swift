import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// Text/Audio mode switcher pill for Discovery Detail view.
/// Mirrors the styling of the pill in Audio Guides HeroPlayerView.
/// Visible only when the current discovery is the one playing/paused in the audio player.
struct DiscoveryDetailModePill: View {
    let discovery: DiscoverySummary
    let onAudioSelected: () -> Void
    
    @ObservedObject private var controller: VoiceoverPlaybackController
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        discovery: DiscoverySummary,
        controller: VoiceoverPlaybackController,
        onAudioSelected: @escaping () -> Void
    ) {
        self.discovery = discovery
        self._controller = ObservedObject(initialValue: controller)
        self.onAudioSelected = onAudioSelected
    }
    
    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }
    
    /// Determines if the pill should be visible based on playback state.
    /// Rules:
    /// - Visible only when: discovery.id matches currentDiscovery.id AND player is playing/paused
    /// - Hidden for all other discoveries and when playback is idle, stopped, or failed
    var shouldShow: Bool {
        guard let currentDiscovery = controller.currentDiscovery,
              currentDiscovery.id == discovery.id else {
            return false
        }
        
        switch controller.playbackState {
        case .playing, .paused:
            return true
        case .idle, .failed, .preparing:
            return false
        }
    }
    
    var body: some View {
        if shouldShow {
            pillContent
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
    
    private var pillContent: some View {
        HStack(spacing: 0) {
            // Text button - selected (we're on the text/detail side)
            Text("Text")
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 80, height: 32)
                .foregroundColor(BrandColors.logo)
                .background(
                    Capsule()
                        .fill(palette.surface)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
            
            // Audio button - tap to switch to Audio Guides tab
            Button(action: onAudioSelected) {
                Text("Audio")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(width: 80, height: 32)
                    .foregroundColor(palette.textPrimary)  // Changed from textSecondary for better visibility
            }
        }
        .padding(2)
        .background(.ultraThinMaterial)  // Frosted glass effect for visibility over any image
        .clipShape(Capsule())
    }
}
