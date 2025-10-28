import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct VoiceoverPlayerBar: View {
    @ObservedObject private var controller: VoiceoverPlaybackController
    private let discovery: DiscoverySummary
    private let imageURL: URL?
    @EnvironmentObject private var insetStore: VoiceoverPlayerInsetStore

    init(
        controller: VoiceoverPlaybackController,
        discovery: DiscoverySummary,
        imageURL: URL?
    ) {
        _controller = ObservedObject(initialValue: controller)
        self.discovery = discovery
        self.imageURL = imageURL
    }

    var body: some View {
        VoiceoverPersistentPlayerView(
            controller: controller,
            discovery: discovery,
            imageURL: imageURL
        )
        .frame(maxWidth: .infinity)
        // Cancel parent horizontal padding so the bar spans full width.
        .padding(.horizontal, -BrandSpacing.large)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: VoiceoverPlayerHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        )
        .onPreferenceChange(VoiceoverPlayerHeightPreferenceKey.self) { value in
            Task { @MainActor in
                insetStore.update(height: value)
            }
        }
        .onDisappear {
            Task { @MainActor in
                insetStore.update(height: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio player")
    }
}
