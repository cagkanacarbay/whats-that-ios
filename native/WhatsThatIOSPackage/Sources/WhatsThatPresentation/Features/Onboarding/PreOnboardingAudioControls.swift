import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// Simplified audio controls for pre-onboarding sample discoveries.
/// Shows a play/pause button without credits, queue, or generation features.
struct PreOnboardingAudioControls: View {
    let discovery: DiscoverySummary
    @ObservedObject var voiceoverController: VoiceoverPlaybackController
    @Binding var scrollOffset: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var isPlaying: Bool {
        if case .playing(let id) = voiceoverController.playbackState {
            return id == discovery.id
        }
        return false
    }

    private var isPreparing: Bool {
        if case .preparing(let id) = voiceoverController.playbackState {
            return id == discovery.id
        }
        return false
    }

    private var hasAudio: Bool {
        guard let asset = voiceoverController.normalizedAsset(for: discovery.id) else {
            return false
        }
        return asset.status == .ready
    }

    // MARK: - Scroll Animation
    private let scrollTransitionThreshold: CGFloat = 60

    private var scrollProgress: CGFloat {
        min(1.0, max(0.0, scrollOffset / scrollTransitionThreshold))
    }

    private var animatedShadowOpacity: Double {
        0.15 * (1 - scrollProgress)
    }

    private var animatedShadowRadius: CGFloat {
        10 * (1 - scrollProgress)
    }

    private var animatedVerticalOffset: CGFloat {
        scrollProgress * 12
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        if hasAudio {
            HStack {
                Spacer()

                Button(action: togglePlayback) {
                    HStack(spacing: 10) {
                        // Play/Pause icon
                        ZStack {
                            Circle()
                                .fill(BrandColors.logo)
                                .frame(width: 36, height: 36)

                            if isPreparing {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else if isPlaying {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .offset(x: 2)
                            }
                        }

                        Text(isPlaying ? "Pause" : "Play Audio Guide")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(palette.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(palette.surface.opacity(0.95))
                            .shadow(
                                color: Color.black.opacity(animatedShadowOpacity),
                                radius: animatedShadowRadius,
                                x: 0,
                                y: 4
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(palette.border.opacity(1 - scrollProgress), lineWidth: 0.5)
                            )
                    )
                    .offset(y: animatedVerticalOffset)
                }
                .buttonStyle(PreOnboardingAudioButtonStyle())
                .disabled(isPreparing)

                Spacer()
            }
            .padding(.bottom, BrandSpacing.medium)
            .animation(.easeOut(duration: 0.15), value: scrollOffset)
        }
    }

    private func togglePlayback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        voiceoverController.togglePlayback(for: discovery)
    }
}

/// Simple scale button style for audio controls
private struct PreOnboardingAudioButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
