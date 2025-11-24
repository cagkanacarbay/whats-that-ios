import SwiftUI
import WhatsThatDomain
import WhatsThatShared
import UIKit

struct VoiceoverPersistentPlayerView: View {
    @ObservedObject private var controller: VoiceoverPlaybackController
    let discovery: DiscoverySummary
    let imageURL: URL?
    let onNextDiscovery: (() -> Void)?
    let onPreviousDiscovery: (() -> Void)?
    private let artworkSize: CGFloat = 72
    private let primaryButtonSize: CGFloat = 36
    private let skipButtonSize: CGFloat = 28
    private let primaryActionAreaWidth: CGFloat = 120
    private let closeButtonSize: CGFloat = 26
    private var artworkShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 8,
            topTrailingRadius: 8
        )
    }

    @State private var pendingSliderValue: Double?
    @State private var isScrubbing = false
    @State private var isSliderEditing = false
    @State private var isSuppressingProgress = false

    init(
        controller: VoiceoverPlaybackController,
        discovery: DiscoverySummary,
        imageURL: URL?,
        onNextDiscovery: (() -> Void)? = nil,
        onPreviousDiscovery: (() -> Void)? = nil
    ) {
        _controller = ObservedObject(initialValue: controller)
        self.discovery = discovery
        self.imageURL = imageURL
        self.onNextDiscovery = onNextDiscovery
        self.onPreviousDiscovery = onPreviousDiscovery
    }

    private var playbackBindings: VoiceoverPlaybackBindings {
        VoiceoverPlaybackBindings(
            controller: controller,
            discovery: discovery,
            pendingSliderValue: $pendingSliderValue
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: BrandSpacing.small) {
                artwork

                VStack {
                    Spacer()
                    HStack(spacing: BrandSpacing.small * 0.75) {
                        previousButton
                        primaryActionButton
                        nextButton
                    }
                    Spacer()
                }
                .frame(width: primaryActionAreaWidth, height: artworkSize, alignment: .center)

                VStack(alignment: .leading, spacing: BrandSpacing.small * 0.5) {
                    Text(discovery.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, BrandSpacing.small * 0.5)

                    scrubber
                        .frame(height: 20)
                        .padding(.trailing, BrandSpacing.small)

                    HStack {
                        Text(formatTime(playbackBindings.currentSliderValue))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTime(controller.duration ?? 0))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, BrandSpacing.small)

                    Spacer(minLength: BrandSpacing.small * 0.5)
                }
                .frame(height: artworkSize, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 0)
            .padding(.vertical, 0)
            .background(tabBarMatchedBackground)
            .animation(.easeInOut, value: controller.playbackState)

            closeButton
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tabBarSeparatorColor)
                .frame(height: hairlineWidth)
                .frame(maxWidth: .infinity, alignment: .top)
                .allowsHitTesting(false)
        }
    }

    private var artwork: some View {
        ZStack {
            artworkShape
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
                            .scaleEffect(1.08)
                    case .failure:
                        fallbackIcon
                    case .loading, .empty:
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
                .clipShape(artworkShape)
            } else {
                fallbackIcon
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(artworkShape)
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        Image(systemName: "waveform")
            .font(.system(size: 14))
            .foregroundStyle(Color.secondary)
    }

    private var primaryActionButton: some View {
        Button(action: handlePrimaryAction) {
            Image(systemName: playbackBindings.primaryActionIcon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: primaryButtonSize, height: primaryButtonSize)
                .background(BrandColors.Dark.primaryAction)
                .clipShape(Circle())
                .accessibilityLabel(primaryActionAccessibilityLabel)
        }
        .buttonStyle(.plain)
    }

    private var previousButton: some View {
        Button(action: handlePreviousDiscovery) {
            Image(systemName: "backward.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: skipButtonSize, height: skipButtonSize)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Circle())
                .accessibilityLabel("Rewind")
        }
        .buttonStyle(.plain)
    }

    private var nextButton: some View {
        Button(action: handleNextDiscovery) {
            Image(systemName: "forward.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: skipButtonSize, height: skipButtonSize)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Circle())
                .accessibilityLabel("Fast forward")
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button(action: { controller.stop() }) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .frame(width: closeButtonSize, height: closeButtonSize)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel("Close player")
        }
        .buttonStyle(.plain)
    }

    private var scrubber: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let sliderUpperBound = playbackBindings.sliderRangeUpperBound
            let progress = sliderUpperBound > 0
                ? playbackBindings.currentSliderValue / sliderUpperBound
                : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))

                Capsule()
                    .fill(BrandColors.Dark.primaryAction)
                    .frame(width: max(0, min(width * progress, width)))
            }
            .frame(height: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .overlay {
                Slider(
                    value: playbackBindings.sliderBinding,
                    in: 0...playbackBindings.sliderRangeUpperBound,
                    onEditingChanged: handleSliderEditingChanged(_:)
                )
                .tint(.clear)
                .opacity(0.01) // keep gestures, hide knob/track
                .frame(height: max(proxy.size.height, 32))
                .contentShape(Rectangle())
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        updateSuppressionIfNeeded()
                        let resolvedWidth = max(width, 1)
                        pendingSliderValue = scrubValue(for: value.location.x, width: resolvedWidth, upperBound: sliderUpperBound)
                    }
                    .onEnded { value in
                        let resolvedWidth = max(width, 1)
                        pendingSliderValue = scrubValue(for: value.location.x, width: resolvedWidth, upperBound: sliderUpperBound)
                        playbackBindings.commitPendingSliderValue()
                        isScrubbing = false
                        // Reset slider editing flag in case the hidden slider also fired.
                        isSliderEditing = false
                        updateSuppressionIfNeeded()
                    }
            )
        }
        .frame(height: 20)
    }

    private var tabBarMatchedBackground: Color {
        let appearance = UITabBar.appearance()
        if let standardColor = appearance.standardAppearance.backgroundColor {
            return Color(uiColor: standardColor)
        }
        if let scrollEdgeColor = appearance.scrollEdgeAppearance?.backgroundColor {
            return Color(uiColor: scrollEdgeColor)
        }
        return Color(uiColor: .systemBackground)
    }

    private var tabBarSeparatorColor: Color {
        let appearance = UITabBar.appearance()
        if let standardShadow = appearance.standardAppearance.shadowColor {
            return Color(uiColor: standardShadow)
        }
        if let scrollEdgeShadow = appearance.scrollEdgeAppearance?.shadowColor {
            return Color(uiColor: scrollEdgeShadow)
        }
        return Color(uiColor: .separator)
    }

    private var hairlineWidth: CGFloat {
        1 / UIScreen.main.scale
    }

    private func handleSliderEditingChanged(_ isEditing: Bool) {
        isSliderEditing = isEditing
        updateSuppressionIfNeeded()
        if !isEditing && !isScrubbing {
            playbackBindings.commitPendingSliderValue()
        }
    }

    private func scrubValue(for locationX: CGFloat, width: CGFloat, upperBound: Double) -> Double {
        guard upperBound > 0 else { return 0 }
        let clampedX = min(max(locationX, 0), width)
        let fraction = Double(clampedX / width)
        return fraction * upperBound
    }

    private func updateSuppressionIfNeeded() {
        let shouldSuppress = isScrubbing || isSliderEditing
        if shouldSuppress != isSuppressingProgress {
            isSuppressingProgress = shouldSuppress
            controller.suppressProgressUpdates = shouldSuppress
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

    private func handlePreviousDiscovery() {
        onPreviousDiscovery?()
    }

    private func handleNextDiscovery() {
        onNextDiscovery?()
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
