import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// Wrapper that observes AudioServicesContainer to show toast when audio guide generation completes.
struct AudioGuideCompletionToastOverlay: View {
    @ObservedObject var audioServices: AudioServicesContainer
    @ObservedObject var miniPlayerPresence: MiniPlayerPresenceStore
    @Environment(\.colorScheme) private var colorScheme
    
    // Mini player constants (from MiniPlayerView)
    private var miniPlayerHeight: CGFloat {
        UIDevice.isIPad ? 154 : 110
    }
    
    private var miniPlayerBottomPadding: CGFloat {
        UIDevice.isIPad ? 49 + 12 : 49 + 2
    }
    // Tab bar height + spacing
    private let tabBarOffset: CGFloat = 49 + 8
    // Small gap between toast and mini player
    private let toastMiniPlayerGap: CGFloat = 8
    
    private var isMiniPlayerVisible: Bool {
        // Check if mini player has been dismissed by user
        guard !miniPlayerPresence.isDismissed else { return false }
        guard audioServices.playbackController.currentDiscovery != nil else { return false }
        // Check if playback state is active (not idle or failed)
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
    
    var body: some View {
        let toasts = audioServices.pendingGenerationToasts
        let toastCount = toasts.count
        
        if let frontToast = toasts.first {
            GenerationCompleteToastView(
                toast: frontToast,
                onPlayNow: { audioServices.handleToastPlayNow() },
                onPlayNext: { audioServices.handleToastPlayNext() },
                onAddToQueue: { audioServices.handleToastAddToQueue() },
                onDismiss: { audioServices.dismissGenerationToast() }
            )
            // Badge showing remaining toast count (if more than 1)
            .overlay(alignment: .trailing) {
                if toastCount > 1 {
                    pendingCountBadge(count: toastCount)
                        .offset(x: 4)
                }
            }
            // Force view refresh when toast changes to update image and content
            .id(frontToast.id)
            .padding(.bottom, bottomPadding)
            // iPad: Constrain width and center
            .frame(maxWidth: UIDevice.isIPad ? IPadLayout.toastMaxWidth : .infinity)
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: frontToast.id)
            .zIndex(10)
        }
    }
    
    /// Badge showing how many toasts are pending
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
