import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared

/// An invisible view that pre-compiles the DiscoveryDetailOverlayView hierarchy.
///
/// SwiftUI compiles view bodies lazily on first render, which can cause animation jank
/// when complex views like the discovery detail overlay are first displayed. This warmup
/// view renders the full overlay hierarchy offscreen on app launch, forcing SwiftUI to
/// compile it before the user taps a discovery card.
///
/// Usage: Add this view to your container with `.allowsHitTesting(false)` and `.zIndex(-1)`,
/// then remove it after a short delay (100ms) once warmup is complete.
struct DiscoveryDetailWarmupView: View {
    let voiceoverController: VoiceoverPlaybackController
    let backgroundColor: Color
    let colorScheme: ColorScheme

    // State to trigger warmup animation
    @State private var animationProgress: CGFloat = 0

    // Use actual screen dimensions to ensure proper geometry calculations
    private var screenBounds: CGRect { UIScreen.main.bounds }

    // Create a minimal dummy discovery for warmup
    private var dummyDiscovery: DiscoverySummary {
        DiscoverySummary(
            id: -1,
            title: "Warmup",
            highlight: "Warmup",
            capturedAt: Date()
        )
    }

    // Create a dummy snapshot that animates from 0 to 1 progress
    private func warmupSnapshot(progress: CGFloat) -> DiscoveryDetailOverlaySnapshot {
        let cardWidth = screenBounds.width * 0.45
        let cardHeight = cardWidth * 1.2
        let startFrame = CGRect(
            x: (screenBounds.width - cardWidth) / 2,
            y: (screenBounds.height - cardHeight) / 3,
            width: cardWidth,
            height: cardHeight
        )

        var snapshot = DiscoveryDetailOverlaySnapshot()
        snapshot.phase = progress < 1 ? .animatingIn : .presented
        snapshot.context = DiscoveryDetailContext(
            sessionId: UUID(),
            discovery: dummyDiscovery,
            imageURL: nil,
            startFrame: startFrame,
            placeholderImage: nil,
            cardAspectRatio: 1.2
        )
        snapshot.progress = progress
        snapshot.isContentReady = progress >= 1
        snapshot.contentOpacity = progress >= 1 ? 1 : 0
        return snapshot
    }

    var body: some View {
        let snapshot = warmupSnapshot(progress: animationProgress)

        // Render the full overlay view hierarchy offscreen to force compilation.
        // We use actual screen dimensions and position it far offscreen rather than
        // using opacity(0) with a tiny frame, which SwiftUI might optimize away.
        DiscoveryDetailOverlayView(
            snapshot: snapshot,
            destinationFrame: snapshot.context?.startFrame ?? .zero,
            backgroundColor: backgroundColor,
            colorScheme: colorScheme,
            voiceoverController: voiceoverController,
            onClose: {},
            deletingDiscoveryId: nil,
            isDeletingDiscovery: false,
            onDelete: nil,
            onShowOptions: nil,
            onOpenAudioGuide: nil,
            onScrollContentOffsetChanged: { _ in }
        )
        .frame(width: screenBounds.width, height: screenBounds.height)
        .offset(x: screenBounds.width * 2) // Position far offscreen to the right
        .accessibilityHidden(true)
        .onAppear {
            // Trigger a warmup animation to exercise the animation system.
            // Use the same timing curve as the actual hero animation.
            withAnimation(.timingCurve(0.33, 1.0, 0.68, 1.0, duration: 0.3)) {
                animationProgress = 1
            }
        }
    }
}
