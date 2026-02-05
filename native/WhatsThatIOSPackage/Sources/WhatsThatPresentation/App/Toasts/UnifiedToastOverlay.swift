import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// Unified toast overlay that coordinates discovery completion and audio guide toasts.
/// Shows one toast at a time with a combined count badge when multiple toasts exist.
struct UnifiedToastOverlay: View {
    @ObservedObject var audioServices: AudioServicesContainer
    @ObservedObject var miniPlayerPresence: MiniPlayerPresenceStore
    @ObservedObject var sessionManager = DiscoverySessionManager.shared
    let onViewDiscovery: (Int64) -> Void
    let onGenerateAudio: (DiscoverySummary) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Layout Constants
    
    private var miniPlayerHeight: CGFloat {
        UIDevice.isIPad ? 168 : 110
    }
    
    private var miniPlayerBottomPadding: CGFloat {
        UIDevice.isIPad ? 20 + 8 : 49 + 2
    }
    
    private var tabBarOffset: CGFloat {
        UIDevice.isIPad ? 24 : 49 + 8
    }
    
    private let toastMiniPlayerGap: CGFloat = 8
    
    private var isMiniPlayerVisible: Bool {
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
    
    // MARK: - Combined Toast State
    
    /// Which type of toast to show (audio guide toasts take priority)
    private enum FrontToastType {
        case audioGuide(GenerationCompleteToast)
        case discovery(DiscoveryCompletionToast)
    }
    
    /// Get the front toast (audio guide priority) and total count
    private var toastState: (front: FrontToastType?, totalCount: Int) {
        let audioToasts = audioServices.pendingGenerationToasts
        let discoveryToasts = sessionManager.pendingCompletionToasts
        let total = audioToasts.count + discoveryToasts.count
        
        // Audio guide toasts take priority (more immediately actionable)
        if let audioToast = audioToasts.first {
            return (.audioGuide(audioToast), total)
        } else if let discoveryToast = discoveryToasts.first {
            return (.discovery(discoveryToast), total)
        }
        return (nil, 0)
    }
    
    // MARK: - Audio State Helper
    
    private func audioState(for discoveryId: Int64, wasGenerating: Bool) -> DiscoveryCompletionToastView.AudioButtonState {
        if let asset = audioServices.playbackController.assetStates[discoveryId] {
            switch asset.status {
            case .ready:
                return .ready
            case .processing:
                return .generating
            case .failed:
                // Generation failed - show retry button
                return .notGenerated
            default:
                return wasGenerating ? .generating : .notGenerated
            }
        }
        return wasGenerating ? .generating : .notGenerated
    }
    
    // MARK: - Body
    
    var body: some View {
        let (front, totalCount) = toastState
        
        if let frontToast = front {
            Group {
                switch frontToast {
                case .audioGuide(let toast):
                    audioGuideToastContent(toast: toast)
                case .discovery(let toast):
                    discoveryToastContent(toast: toast)
                }
            }
            // Unified badge showing combined count (top-right corner)
            .overlay(alignment: .topTrailing) {
                if totalCount > 1 {
                    pendingCountBadge(count: totalCount)
                        .offset(x: -8, y: -8)
                }
            }
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: UIDevice.isIPad ? IPadLayout.toastMaxWidth : .infinity)
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.opacity)
            .zIndex(10)
        }
    }
    
    // MARK: - Toast Content Views
    
    @ViewBuilder
    private func audioGuideToastContent(toast: GenerationCompleteToast) -> some View {
        GenerationCompleteToastView(
            toast: toast,
            onPlayNow: { audioServices.handleToastPlayNow() },
            onPlayNext: { audioServices.handleToastPlayNext() },
            onAddToQueue: { audioServices.handleToastAddToQueue() },
            onDismiss: { audioServices.dismissGenerationToast() }
        )
        .id("audio-\(toast.id)")
        .animation(.easeInOut(duration: 0.25), value: toast.id)
    }
    
    @ViewBuilder
    private func discoveryToastContent(toast: DiscoveryCompletionToast) -> some View {
        let currentAudioState = audioState(
            for: toast.discovery.id,
            wasGenerating: toast.generateAudioGuide
        )
        
        DiscoveryCompletionToastView(
            toast: toast,
            onViewDiscovery: {
                onViewDiscovery(toast.discovery.id)
                sessionManager.dismissCompletionToast()
            },
            onPlayNow: {
                audioServices.playbackController.togglePlayback(for: toast.discovery)
                sessionManager.dismissCompletionToast()
            },
            onPlayNext: {
                audioServices.queueStore.playNext(toast.discovery.id)
                sessionManager.dismissCompletionToast()
            },
            onAddToQueue: {
                audioServices.queueStore.addToEnd(toast.discovery.id)
                sessionManager.dismissCompletionToast()
            },
            onGenerateAudio: {
                onGenerateAudio(toast.discovery)
            },
            onDismiss: {
                sessionManager.dismissCompletionToast()
            },
            audioState: currentAudioState
        )
        .id("discovery-\(toast.id)")
        .animation(.easeInOut(duration: 0.25), value: toast.id)
        .animation(.easeInOut(duration: 0.2), value: currentAudioState == .ready)
    }
    
    // MARK: - Badge
    
    @ViewBuilder
    private func pendingCountBadge(count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: UIDevice.isIPad ? 18 : 12, weight: .bold))
            .foregroundColor(.white)
            .frame(minWidth: UIDevice.isIPad ? 32 : 22, minHeight: UIDevice.isIPad ? 32 : 22)
            .background(
                Circle()
                    .fill(BrandColors.logo)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}
