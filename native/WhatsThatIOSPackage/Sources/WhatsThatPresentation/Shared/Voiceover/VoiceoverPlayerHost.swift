import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct VoiceoverPlayerHost: View {
    @ObservedObject private var controller: VoiceoverPlaybackController
    @EnvironmentObject private var insetStore: VoiceoverPlayerInsetStore
    let overlayPhase: DiscoveryCreationPhase?
    let imageURLResolver: (DiscoverySummary) -> URL?

    init(
        controller: VoiceoverPlaybackController,
        overlayPhase: DiscoveryCreationPhase?,
        imageURLResolver: @escaping (DiscoverySummary) -> URL?
    ) {
        _controller = ObservedObject(initialValue: controller)
        self.overlayPhase = overlayPhase
        self.imageURLResolver = imageURLResolver
    }

    var body: some View {
        Group {
            if isVisible, let discovery = controller.currentDiscovery {
                VoiceoverPersistentPlayerView(
                    controller: controller,
                    discovery: discovery,
                    imageURL: imageURLResolver(discovery),
                    onNextDiscovery: { controller.skipToNextDiscovery() },
                    onPreviousDiscovery: { controller.skipToPreviousDiscovery() }
                )
                .id(discovery.id)
                .frame(maxWidth: .infinity)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: VoiceoverPlayerHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )
                .onPreferenceChange(VoiceoverPlayerHeightPreferenceKey.self) { value in
                    Task { @MainActor in
                        insetStore.update(height: value)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: isVisible) { _, visible in
            if !visible {
                Task { @MainActor in
                    insetStore.update(height: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio player")
    }

    private var isVisible: Bool {
        // Hide during capture/selection/confirmation overlays; allow during streaming.
        if let phase = overlayPhase {
            switch phase {
            case .analyzing:
                break // allowed
            default:
                return false
            }
        }

        // Show for active or loading/failed states that have a discovery.
        switch controller.playbackState {
        case .idle, .failed:
            return false
        default:
            return controller.currentDiscovery != nil
        }
    }
}
