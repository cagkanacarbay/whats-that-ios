import SwiftUI
import WhatsThatDomain

struct MainTabView: View {
    private enum Tab: Hashable {
        case camera
        case discoveries
        case upload
    }

    @State private var selectedTab: Tab = .discoveries
    @StateObject private var cameraViewModel: DiscoveryCreationFlowViewModel
    @StateObject private var uploadViewModel: DiscoveryCreationFlowViewModel
    @StateObject private var voiceoverController: VoiceoverPlaybackController
    @State private var feedRefreshToken = UUID()
    @State private var pendingDiscoveryId: Int64?
    @State private var pendingCreatedSummary: DiscoverySummary?
    @State private var needsFeedRefresh = false
    @State private var awaitingSummaryId: Int64?
    @State private var summaryFallbackTask: Task<Void, Never>?

    private let feedUseCase: DiscoveryFeedUseCase
    private let onSignOut: () -> Void
    private let onSettings: (() -> Void)?

    init(
        feedUseCase: DiscoveryFeedUseCase,
        cameraViewModel: DiscoveryCreationFlowViewModel,
        uploadViewModel: DiscoveryCreationFlowViewModel,
        voiceoverControllerFactory: @escaping () -> VoiceoverPlaybackController,
        onSignOut: @escaping () -> Void,
        onSettings: (() -> Void)? = nil
    ) {
        self.feedUseCase = feedUseCase
        self.onSignOut = onSignOut
        self.onSettings = onSettings
        _cameraViewModel = StateObject(wrappedValue: cameraViewModel)
        _uploadViewModel = StateObject(wrappedValue: uploadViewModel)
        _voiceoverController = StateObject(wrappedValue: voiceoverControllerFactory())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DiscoveryCreationFlowView(
                viewModel: cameraViewModel,
                placeholderEmoji: "📷",
                ctaTitle: "Take a photo to discover",
                retryTitle: "Try again",
                voiceoverController: voiceoverController
            )
            .tag(Tab.camera)
            .tabItem {
                Label("Camera", systemImage: "camera.fill")
            }

            DiscoveriesHomeView(
                feedUseCase: feedUseCase,
                voiceoverController: voiceoverController,
                pendingDiscoveryId: $pendingDiscoveryId,
                pendingCreatedSummary: $pendingCreatedSummary,
                onSignOut: onSignOut,
                onSettings: onSettings
            )
            .id(feedRefreshToken)
            .tag(Tab.discoveries)
            .tabItem {
                Label("Discoveries", systemImage: "square.grid.2x2")
            }

            DiscoveryCreationFlowView(
                viewModel: uploadViewModel,
                placeholderEmoji: "📤",
                ctaTitle: "Upload a photo to analyze",
                retryTitle: "Select again",
                voiceoverController: voiceoverController
            )
            .tag(Tab.upload)
            .tabItem {
                Label("Upload", systemImage: "square.and.arrow.up")
            }
        }
        .onAppear {
            cameraViewModel.onDiscoveryCreated = handleDiscoveryCreated
            uploadViewModel.onDiscoveryCreated = handleDiscoveryCreated
            cameraViewModel.onDiscoverySummaryReady = handleDiscoverySummaryReady
            uploadViewModel.onDiscoverySummaryReady = handleDiscoverySummaryReady
        }
        .onDisappear {
            summaryFallbackTask?.cancel()
        }
        .onChange(of: selectedTab) { newValue in
            switch newValue {
            case .camera:
                uploadViewModel.cancelFlow()
                cameraViewModel.startFlow()
            case .upload:
                cameraViewModel.cancelFlow()
                uploadViewModel.startFlow()
            case .discoveries:
                cameraViewModel.cancelFlow()
                uploadViewModel.cancelFlow()
                if needsFeedRefresh {
                    feedRefreshToken = UUID()
                    needsFeedRefresh = false
                }
            }
        }
    }

    private func handleDiscoveryCreated(_ discoveryId: Int64) {
        pendingDiscoveryId = discoveryId
        awaitingSummaryId = discoveryId
        summaryFallbackTask?.cancel()
        summaryFallbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if awaitingSummaryId == discoveryId {
                    needsFeedRefresh = true
                }
            }
        }
    }

    private func handleDiscoverySummaryReady(_ summary: DiscoverySummary) {
        summaryFallbackTask?.cancel()
        awaitingSummaryId = nil
        pendingCreatedSummary = summary
        pendingDiscoveryId = summary.id
        needsFeedRefresh = false
    }
}
