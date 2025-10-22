import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct VoiceoverDetailButton: View {
    let discovery: DiscoverySummary
    @ObservedObject private var controller: VoiceoverPlaybackController
    let palette: BrandTheme.Palette

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
        Button(action: { controller.togglePlayback(for: discovery) }) {
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
        .disabled(isLoading)
    }

    private var asset: DiscoveryVoiceoverAsset? {
        controller.assetStates[discovery.id]
    }

    private var isLoading: Bool {
        controller.isLoading(discoveryId: discovery.id) && asset == nil
    }

    private var isUnavailable: Bool {
        asset?.status == .missing
    }

    private var playbackIconName: String {
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
            return "Loading narration..."
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

        if isUnavailable {
            return "Narration unavailable"
        }

        if case let .failed(id, _) = controller.playbackState, id == discovery.id {
            return "Retry Audio"
        }

        return "Play Audio Narration"
    }

    private var buttonBackground: some View {
        palette.primaryAction
            .opacity(isUnavailable ? 0.55 : 1.0)
    }

    private var iconOpacity: Double {
        isUnavailable ? 0.7 : 1.0
    }

    private var titleOpacity: Double {
        isUnavailable ? 0.75 : 1.0
    }
}
