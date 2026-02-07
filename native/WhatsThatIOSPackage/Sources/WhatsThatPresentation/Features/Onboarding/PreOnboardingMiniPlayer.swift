import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared

/// Simplified mini player for pre-onboarding sample discoveries.
/// Shows the currently playing discovery with basic playback controls.
struct PreOnboardingMiniPlayer: View {
    @ObservedObject var voiceoverController: VoiceoverPlaybackController
    let discoveries: [DiscoverySummary]
    @Binding var isDismissedByUser: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGFloat = 0
    private let dismissThreshold: CGFloat = 50

    private let artworkDiameter: CGFloat = 110
    private let backgroundHeight: CGFloat = 84
    private let progressLineWidth: CGFloat = 3

    private var discovery: DiscoverySummary? {
        voiceoverController.currentDiscovery
    }

    private var progress: Double {
        guard let duration = voiceoverController.duration, duration > 0 else { return 0 }
        return voiceoverController.position / duration
    }

    private var isPlaying: Bool {
        if case .playing = voiceoverController.playbackState { return true }
        return false
    }

    private var shouldShow: Bool {
        // Don't show if user explicitly dismissed
        if isDismissedByUser {
            return false
        }

        switch voiceoverController.playbackState {
        case .playing, .paused, .preparing:
            return discovery != nil
        default:
            return false
        }
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        Group {
            if shouldShow {
                ZStack(alignment: .leading) {
                    backgroundPill
                    contentArea
                    artworkWithProgressRing
                }
                .frame(height: artworkDiameter)
                .frame(maxWidth: UIDevice.isIPad ? IPadLayout.miniPlayerMaxWidth : .infinity, alignment: .center)
                .padding(.horizontal, BrandSpacing.medium)
                // Swipe-to-dismiss support
                .offset(y: dragOffset)
                .opacity(Double(1 - (dragOffset / (dismissThreshold * 2))))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.height > 0 {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > dismissThreshold {
                                pauseAndDismiss()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: voiceoverController.playbackState) { _, newState in
            // Reset dismissed state when user starts playing again
            if case .playing = newState {
                isDismissedByUser = false
            }
        }
    }

    private var backgroundPill: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(palette.surface.opacity(0.95))
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(palette.border, lineWidth: 0.5)
            )
            .frame(height: backgroundHeight)
            .padding(.leading, 20)
    }

    private var contentArea: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 108)

            VStack(spacing: 4) {
                // Title
                Text(discovery?.title ?? "Audio Guide")
                    .font(.adaptiveSystem(size: 16, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Controls row - centered in available space
                controlsRow
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.trailing, 16)
            .padding(.vertical, 10)
        }
        .frame(height: backgroundHeight)
        .padding(.leading, 20)
    }

    private var controlsRow: some View {
        HStack(spacing: 16) {
            // Back 5s
            Button(action: { voiceoverController.seek(by: -5) }) {
                Image(systemName: "gobackward.5")
                    .font(.adaptiveSystem(size: 18))
                    .foregroundColor(palette.textSecondary)
            }

            // Play/Pause
            Button(action: togglePlayPause) {
                ZStack {
                    Circle()
                        .fill(BrandColors.logo)
                        .frame(width: 40, height: 40)
                        .shadow(color: BrandColors.logo.opacity(0.4), radius: 4, y: 2)

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.adaptiveSystem(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            // Forward 5s
            Button(action: { voiceoverController.seek(by: 5) }) {
                Image(systemName: "goforward.5")
                    .font(.adaptiveSystem(size: 18))
                    .foregroundColor(palette.textSecondary)
            }
        }
    }

    private var artworkWithProgressRing: some View {
        ZStack {
            // Background for ring
            Circle()
                .fill(palette.background)
                .frame(width: artworkDiameter, height: artworkDiameter)

            // Track ring (open arc)
            Circle()
                .trim(from: 0.0, to: 0.8)
                .stroke(Color.black.opacity(0.3), style: StrokeStyle(lineWidth: progressLineWidth, lineCap: .round))
                .rotationEffect(Angle(degrees: 126))
                .frame(width: artworkDiameter, height: artworkDiameter)

            // Progress ring
            Circle()
                .trim(from: 0.0, to: progress * 0.8)
                .stroke(BrandColors.logo, style: StrokeStyle(lineWidth: progressLineWidth, lineCap: .round))
                .rotationEffect(Angle(degrees: 126))
                .frame(width: artworkDiameter, height: artworkDiameter)

            // Artwork image
            artworkImage
        }
        .padding(.leading, 0)
        .zIndex(1)
    }

    @ViewBuilder
    private var artworkImage: some View {
        let size = artworkDiameter - (progressLineWidth * 3)
        if let discovery = discovery,
           let imagePath = discovery.imagePath,
           let imageURL = URL(string: imagePath) {
            DiscoveryCachedImage(
                discoveryId: discovery.id,
                remoteURL: imageURL
            ) { phase in
                switch phase {
                case .success(let platformImage):
                    Image(uiImage: platformImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                case .loading, .empty, .failure:
                    placeholderArtwork(size: size)
                }
            }
            .id("artwork-\(discovery.id)-\(imagePath)")
        } else {
            placeholderArtwork(size: size)
        }
    }

    private func placeholderArtwork(size: CGFloat) -> some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: size, height: size)
    }

    private func togglePlayPause() {
        guard let discovery else { return }
        voiceoverController.togglePlayback(for: discovery)
    }

    private func pauseAndDismiss() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Mark as dismissed by user so it doesn't come back
        isDismissedByUser = true

        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = 200
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            voiceoverController.pause()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                dragOffset = 0
            }
        }
    }
}
