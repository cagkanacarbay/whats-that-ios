import SwiftUI
import WhatsThatDomain

enum MainTabDestination {
    case camera
    case discoveries
    case upload
}

struct MainTabView: View {
    private enum Tab: Hashable {
        case camera
        case discoveries
        case upload
    }

    @State private var selectedTab: Tab
    @StateObject private var cameraViewModel: DiscoveryCreationFlowViewModel
    @StateObject private var uploadViewModel: DiscoveryCreationFlowViewModel
    @StateObject private var voiceoverController: VoiceoverPlaybackController
    @State private var feedRefreshToken = UUID()
    @State private var pendingDiscoveryId: Int64?
    @State private var pendingCreatedSummary: DiscoverySummary?
    @State private var needsFeedRefresh = false
    @State private var awaitingSummaryId: Int64?
    @State private var summaryFallbackTask: Task<Void, Never>?
    @State private var activeOverlayTab: Tab?
    @StateObject private var playerInsetStore = VoiceoverPlayerInsetStore()

    private let feedUseCase: DiscoveryFeedUseCase
    private let deletionUseCase: DiscoveryDeletionUseCase
    private let onSignOut: () -> Void
    private let onSettings: (() -> Void)?
    private let makeCreditsViewModel: (() -> CreditsViewModel)?

    init(
        feedUseCase: DiscoveryFeedUseCase,
        deletionUseCase: DiscoveryDeletionUseCase,
        cameraViewModel: DiscoveryCreationFlowViewModel,
        uploadViewModel: DiscoveryCreationFlowViewModel,
        voiceoverControllerFactory: @escaping () -> VoiceoverPlaybackController,
        initialTab: MainTabDestination = .discoveries,
        onSignOut: @escaping () -> Void,
        onSettings: (() -> Void)? = nil,
        makeCreditsViewModel: (() -> CreditsViewModel)? = nil
    ) {
        self.feedUseCase = feedUseCase
        self.deletionUseCase = deletionUseCase
        self.onSignOut = onSignOut
        self.onSettings = onSettings
        self.makeCreditsViewModel = makeCreditsViewModel
        _selectedTab = State(initialValue: Self.tab(for: initialTab))
        _cameraViewModel = StateObject(wrappedValue: cameraViewModel)
        _uploadViewModel = StateObject(wrappedValue: uploadViewModel)
        _voiceoverController = StateObject(wrappedValue: voiceoverControllerFactory())
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                DiscoveryCreationFlowView(
                    viewModel: cameraViewModel,
                    placeholderEmoji: "📷",
                    ctaTitle: "Take a photo to discover",
                    retryTitle: "Try again",
                    makeCreditsViewModel: makeCreditsViewModel
                )
                .tag(Tab.camera)
                .tabItem {
                    Label("Camera", systemImage: "camera.fill")
                }

                DiscoveriesHomeView(
                    feedUseCase: feedUseCase,
                    deletionUseCase: deletionUseCase,
                    voiceoverController: voiceoverController,
                    pendingDiscoveryId: $pendingDiscoveryId,
                    pendingCreatedSummary: $pendingCreatedSummary,
                    onSignOut: onSignOut,
                    onSettings: onSettings,
                    onQuickCamera: { selectedTab = .camera },
                    onQuickUpload: { selectedTab = .upload }
                )
                .id(feedRefreshToken)
                .tag(Tab.discoveries)
                .tabItem {
                    Label("Discoveries", systemImage: "square.grid.2x2")
                }
                // Attach the voiceover bar within the Discoveries tab so it
                // appears above the tab bar rather than covering it.
                .safeAreaInset(edge: .bottom) {
                    if shouldShowPlayerInset {
                        VoiceoverPlayerHost(
                            controller: voiceoverController,
                            overlayPhase: activeOverlayPhase,
                            imageURLResolver: imageURL(for:)
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                DiscoveryCreationFlowView(
                    viewModel: uploadViewModel,
                    placeholderEmoji: "🖼️",
                    ctaTitle: "Choose a photo from your gallery",
                    retryTitle: "Select again",
                    makeCreditsViewModel: makeCreditsViewModel
                )
                .tag(Tab.upload)
                .tabItem {
                    Label("Gallery", systemImage: "photo.on.rectangle")
                }
            }
        
            if let overlayTab = activeOverlayTab,
               let overlayViewModel = viewModel(for: overlayTab),
               shouldShowOverlay(for: overlayViewModel.flowState)
            {
                DiscoveryCreationFlowView(
                    viewModel: overlayViewModel,
                    placeholderEmoji: overlayTab == .camera ? "📷" : "🖼️",
                    ctaTitle: overlayTab == .camera ? "Take a photo to discover" : "Choose a photo from your gallery",
                    retryTitle: overlayTab == .camera ? "Try again" : "Select again",
                    makeCreditsViewModel: makeCreditsViewModel
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .environmentObject(playerInsetStore)
        .onAppear {
            cameraViewModel.onDiscoveryCreated = handleDiscoveryCreated
            uploadViewModel.onDiscoveryCreated = handleDiscoveryCreated
            cameraViewModel.onDiscoverySummaryReady = handleDiscoverySummaryReady
            uploadViewModel.onDiscoverySummaryReady = handleDiscoverySummaryReady
            cameraViewModel.onAnalysisBegan = handleAnalysisBegan
            uploadViewModel.onAnalysisBegan = handleAnalysisBegan
            handleTabChange(to: selectedTab, isInitial: true)
        }
        .onDisappear {
            summaryFallbackTask?.cancel()
        }
        .onChange(of: selectedTab) { _, newValue in
            handleTabChange(to: newValue)
        }
        .onChange(of: cameraViewModel.flowState.phase) { _, newPhase in
            updateOverlayVisibility(for: .camera, phase: newPhase)
        }
        .onChange(of: uploadViewModel.flowState.phase) { _, newPhase in
            updateOverlayVisibility(for: .upload, phase: newPhase)
        }
    }

    private func handleTabChange(to tab: Tab, isInitial: Bool = false) {
        switch tab {
        case .camera:
            uploadViewModel.cancelFlow()
            cameraViewModel.startFlow()
            activeOverlayTab = nil
        case .upload:
            cameraViewModel.cancelFlow()
            uploadViewModel.startFlow()
            activeOverlayTab = nil
        case .discoveries:
            if activeOverlayTab != .camera {
                cameraViewModel.cancelFlow()
            }
            if activeOverlayTab != .upload {
                uploadViewModel.cancelFlow()
            }
            if needsFeedRefresh {
                feedRefreshToken = UUID()
                needsFeedRefresh = false
            }
            if isInitial {
                cameraViewModel.cancelFlow()
                uploadViewModel.cancelFlow()
            }
        }
    }

    private func handleDiscoveryCreated(_ discoveryId: Int64) {
        // Do not pre-select the discovery from the feed; keep the overlay active during creation.
        // pendingDiscoveryId = discoveryId
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
        // Upsert the created summary into the feed so it's available behind the overlay.
        pendingCreatedSummary = summary
        // Do NOT trigger a hero open; we want to remain on the creation overlay.
        // pendingDiscoveryId = summary.id
        needsFeedRefresh = false
        // Ensure we're showing the Discoveries tab underneath the overlay.
        selectedTab = .discoveries
        // Keep the creation overlay visible; do not cancel the flow or clear the overlay.
        // cameraViewModel.cancelFlow()
        // uploadViewModel.cancelFlow()
        // activeOverlayTab = nil
    }

    private func handleAnalysisBegan(_ type: DiscoveryCreationFlowType) {
        switch type {
        case .camera:
            activeOverlayTab = .camera
        case .upload:
            activeOverlayTab = .upload
        }
        selectedTab = .discoveries
    }

    private func shouldShowOverlay(for state: DiscoveryCreationFlowState) -> Bool {
        switch state {
        case .idle, .cancelled:
            return false
        default:
            return true
        }
    }

    private func shouldShowOverlay(for phase: DiscoveryCreationPhase) -> Bool {
        switch phase {
        case .idle, .cancelled:
            return false
        default:
            return true
        }
    }

    private func viewModel(for tab: Tab) -> DiscoveryCreationFlowViewModel? {
        switch tab {
        case .camera:
            return cameraViewModel
        case .upload:
            return uploadViewModel
        case .discoveries:
            return nil
        }
    }

    private func updateOverlayVisibility(for tab: Tab, state: DiscoveryCreationFlowState) {
        guard activeOverlayTab == tab else { return }
        if !shouldShowOverlay(for: state) {
            activeOverlayTab = nil
        }
    }

    private func updateOverlayVisibility(for tab: Tab, phase: DiscoveryCreationPhase) {
        guard activeOverlayTab == tab else { return }
        if !shouldShowOverlay(for: phase) {
            activeOverlayTab = nil
        }
    }

    private var activeOverlayPhase: DiscoveryCreationPhase? {
        guard let tab = activeOverlayTab else { return nil }
        switch tab {
        case .camera:
            return cameraViewModel.flowState.phase
        case .upload:
            return uploadViewModel.flowState.phase
        case .discoveries:
            return nil
        }
    }

    private var shouldShowPlayerInset: Bool {
        // Only in the Discoveries tab context.
        guard selectedTab == .discoveries else { return false }

        // Hide during capture/selection/confirmation stages of the creation overlay.
        if let phase = activeOverlayPhase {
            switch phase {
            case .capturingInitial, .capturingRetake, .selectingInitial, .selectingRetake, .confirming, .requestingPermissions:
                return false
            case .analyzing, .idle, .cancelled, .error:
                break
            }
        }

        // Only when the player has something to show.
        switch voiceoverController.playbackState {
        case .idle, .unavailable:
            return false
        default:
            return voiceoverController.currentDiscovery != nil
        }
    }

    private func imageURL(for discovery: DiscoverySummary) -> URL? {
        guard let path = discovery.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        return URL(string: path)
    }

    private static func tab(for destination: MainTabDestination) -> Tab {
        switch destination {
        case .camera:
            return .camera
        case .discoveries:
            return .discoveries
        case .upload:
            return .upload
        }
    }
}
