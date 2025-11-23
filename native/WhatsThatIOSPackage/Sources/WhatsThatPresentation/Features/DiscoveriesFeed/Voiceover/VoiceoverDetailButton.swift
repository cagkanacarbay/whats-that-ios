import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct VoiceoverDetailButton: View {
    let discovery: DiscoverySummary
    @ObservedObject private var controller: VoiceoverPlaybackController
    let palette: BrandTheme.Palette
    @State private var showCreditsAlert = false

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
            guard canTap else { return }
            handleTap()
        }) {
            HStack(spacing: BrandSpacing.small) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(palette.overlayButtonForeground)
                } else {
                    Image(systemName: playbackIconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.overlayButtonForeground.opacity(iconOpacity))
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
            if newValue == "insufficient_credits" {
                showCreditsAlert = true
            }
        }
    }

    private var asset: DiscoveryVoiceoverAsset? {
        controller.assetStates[discovery.id]
    }

    private var isLoading: Bool {
        asset?.status == .processing
    }

    private var canTap: Bool {
        guard let status = asset?.status else { return true }
        return status != .processing
    }

    private var playbackIconName: String {
        if downloadNeeded {
            return "arrow.down.circle.fill"
        }

        switch controller.playbackState {
        case let .playing(id) where id == discovery.id:
            return "pause.fill"
        case let .paused(id) where id == discovery.id:
            return "play.fill"
        case let .failed(id, _) where id == discovery.id:
            return "arrow.clockwise"
        default:
            return "play.fill"
        }
    }

    private var buttonTitle: String {
        if isLoading {
            return "Generating…"
        }

        if let playback = controller.playbackState.discoveryId,
           playback == discovery.id {
            switch controller.playbackState {
            case .playing:
                return "Pause Audio"
            case .paused:
                return "Resume Audio"
            case .failed:
                return "Retry Audio"
            default:
                break
            }
        }

        switch asset?.status {
        case .processing:
            return "Generating…"
        case .failed:
            return "Retry audio"
        case .ready where downloadNeeded:
            return "Download & play"
        case .ready:
            return "Play audio"
        default:
            return "Create audio"
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

    private var downloadNeeded: Bool {
        controller.isDownloadPending(for: discovery.id)
    }

    private func handleTap() {
        guard let status = asset?.status else {
            controller.requestVoiceover(for: discovery)
            return
        }

        if status == .failed || status == .missing || status == .none {
            controller.requestVoiceover(for: discovery)
        } else {
            controller.togglePlayback(for: discovery)
        }
    }
}
