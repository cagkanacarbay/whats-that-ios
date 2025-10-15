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
    @State private var feedRefreshToken = UUID()

    private let feedUseCase: DiscoveryFeedUseCase
    private let onSignOut: () -> Void
    private let onSettings: (() -> Void)?

    init(
        feedUseCase: DiscoveryFeedUseCase,
        cameraViewModel: DiscoveryCreationFlowViewModel,
        uploadViewModel: DiscoveryCreationFlowViewModel,
        onSignOut: @escaping () -> Void,
        onSettings: (() -> Void)? = nil
    ) {
        self.feedUseCase = feedUseCase
        self.onSignOut = onSignOut
        self.onSettings = onSettings
        _cameraViewModel = StateObject(wrappedValue: cameraViewModel)
        _uploadViewModel = StateObject(wrappedValue: uploadViewModel)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DiscoveryCreationFlowView(
                viewModel: cameraViewModel,
                placeholderEmoji: "📷",
                ctaTitle: "Take a photo to discover",
                retryTitle: "Try again"
            )
            .tag(Tab.camera)
            .tabItem {
                Label("Camera", systemImage: "camera.fill")
            }

            DiscoveriesHomeView(
                feedUseCase: feedUseCase,
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
                retryTitle: "Select again"
            )
            .tag(Tab.upload)
            .tabItem {
                Label("Upload", systemImage: "square.and.arrow.up")
            }
        }
        .onAppear {
            cameraViewModel.onDiscoveryCreated = handleDiscoveryCreated
            uploadViewModel.onDiscoveryCreated = handleDiscoveryCreated
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
            }
        }
    }

    private func handleDiscoveryCreated(_ discoveryId: Int64) {
        selectedTab = .discoveries
        cameraViewModel.cancelFlow()
        uploadViewModel.cancelFlow()
        feedRefreshToken = UUID()
    }
}
