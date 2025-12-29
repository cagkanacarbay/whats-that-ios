import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct VoiceoverDetailButton: View {
    let discovery: DiscoverySummary
    @ObservedObject private var controller: VoiceoverPlaybackController
    let palette: BrandTheme.Palette
    @State private var showCreditsAlert = false

    private enum ButtonState {
        case generating
        case playing
        case paused
        case readyToPlay
        case retry
        case create
    }

    init(
        discovery: DiscoverySummary,
        controller: VoiceoverPlaybackController,
        palette: BrandTheme.Palette
    ) {
        self.discovery = discovery
        self.palette = palette
        _controller = ObservedObject(initialValue: controller)
    }

    var body: some View {
        Button(action: {
            handleTap()
        }) {
            HStack(spacing: BrandSpacing.small) {
                if let iconName = iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.overlayButtonForeground.opacity(iconOpacity))
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(palette.overlayButtonForeground)
                }

                Text(buttonTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.overlayButtonForeground.opacity(titleOpacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: BrandCornerRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canTap)
        .alert(
            "Not enough credits",
            isPresented: $showCreditsAlert,
            actions: {
                Button("OK", role: .cancel) { showCreditsAlert = false }
            },
            message: {
                Text("Add more credits to generate audio.")
            }
        )
        .onChange(of: asset?.errorReason) { _, newValue in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                if newValue == "insufficient_credits" {
                    showCreditsAlert = true
                }
            }
        }
    }

    private var asset: DiscoveryVoiceoverAsset? {
        controller.normalizedAsset(for: discovery.id)
    }

    private var state: ButtonState {
        // Treat "preparing" as loading for this discovery.
        if case let .preparing(id) = controller.playbackState, id == discovery.id {
            return .generating
        }

        if let asset {
            switch asset.status {
            case .processing:
                return .generating
            case .failed:
                return .retry
            case .ready:
                if isCurrentDiscoveryPlaying {
                    return .playing
                }
                if controller.isActive(discoveryId: discovery.id) {
                    return .paused
                }
                return .readyToPlay
            case .missing, .none:
                return .create
            @unknown default:
                return .create
            }
        }

        return .create
    }

    private var buttonTitle: String {
        switch state {
        case .generating:
            return "Generating…"
        case .playing:
            return "Pause discovery"
        case .paused, .readyToPlay:
            return "Play audio"
        case .retry:
            return "Retry audio"
        case .create:
            return "Create audio (one credit)"
        }
    }

    private var iconName: String? {
        switch state {
        case .generating:
            return nil
        case .playing:
            return "pause.fill"
        case .paused, .readyToPlay:
            return "play.fill"
        case .retry:
            return "arrow.clockwise"
        case .create:
            return "plus.circle.fill"
        }
    }

    private var buttonBackground: some View {
        palette.primaryAction
            .opacity(isLoading ? 0.6 : 1.0)
    }

    private var iconOpacity: Double {
        isLoading ? 0.7 : 1.0
    }

    private var titleOpacity: Double {
        isLoading ? 0.8 : 1.0
    }

    private var isCurrentDiscoveryPlaying: Bool {
        if case let .playing(id) = controller.playbackState, id == discovery.id {
            return true
        }
        return false
    }

    private var isLoading: Bool {
        state == .generating
    }

    private var canTap: Bool {
        state != .generating
    }

    private func handleTap() {
        guard canTap else { return }

        switch state {
        case .retry, .create:
            controller.setCurrentDiscovery(discovery)
            controller.requestVoiceover(for: discovery)
        case .playing, .paused, .readyToPlay:
            controller.setCurrentDiscovery(discovery)
            controller.togglePlayback(for: discovery)
        case .generating:
            break
        }
    }
}
