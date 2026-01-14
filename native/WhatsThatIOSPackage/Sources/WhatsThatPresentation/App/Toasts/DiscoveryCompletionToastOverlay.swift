import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// Wrapper that observes DiscoverySessionManager to show discovery completion toast.
/// Also observes VoiceoverPlaybackController to track audio generation state.
struct DiscoveryCompletionToastOverlay: View {
    @ObservedObject var sessionManager = DiscoverySessionManager.shared
    @ObservedObject var audioServices: AudioServicesContainer
    @ObservedObject var miniPlayerPresence: MiniPlayerPresenceStore
    let onViewDiscovery: (Int64) -> Void
    let onGenerateAudio: (DiscoverySummary) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Mini player constants (from MiniPlayerView)
    // On iPad: artworkDiameter is 154, backgroundHeight is 118
    private var miniPlayerHeight: CGFloat {
        UIDevice.isIPad ? 154 : 110
    }
    
    private var miniPlayerBottomPadding: CGFloat {
        // Matches Mini Player bottom padding + gap
        UIDevice.isIPad ? 20 + 8 : 49 + 2
    }
    private var tabBarOffset: CGFloat {
        UIDevice.isIPad ? 24 : 49 + 8
    }
    private let toastMiniPlayerGap: CGFloat = 8
    
    private var isMiniPlayerVisible: Bool {
        // Check if mini player has been dismissed by user
        guard !miniPlayerPresence.isDismissed else { return false }
        guard audioServices.playbackController.currentDiscovery != nil else { return false }
        switch audioServices.playbackController.playbackState {
        case .idle, .failed:
            return false
        default:
            return true
        }
    }
    
    private var bottomPadding: CGFloat {
        isMiniPlayerVisible 
            ? miniPlayerBottomPadding + miniPlayerHeight + toastMiniPlayerGap
            : tabBarOffset
    }
    
    /// Compute audio button state for a discovery based on VoiceoverPlaybackController
    private func audioState(for discoveryId: Int64, wasGenerating: Bool) -> DiscoveryCompletionToastView.AudioButtonState {
        if let asset = audioServices.playbackController.assetStates[discoveryId] {
            switch asset.status {
            case .ready:
                return .ready
            case .processing:
                return .generating
            default:
                // If toast was created with generateAudioGuide=true but we don't have an asset yet,
                // assume it's still generating
                return wasGenerating ? .generating : .notGenerated
            }
        } else {
            // No asset tracked yet - if toast says we're generating, trust that
            return wasGenerating ? .generating : .notGenerated
        }
    }
    
    var body: some View {
        let toasts = sessionManager.pendingCompletionToasts
        let toastCount = toasts.count
        
        if let frontToast = toasts.first {
            let currentAudioState = audioState(
                for: frontToast.discovery.id,
                wasGenerating: frontToast.generateAudioGuide
            )
            
            DiscoveryCompletionToastView(
                toast: frontToast,
                onViewDiscovery: {
                    onViewDiscovery(frontToast.discovery.id)
                    sessionManager.dismissCompletionToast()
                },
                onPlayNow: {
                    // Start playback and dismiss toast
                    audioServices.playbackController.togglePlayback(for: frontToast.discovery)
                    sessionManager.dismissCompletionToast()
                },
                onPlayNext: {
                    // Add to queue as next and dismiss toast
                    audioServices.queueStore.playNext(frontToast.discovery.id)
                    sessionManager.dismissCompletionToast()
                },
                onAddToQueue: {
                    // Add to end of queue and dismiss toast
                    audioServices.queueStore.addToEnd(frontToast.discovery.id)
                    sessionManager.dismissCompletionToast()
                },
                onGenerateAudio: {
                    onGenerateAudio(frontToast.discovery)
                    // Don't dismiss - let user see generating state
                },
                onDismiss: {
                    sessionManager.dismissCompletionToast()
                },
                audioState: currentAudioState
            )
            // Badge showing remaining toast count (if more than 1)
            .overlay(alignment: .trailing) {
                if toastCount > 1 {
                    pendingCountBadge(count: toastCount)
                        .offset(x: 4)
                }
            }
            .id(frontToast.id)
            .padding(.bottom, bottomPadding)
            // iPad: Constrain width and center, slightly narrower than mini player
            .frame(maxWidth: UIDevice.isIPad ? IPadLayout.toastMaxWidth : .infinity)
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: frontToast.id)
            // Also animate when audio state changes
            .animation(.easeInOut(duration: 0.2), value: currentAudioState == .ready)
            .zIndex(9) // Below audio generation toast (10)
        }
    }
    
    @ViewBuilder
    private func pendingCountBadge(count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .frame(minWidth: 22, minHeight: 22)
            .background(
                Circle()
                    .fill(BrandColors.logo)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}
