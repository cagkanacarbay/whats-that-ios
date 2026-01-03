import SwiftUI
import WhatsThatDomain

/// Wrapper view that properly observes VoiceoverPlaybackController to reactively show/hide the mini player.
/// This solves the issue where reading controller properties via computed properties doesn't trigger SwiftUI re-renders.
struct MiniPlayerVisibilityWrapper<Content: View>: View {
    @ObservedObject var controller: VoiceoverPlaybackController
    @ObservedObject var miniPlayerPresence: MiniPlayerPresenceStore
    let isAudioGuidesTab: Bool
    let audioGuidesMode: AudioGuidesDisplayMode
    let activeOverlayPhase: DiscoveryCreationPhase?
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        if shouldShow {
            content()
                .animation(.easeInOut(duration: 0.25), value: shouldShow)
                .onAppear {
                    miniPlayerPresence.updateVisibility(true)
                }
        }
    }
    
    private var shouldShow: Bool {
        // FIRST: Check if visibility has been explicitly disabled
        // This allows other views (like DiscoveryDetailOverlayView) to hide the global player
        guard miniPlayerPresence.isVisible else { return false }
        
        // Must have something playing
        guard controller.currentDiscovery != nil else { return false }
        
        // Only show in active playback states
        switch controller.playbackState {
        case .idle, .failed:
            return false
        default:
            break
        }
        
        // Audio Guides: show in list mode, hide in hero mode (hero has its own full player)
        if isAudioGuidesTab {
            return audioGuidesMode == .list
        }
        
        // Hide during capture/selection/confirmation stages of the creation overlay
        if let phase = activeOverlayPhase {
            switch phase {
            case .capturingInitial, .capturingRetake, .selectingInitial, .selectingRetake, .confirming, .requestingPermissions:
                return false
            case .analyzing, .idle, .cancelled, .error:
                break
            }
        }
        
        return true
    }
}
