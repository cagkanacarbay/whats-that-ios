import SwiftUI
import WhatsThatDomain
import WhatsThatShared
import UIKit

struct VoiceoverPersistentPlayerView: View {
    @ObservedObject private var controller: VoiceoverPlaybackController
    let discovery: DiscoverySummary
    let imageURL: URL?

    @State private var pendingSliderValue: Double?
    @State private var isScrubbing = false

    init(
        controller: VoiceoverPlaybackController,
        discovery: DiscoverySummary,
        imageURL: URL?
    ) {
        _controller = ObservedObject(initialValue: controller)
        self.discovery = discovery
        self.imageURL = imageURL
    }

    private var playbackBindings: VoiceoverPlaybackBindings {
        VoiceoverPlaybackBindings(
            controller: controller,
            discovery: discovery,
            pendingSliderValue: $pendingSliderValue
        )
    }

    var body: some View {
        HStack(spacing: BrandSpacing.medium) {
            artwork

            VStack(spacing: 6) {
                Slider(
                    value: playbackBindings.sliderBinding,
                    in: 0...playbackBindings.sliderRangeUpperBound,
                    onEditingChanged: handleSliderEditingChanged(_:)
                )
                .tint(BrandColors.Dark.primaryAction)

                HStack {
                    Text(formatTime(playbackBindings.currentSliderValue))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(controller.duration ?? 0))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: BrandSpacing.small) {
                Button(action: handlePrimaryAction) {
                    Image(systemName: playbackBindings.primaryActionIcon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 36, height: 36)
                        .background(BrandColors.Dark.primaryAction)
                        .clipShape(Circle())
                        .accessibilityLabel(primaryActionAccessibilityLabel)
                }
                .buttonStyle(.plain)

                Button(action: { controller.stop() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .padding(8)
                        .background(Color.secondary.opacity(0.18))
                        .clipShape(Circle())
                        .accessibilityLabel("Close player")
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, BrandSpacing.large)
        .padding(.vertical, BrandSpacing.medium)
        .background(.thinMaterial)
        .animation(.easeInOut, value: controller.playbackState)
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.25))

            if let imageURL {
                DiscoveryCachedImage(
                    discoveryId: discovery.id,
                    remoteURL: imageURL
                ) { phase in
                    switch phase {
                    case .success(let platformImage):
                        Image(uiImage: platformImage)
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackIcon
                    case .loading, .empty:
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                fallbackIcon
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        Image(systemName: "waveform")
            .font(.system(size: 14))
            .foregroundStyle(Color.secondary)
    }

    private func handleSliderEditingChanged(_ isEditing: Bool) {
        isScrubbing = isEditing
        if !isEditing {
            playbackBindings.commitPendingSliderValue()
        }
    }

    private func handlePrimaryAction() {
        switch controller.playbackState {
        case let .playing(id) where id == discovery.id:
            controller.pause()
        case let .paused(id) where id == discovery.id:
            controller.resume()
        default:
            controller.togglePlayback(for: discovery)
        }
    }

    private var primaryActionAccessibilityLabel: String {
        switch controller.playbackState {
        case let .playing(id) where id == discovery.id:
            return "Pause"
        default:
            return "Play"
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
