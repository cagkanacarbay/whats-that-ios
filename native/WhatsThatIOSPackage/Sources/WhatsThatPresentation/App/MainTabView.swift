import SwiftUI
import os
import WhatsThatDomain
import WhatsThatShared

public enum MainTabDestination {
    case camera
    case discoveries
    case upload
    case audioGuides
}

struct MainTabView: View {
    private enum Tab: Hashable {
        case camera
        case discoveries
        case upload
        case audioGuides
    }

    @State private var selectedTab: Tab
    @StateObject private var cameraViewModel: DiscoveryCreationFlowViewModel
    @StateObject private var uploadViewModel: DiscoveryCreationFlowViewModel
    @StateObject private var audioServices: AudioServicesContainer
    @ObservedObject private var storeObserver: DiscoveryStoreObserver
    @State private var pendingDiscoveryId: Int64?
    @State private var awaitingSummaryId: Int64?
    @State private var summaryFallbackTask: Task<Void, Never>?
    @State private var activeOverlayTab: Tab?
    @State private var audioGuidesMode: AudioGuidesDisplayMode = .hero
    @State private var openFirstDetailFromAudioGuides = false
    @State private var audioGuidesTargetDiscoveryId: Int64?
    @State private var audioGuidesTargetDiscoverySummary: DiscoverySummary?
    
    // Background polling/UX state
    @State private var showingProcessingAlert = false

    private let deletionUseCase: DiscoveryDeletionUseCase
    private let onSignOut: () -> Void
    private let onSettings: (() -> Void)?
    private let makeCreditsViewModel: (() -> CreditsViewModel)?

    init(
        storeObserver: DiscoveryStoreObserver,
        deletionUseCase: DiscoveryDeletionUseCase,
        cameraViewModel: DiscoveryCreationFlowViewModel,
        uploadViewModel: DiscoveryCreationFlowViewModel,
        audioServicesFactory: @escaping () -> AudioServicesContainer,
        initialTab: MainTabDestination = .discoveries,
        onSignOut: @escaping () -> Void,
        onSettings: (() -> Void)? = nil,
        makeCreditsViewModel: (() -> CreditsViewModel)? = nil
    ) {
        self._storeObserver = ObservedObject(wrappedValue: storeObserver)
        self.deletionUseCase = deletionUseCase
        self.onSignOut = onSignOut
        self.onSettings = onSettings
        self.makeCreditsViewModel = makeCreditsViewModel
        _selectedTab = State(initialValue: Self.tab(for: initialTab))
        _cameraViewModel = StateObject(wrappedValue: cameraViewModel)
        _uploadViewModel = StateObject(wrappedValue: uploadViewModel)
        _audioServices = StateObject(wrappedValue: audioServicesFactory())
    }

    // Convenience accessor
    private var voiceoverController: VoiceoverPlaybackController {
        audioServices.playbackController
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
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
                    storeObserver: storeObserver,
                    deletionUseCase: deletionUseCase,
                    voiceoverController: voiceoverController,
                    pendingDiscoveryId: $pendingDiscoveryId,
                    openFirstDetailFromAudioGuides: $openFirstDetailFromAudioGuides,
                    audioGuidesTargetDiscoveryId: $audioGuidesTargetDiscoveryId,
                    audioGuidesTargetDiscoverySummary: $audioGuidesTargetDiscoverySummary,
                    onSignOut: onSignOut,
                    onSettings: onSettings,
                    onQuickCamera: { selectedTab = .camera },
                    onQuickUpload: { selectedTab = .upload },
                    onOpenAudioGuide: { discovery in
                        handleDiscoveryAudioPillTapped(discovery)
                    }
                )
                .tag(Tab.discoveries)
                .tabItem {
                    Label("Discoveries", systemImage: "square.grid.2x2")
                }

                AudioGuidesPageView(
                    mode: $audioGuidesMode,
                    audioServices: audioServices,
                    onTextSelected: { discovery in
                        handleAudioGuideTextSelected(discovery)
                    },
                    makeCreditsViewModel: makeCreditsViewModel
                )
                .tag(Tab.audioGuides)
                .tabItem {
                    Label("Audio Guides", systemImage: "headphones")
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
        
            // Creation overlay
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
            
            // Global mini player overlay - wrapped to properly observe controller changes
            MiniPlayerVisibilityWrapper(
                controller: audioServices.playbackController,
                miniPlayerPresence: audioServices.miniPlayerPresence,
                isAudioGuidesTab: selectedTab == .audioGuides,
                audioGuidesMode: audioGuidesMode,
                activeOverlayPhase: activeOverlayPhase
            ) {
                VStack {
                    Spacer()
                    MiniPlayerView {
                        // Tap mini player -> switch to Audio Guides in hero mode
                        selectedTab = .audioGuides
                        audioGuidesMode = .hero
                    }
                    .padding(.horizontal, 16)
                }
                // Position above tab bar: standard tab bar height (49) + spacing
                .padding(.bottom, 49 + 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Generation complete toast - positioned above mini player
            GenerationToastOverlay(audioServices: audioServices)
        }
        .alert("Processing Discovery", isPresented: $showingProcessingAlert) {
            Button("OK") { showingProcessingAlert = false }
        } message: {
            Text("Your discovery is being processed. We'll let you know when it's ready.")
        }
        .audioServices(audioServices)
        .onAppear {
            cameraViewModel.onDiscoveryCreated = handleDiscoveryCreated
            uploadViewModel.onDiscoveryCreated = handleDiscoveryCreated
            cameraViewModel.onDiscoverySummaryReady = handleDiscoverySummaryReady
            uploadViewModel.onDiscoverySummaryReady = handleDiscoverySummaryReady
            cameraViewModel.onAnalysisBegan = handleAnalysisBegan
            uploadViewModel.onAnalysisBegan = handleAnalysisBegan
            
            cameraViewModel.onStreamInterrupted = handleStreamInterrupted
            uploadViewModel.onStreamInterrupted = handleStreamInterrupted
            cameraViewModel.onPollingDiscoveryReady = { discovery in
                print("[DEBUG MainTabView] onPollingDiscoveryReady CALLBACK RECEIVED for discovery \(discovery.id)")
                handlePollingDiscoveryReady(discovery)
            }
            uploadViewModel.onPollingDiscoveryReady = { discovery in
                print("[DEBUG MainTabView] onPollingDiscoveryReady CALLBACK RECEIVED for discovery \(discovery.id)")
                handlePollingDiscoveryReady(discovery)
            }
            print("[DEBUG MainTabView] onAppear: callbacks assigned")

            handleTabChange(to: selectedTab, isInitial: true)
        }
        .onDisappear {
            summaryFallbackTask?.cancel()
        }
        .onChange(of: selectedTab) { _, newValue in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                handleTabChange(to: newValue)
            }
        }
        .onChange(of: cameraViewModel.flowState.phase) { _, newPhase in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                updateOverlayVisibility(for: .camera, phase: newPhase)
            }
        }
        .onChange(of: uploadViewModel.flowState.phase) { _, newPhase in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                updateOverlayVisibility(for: .upload, phase: newPhase)
            }
        }
    }

    private func handleTabChange(to tab: Tab, isInitial: Bool = false) {
        print("[DEBUG MainTabView] handleTabChange: to \(tab), isInitial: \(isInitial), activeOverlayTab: \(String(describing: activeOverlayTab))")
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
            if isInitial {
                cameraViewModel.cancelFlow()
                uploadViewModel.cancelFlow()
            }
        case .audioGuides:
             cameraViewModel.cancelFlow()
             uploadViewModel.cancelFlow()
             activeOverlayTab = nil
        }
    }

    private func handleAudioGuideTextSelected(_ summary: DiscoverySummary?) {
        let logger = Logger(subsystem: "WhatsThat.AudioGuides", category: "MainTab")

        if let summary {
            audioGuidesTargetDiscoveryId = summary.id
            audioGuidesTargetDiscoverySummary = summary
            logger.info("Text pill from Audio Guides for discovery id=\(summary.id, privacy: .public); switching to Discoveries")
        } else {
            audioGuidesTargetDiscoveryId = nil
            audioGuidesTargetDiscoverySummary = nil
            logger.info("Text pill from Audio Guides with no discovery; switching to Discoveries")
        }

        selectedTab = .discoveries
        openFirstDetailFromAudioGuides = true
    }

    private func handleDiscoveryAudioPillTapped(_ discovery: DiscoverySummary) {
        let logger = Logger(subsystem: "WhatsThat.AudioGuides", category: "MainTab")
        logger.info("Audio pill from Discovery Detail for discovery id=\(discovery.id, privacy: .public); switching to Audio Guides")
        selectedTab = .audioGuides
    }

    private func handleDiscoveryCreated(_ discoveryId: Int64) {
        // Do not pre-select the discovery from the feed; keep the overlay active during creation.
        awaitingSummaryId = discoveryId
        summaryFallbackTask?.cancel()
        summaryFallbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if awaitingSummaryId == discoveryId {
                    // Trigger a reload since we didn't get the summary callback
                    Task { await storeObserver.reload() }
                }
            }
        }
    }

    private func handleDiscoverySummaryReady(_ summary: DiscoverySummary) {
        summaryFallbackTask?.cancel()
        awaitingSummaryId = nil
        // Upsert the created summary into the store - this will automatically update the feed
        Task {
            await storeObserver.upsert(summary)
            // Also update the audio services store for immediate Audio Guides access
            await audioServices.discoveryStore.upsert(summary)
        }
        // Ensure we're showing the Discoveries tab underneath the overlay.
        selectedTab = .discoveries
        // Keep the creation overlay visible; do not cancel the flow or clear the overlay.
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

    private func handleStreamInterrupted(_ media: DiscoveryCapturedMedia) {
        print("[DEBUG MainTabView] handleStreamInterrupted called")
        activeOverlayTab = nil
        selectedTab = .discoveries
        showingProcessingAlert = true
        print("[DEBUG MainTabView] showingProcessingAlert set to true")
    }

    private func handlePollingDiscoveryReady(_ discovery: DiscoverySummary) {
        print("[DEBUG MainTabView] handlePollingDiscoveryReady called for discovery \(discovery.id)")
        
        // Just upsert the discovery so it appears in the Discoveries tab
        // The ViewModel handles populating the streaming view with discovery data
        // User will dismiss the streaming view via normal flow (X button or swipe)
        Task {
            await storeObserver.upsert(discovery)
            await audioServices.discoveryStore.upsert(discovery)
            print("[DEBUG MainTabView] Discovery \(discovery.id) upserted to stores")
        }
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
        case .audioGuides:
            return nil
        }
    }

    private func updateOverlayVisibility(for tab: Tab, state: DiscoveryCreationFlowState) {
        guard activeOverlayTab == tab else { return }
        if !shouldShowOverlay(for: state) {
            print("[DEBUG MainTabView] updateOverlayVisibility(state): clearing activeOverlayTab from \(tab) due to state \(state.phase)")
            activeOverlayTab = nil
        }
    }

    private func updateOverlayVisibility(for tab: Tab, phase: DiscoveryCreationPhase) {
        guard activeOverlayTab == tab else { return }
        if !shouldShowOverlay(for: phase) {
            print("[DEBUG MainTabView] updateOverlayVisibility(phase): clearing activeOverlayTab from \(tab) due to phase \(phase)")
            activeOverlayTab = nil
        }
    }

    private var activeOverlayPhase: DiscoveryCreationPhase? {
        // First check if there's an active overlay (used during analysis when overlaid on discoveries)
        if let tab = activeOverlayTab {
            switch tab {
            case .camera:
                return cameraViewModel.flowState.phase
            case .upload:
                return uploadViewModel.flowState.phase
            case .discoveries, .audioGuides:
                return nil
            }
        }
        
        // Also check current tab for camera/upload - covers confirming/selecting phases before analysis starts
        switch selectedTab {
        case .camera:
            return cameraViewModel.flowState.phase
        case .upload:
            return uploadViewModel.flowState.phase
        case .discoveries, .audioGuides:
            return nil
        }
    }

    /// Whether to show the global mini player
    private var shouldShowMiniPlayer: Bool {
        // Must have something playing
        guard voiceoverController.currentDiscovery != nil else { return false }
        
        // Only show in active playback states
        switch voiceoverController.playbackState {
        case .idle, .failed:
            return false
        default:
            break
        }
        
        // Audio Guides: show in list mode, hide in hero mode (hero has its own full player)
        if selectedTab == .audioGuides {
            return audioGuidesMode == .list
        }
        
        // Hide during capture/selection/confirmation stages of the creation overlay
        if let phase = activeOverlayPhase {
            switch phase {
            case .capturingInitial, .capturingRetake, .selectingInitial, .selectingRetake, .confirming, .requestingPermissions:
                return false
            case .analyzing, .idle, .cancelled, .error:
                break
            }
        }
        
        // Update mini player presence for scroll insets
        DispatchQueue.main.async {
            audioServices.miniPlayerPresence.updateVisibility(true)
        }
        
        return true
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
        case .audioGuides:
            return .audioGuides
        }
    }
}

// MARK: - Mini Player Visibility Wrapper

/// Wrapper view that properly observes VoiceoverPlaybackController to reactively show/hide the mini player.
/// This solves the issue where reading controller properties via computed properties doesn't trigger SwiftUI re-renders.
private struct MiniPlayerVisibilityWrapper<Content: View>: View {
    @ObservedObject var controller: VoiceoverPlaybackController
    @ObservedObject var miniPlayerPresence: MiniPlayerPresenceStore
    let isAudioGuidesTab: Bool
    let audioGuidesMode: AudioGuidesDisplayMode
    let activeOverlayPhase: DiscoveryCreationPhase?
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        if shouldShow {
            content()
                .animation(.easeInOut(duration: 0.25), value: shouldShow)
                .onAppear {
                    miniPlayerPresence.updateVisibility(true)
                }
        }
    }
    
    private var shouldShow: Bool {
        // FIRST: Check if visibility has been explicitly disabled
        // This allows other views (like DiscoveryDetailOverlayView) to hide the global player
        guard miniPlayerPresence.isVisible else { return false }
        
        // Must have something playing
        guard controller.currentDiscovery != nil else { return false }
        
        // Only show in active playback states
        switch controller.playbackState {
        case .idle, .failed:
            return false
        default:
            break
        }
        
        // Audio Guides: show in list mode, hide in hero mode (hero has its own full player)
        if isAudioGuidesTab {
            return audioGuidesMode == .list
        }
        
        // Hide during capture/selection/confirmation stages of the creation overlay
        if let phase = activeOverlayPhase {
            switch phase {
            case .capturingInitial, .capturingRetake, .selectingInitial, .selectingRetake, .confirming, .requestingPermissions:
                return false
            case .analyzing, .idle, .cancelled, .error:
                break
            }
        }
        
        return true
    }
}

// MARK: - Generation Toast Overlay

/// Wrapper that observes AudioServicesContainer to show generation complete toast
private struct GenerationToastOverlay: View {
    @ObservedObject var audioServices: AudioServicesContainer
    @Environment(\.colorScheme) private var colorScheme
    
    // Mini player constants (from MiniPlayerView)
    private let miniPlayerHeight: CGFloat = 110  // artworkDiameter
    private let miniPlayerBottomPadding: CGFloat = 49 + 2  // tab bar + spacing
    // Tab bar height + spacing
    private let tabBarOffset: CGFloat = 49 + 8
    // Small gap between toast and mini player
    private let toastMiniPlayerGap: CGFloat = 8
    
    private var isMiniPlayerVisible: Bool {
        guard audioServices.playbackController.currentDiscovery != nil else { return false }
        // Check if playback state is active (not idle or failed)
        switch audioServices.playbackController.playbackState {
        case .idle, .failed:
            return false
        default:
            return true
        }
    }
    
    private var bottomPadding: CGFloat {
        isMiniPlayerVisible 
            ? miniPlayerBottomPadding + miniPlayerHeight + toastMiniPlayerGap
            : tabBarOffset
    }
    
    var body: some View {
        let toasts = audioServices.pendingGenerationToasts
        let toastCount = toasts.count
        
        if let frontToast = toasts.first {
            ZStack(alignment: .topTrailing) {
                GenerationCompleteToastView(
                    toast: frontToast,
                    onPlayNow: { audioServices.handleToastPlayNow() },
                    onPlayNext: { audioServices.handleToastPlayNext() },
                    onAddToQueue: { audioServices.handleToastAddToQueue() },
                    onDismiss: { audioServices.dismissGenerationToast() }
                )
                
                // Badge showing remaining toast count (if more than 1)
                if toastCount > 1 {
                    pendingCountBadge(count: toastCount)
                        .offset(x: -8, y: -8)
                }
            }
            // Force view refresh when toast changes to update image and content
            .id(frontToast.id)
            .padding(.bottom, bottomPadding)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: frontToast.id)
            .zIndex(10)
        }
    }
    
    /// Badge showing how many toasts are pending
    @ViewBuilder
    private func pendingCountBadge(count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .frame(minWidth: 22, minHeight: 22)
            .background(
                Circle()
                    .fill(BrandColors.logo)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}

