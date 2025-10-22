import SwiftUI
import WhatsThatDomain
import WhatsThatShared
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct VoiceoverPlayerBar: View {
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
        VStack(spacing: BrandSpacing.medium) {
            HStack(spacing: BrandSpacing.medium) {
                artwork

                VStack(alignment: .leading, spacing: 4) {
                    Text(discovery.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    if let subtitle = playbackBindings.subtitleText {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(action: { controller.stop() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(8)
                        .background(Color.secondary.opacity(0.16))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: BrandSpacing.small) {
                Slider(
                    value: playbackBindings.sliderBinding,
                    in: 0...playbackBindings.sliderRangeUpperBound,
                    onEditingChanged: handleSliderEditingChanged(_:)
                )
                .tint(BrandColors.Dark.primaryAction)

                HStack {
                    Text(formatTime(playbackBindings.currentSliderValue))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Text(formatTime(controller.duration ?? 0))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
            }

            HStack(spacing: BrandSpacing.medium) {
                Button(action: handlePrimaryAction) {
                    Image(systemName: playbackBindings.primaryActionIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 56, height: 56)
                        .background(BrandColors.Dark.primaryAction)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                if case let .failed(id, message) = controller.playbackState, id == discovery.id {
                    Text(message ?? "Playback failed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
        .padding(BrandSpacing.medium)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: BrandCornerRadius.large, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        .animation(.easeInOut, value: controller.playbackState)
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.25))

            if let imageURL {
                DiscoveryCachedImage(
                    discoveryId: discovery.id,
                    remoteURL: imageURL
                ) { phase in
                    switch phase {
                    case .success(let platformImage):
                        platformImageView(for: platformImage)
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackIcon
                    case .loading, .empty:
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                fallbackIcon
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var fallbackIcon: some View {
        Image(systemName: "waveform")
            .font(.system(size: 18))
            .foregroundStyle(Color.secondary)
    }

    private func platformImageView(for image: DiscoveryPlatformImage) -> Image {
#if canImport(UIKit)
        return Image(uiImage: image)
#elseif canImport(AppKit)
        return Image(nsImage: image)
#endif
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

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
