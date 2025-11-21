import SwiftUI
import WhatsThatDomain

@MainActor
struct VoiceoverPlaybackBindings {
    let controller: VoiceoverPlaybackController
    let discovery: DiscoverySummary
    @Binding var pendingSliderValue: Double?

    init(
        controller: VoiceoverPlaybackController,
        discovery: DiscoverySummary,
        pendingSliderValue: Binding<Double?>
    ) {
        self.controller = controller
        self.discovery = discovery
        _pendingSliderValue = pendingSliderValue
    }

    var sliderRangeUpperBound: Double {
        let duration = controller.duration ?? 0
        if duration > 0 {
            return duration
        }
        return max(controller.position, 1)
    }

    var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: {
                min(max(pendingSliderValue ?? controller.position, 0), sliderRangeUpperBound)
            },
            set: { newValue in
                pendingSliderValue = newValue
            }
        )
    }

    var currentSliderValue: Double {
        pendingSliderValue ?? controller.position
    }

    var primaryActionIcon: String {
        switch controller.playbackState {
        case let .playing(id) where id == discovery.id:
            return "pause.fill"
        case let .paused(id) where id == discovery.id:
            return "play.fill"
        default:
            return "play.fill"
        }
    }

    var subtitleText: String? {
        switch controller.playbackState {
        case let .loading(id) where id == discovery.id:
            return "Preparing narration..."
        case let .paused(id) where id == discovery.id:
            return "Paused"
        case let .playing(id) where id == discovery.id:
            return "Playing"
        case let .failed(id, _) where id == discovery.id:
            return "Playback error"
        default:
            if let model = controller.assetStates[discovery.id]?.modelIdentifier {
                return model
            }
            return nil
        }
    }

    @MainActor
    func commitPendingSliderValue() {
        guard let pendingSliderValue else {
            return
        }

        controller.seek(to: pendingSliderValue) {
            self.pendingSliderValue = nil
        }
    }
}
