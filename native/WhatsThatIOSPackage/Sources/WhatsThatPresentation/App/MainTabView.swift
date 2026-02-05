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
    @Environment(\.colorScheme) private var colorScheme
    private enum Tab: Hashable {
        case camera
        case discoveries
        case upload
        case audioGuides
    }

    @State private var selectedTab: Tab
    /// ViewModels are owned by RootContentView as @StateObject, passed here as @ObservedObject
    @ObservedObject private var cameraViewModel: DiscoveryCreationFlowViewModel
    @ObservedObject private var uploadViewModel: DiscoveryCreationFlowViewModel
    /// AudioServicesContainer is passed from RootContentView to ensure single shared instance
    @ObservedObject private var audioServices: AudioServicesContainer
    @ObservedObject private var storeObserver: DiscoveryStoreObserver
    @State private var pendingDiscoveryId: Int64?
    @State private var awaitingSummaryId: Int64?
    @State private var summaryFallbackTask: Task<Void, Never>?
    @State private var activeOverlayTab: Tab?
    @State private var audioGuidesMode: AudioGuidesDisplayMode = .hero
    @State private var openFirstDetailFromAudioGuides = false
    @State private var audioGuidesTargetDiscoveryId: Int64?
    @State private var audioGuidesTargetDiscoverySummary: DiscoverySummary?

    // Credits sheet state (opened from various triggers)
    @State private var showCreditsSheetFromExhausted: Bool = false
    @State private var creditsExhaustedCreditsViewModel: CreditsViewModel?

    // Free credits exhausted full-screen modal (triggered from either camera or upload viewModel)
    @State private var showFreeCreditsExhaustedModal: Bool = false

    // Flag to present credits sheet AFTER fullScreenCover dismisses (avoids SwiftUI presentation race)
    @State private var shouldPresentCreditsAfterDismiss: Bool = false

    // Reference to session manager (singleton, not StateObject since it's shared globally)
    private var sessionManager: DiscoverySessionManager { DiscoverySessionManager.shared }

    private let deletionUseCase: DiscoveryDeletionUseCase
    private let onSignOut: () -> Void
    private let onSettings: (() -> Void)?
    /// Binding indicating whether the settings sheet is currently presented
    @Binding private var isSettingsPresented: Bool
    private let makeCreditsViewModel: (() -> CreditsViewModel)?
    private let onScreenSafetyChanged: ((Bool) -> Void)?

    // Post-purchase configuration closures
    private let loadVoiceoverPreferences: (() async -> VoiceoverPreferences)?
    private let saveVoiceoverPreferences: ((VoiceoverPreferences) async -> Void)?
    private let fetchVoiceOptions: (() async -> [VoiceModelOption])?
    private let fetchVoiceSampleURL: ((String) async -> URL?)?
    private let loadIPoPPreferences: (() async -> IPoPPreferences?)?
    private let saveIPoPPreferences: ((IPoPPreferences) async -> Void)?

    init(
        storeObserver: DiscoveryStoreObserver,
        deletionUseCase: DiscoveryDeletionUseCase,
        cameraViewModel: DiscoveryCreationFlowViewModel,
        uploadViewModel: DiscoveryCreationFlowViewModel,
        audioServices: AudioServicesContainer,
        initialTab: MainTabDestination = .discoveries,
        onSignOut: @escaping () -> Void,
        onSettings: (() -> Void)? = nil,
        isSettingsPresented: Binding<Bool> = .constant(false),
        makeCreditsViewModel: (() -> CreditsViewModel)? = nil,
        onScreenSafetyChanged: ((Bool) -> Void)? = nil,
        loadVoiceoverPreferences: (() async -> VoiceoverPreferences)? = nil,
        saveVoiceoverPreferences: ((VoiceoverPreferences) async -> Void)? = nil,
        fetchVoiceOptions: (() async -> [VoiceModelOption])? = nil,
        fetchVoiceSampleURL: ((String) async -> URL?)? = nil,
        loadIPoPPreferences: (() async -> IPoPPreferences?)? = nil,
        saveIPoPPreferences: ((IPoPPreferences) async -> Void)? = nil
    ) {
        self._storeObserver = ObservedObject(wrappedValue: storeObserver)
        self.deletionUseCase = deletionUseCase
        self.onSignOut = onSignOut
        self.onSettings = onSettings
        self._isSettingsPresented = isSettingsPresented
        self.makeCreditsViewModel = makeCreditsViewModel
        self.onScreenSafetyChanged = onScreenSafetyChanged
        self.loadVoiceoverPreferences = loadVoiceoverPreferences
        self.saveVoiceoverPreferences = saveVoiceoverPreferences
        self.fetchVoiceOptions = fetchVoiceOptions
        self.fetchVoiceSampleURL = fetchVoiceSampleURL
        self.loadIPoPPreferences = loadIPoPPreferences
        self.saveIPoPPreferences = saveIPoPPreferences
        _selectedTab = State(initialValue: Self.tab(for: initialTab))
        _cameraViewModel = ObservedObject(wrappedValue: cameraViewModel)
        _uploadViewModel = ObservedObject(wrappedValue: uploadViewModel)
        _audioServices = ObservedObject(wrappedValue: audioServices)

        // Enforce consistent tab bar background to prevent transparency issues during custom transitions
        Self.configureTabBarAppearance()
    }

    // Convenience accessor
    private var voiceoverController: VoiceoverPlaybackController {
        audioServices.playbackController
    }
    

    
    var body: some View {
        let _ = print("[MainTabView] body evaluated: selectedTab=\(selectedTab), activeOverlayTab=\(String(describing: activeOverlayTab))")
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                DiscoveryCreationFlowView(
                    viewModel: cameraViewModel,
                    placeholderEmoji: "📷",
                    ctaTitle: "Take a photo to discover",
                    retryTitle: "Try again",
                    makeCreditsViewModel: makeCreditsViewModel,
                    fetchRecentDiscoveries: { storeObserver.discoveries },
                    loadVoiceoverPreferences: loadVoiceoverPreferences,
                    saveVoiceoverPreferences: saveVoiceoverPreferences,
                    fetchVoiceOptions: fetchVoiceOptions,
                    fetchVoiceSampleURL: fetchVoiceSampleURL,
                    loadIPoPPreferences: loadIPoPPreferences,
                    saveIPoPPreferences: saveIPoPPreferences
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
                    isSettingsSelected: isSettingsPresented,
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
                    makeCreditsViewModel: makeCreditsViewModel,
                    loadVoiceoverPreferences: loadVoiceoverPreferences,
                    saveVoiceoverPreferences: saveVoiceoverPreferences,
                    fetchVoiceOptions: fetchVoiceOptions,
                    fetchVoiceSampleURL: fetchVoiceSampleURL,
                    loadIPoPPreferences: loadIPoPPreferences,
                    saveIPoPPreferences: saveIPoPPreferences
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
                    makeCreditsViewModel: makeCreditsViewModel,
                    fetchRecentDiscoveries: { storeObserver.discoveries },
                    loadVoiceoverPreferences: loadVoiceoverPreferences,
                    saveVoiceoverPreferences: saveVoiceoverPreferences,
                    fetchVoiceOptions: fetchVoiceOptions,
                    fetchVoiceSampleURL: fetchVoiceSampleURL,
                    loadIPoPPreferences: loadIPoPPreferences,
                    saveIPoPPreferences: saveIPoPPreferences
                )
                .tag(Tab.upload)
                .tabItem {
                    Label("Gallery", systemImage: "photo.on.rectangle")
                }
            }
        
            // Creation overlay
            // During analyzing phase, leave space for tab bar so user can navigate
            if let overlayTab = activeOverlayTab,
               let overlayViewModel = viewModel(for: overlayTab),
               shouldShowOverlay(for: overlayViewModel.flowState)
            {
                DiscoveryCreationFlowView(
                    viewModel: overlayViewModel,
                    placeholderEmoji: overlayTab == .camera ? "📷" : "🖼️",
                    ctaTitle: overlayTab == .camera ? "Take a photo to discover" : "Choose a photo from your gallery",
                    retryTitle: overlayTab == .camera ? "Try again" : "Select again",
                    isOverlay: true,
                    onDiscoverAnother: {
                        // Handle "Discover Another" from audio generating modal.
                        // This callback is invoked AFTER the modal is fully dismissed (via onDismiss).
                        let targetTab: Tab = overlayTab == .camera ? .camera : .upload
                        let targetViewModel = overlayTab == .camera ? cameraViewModel : uploadViewModel

                        // Unsubscribe preserves state for cancellation restoration.
                        // If user cancels the new capture, they'll return to this completed discovery.
                        targetViewModel.unsubscribe()

                        // Switch to the target tab so user sees confirm stage there after capture.
                        // The onChange handler dispatches handleTabChange async, so retake() runs first.
                        // By the time handleTabChange runs, flowState is already capturing, so
                        // canStartFlow() returns false and won't interfere with the retake flow.
                        selectedTab = targetTab

                        // Start new capture via retake() which keeps preservedState intact.
                        targetViewModel.retake()
                    },
                    makeCreditsViewModel: makeCreditsViewModel,
                    fetchRecentDiscoveries: { storeObserver.discoveries },
                    loadVoiceoverPreferences: loadVoiceoverPreferences,
                    saveVoiceoverPreferences: saveVoiceoverPreferences,
                    fetchVoiceOptions: fetchVoiceOptions,
                    fetchVoiceSampleURL: fetchVoiceSampleURL,
                    loadIPoPPreferences: loadIPoPPreferences,
                    saveIPoPPreferences: saveIPoPPreferences
                )
                .padding(.bottom, overlayViewModel.flowState.phase == .analyzing ? 49 : 0)
                .transition(.opacity)
                .zIndex(1)
            }
            
            // Global mini player overlay - wrapped to properly observe controller changes
            // Use zIndex(2) when analyzing to appear above the creation overlay (zIndex 1)
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
                // On iPad: reduce clearance as requested (safely above home indicator)
                .padding(.bottom, UIDevice.isIPad ? 20 : 49 + 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .zIndex(activeOverlayPhase == .analyzing ? 2 : 0)
            

            
            // Unified toast overlay for all toast types (discovery + audio guide)
            UnifiedToastOverlay(
                audioServices: audioServices,
                miniPlayerPresence: audioServices.miniPlayerPresence,
                onViewDiscovery: { discoveryId in
                    self.pendingDiscoveryId = discoveryId
                    self.selectedTab = .discoveries
                },
                onGenerateAudio: { summary in
                    self.audioServices.playbackController.requestVoiceover(for: summary)
                }
            )
        }
        .tint(colorScheme == .dark ? BrandColors.logo : BrandColors.Light.tabSelected)
        .sheet(isPresented: $showCreditsSheetFromExhausted, onDismiss: {
            creditsExhaustedCreditsViewModel = nil
        }) {
            if let viewModel = creditsExhaustedCreditsViewModel {
                NavigationStack {
                    CreditsView(
                        viewModel: viewModel,
                        loadVoiceoverPreferences: loadVoiceoverPreferences ?? { VoiceoverPreferences(autoEnabled: false, voiceModelId: "", ttsModel: "s1") },
                        saveVoiceoverPreferences: saveVoiceoverPreferences ?? { _ in },
                        fetchVoiceOptions: fetchVoiceOptions ?? { [] },
                        fetchVoiceSampleURL: fetchVoiceSampleURL ?? { _ in nil },
                        loadIPoPPreferences: loadIPoPPreferences ?? { nil },
                        saveIPoPPreferences: saveIPoPPreferences ?? { _ in }
                    )
                }
                .presentationDetents([.fraction(0.8), .large])
            } else {
                // Fallback view if credits view model failed to initialize
                CreditsSheetErrorView(
                    onRetry: {
                        if let maker = makeCreditsViewModel {
                            creditsExhaustedCreditsViewModel = maker()
                        }
                    },
                    onDismiss: {
                        showCreditsSheetFromExhausted = false
                    }
                )
                .presentationDetents([.fraction(0.5)])
            }
        }
        .audioServices(audioServices)
        .onAppear {
            cameraViewModel.onDiscoveryCreated = handleDiscoveryCreated
            uploadViewModel.onDiscoveryCreated = handleDiscoveryCreated
            cameraViewModel.onDiscoverySummaryReady = handleDiscoverySummaryReady
            uploadViewModel.onDiscoverySummaryReady = handleDiscoverySummaryReady
            
            cameraViewModel.onPollingDiscoveryReady = { discovery in
                handlePollingDiscoveryReady(discovery)
            }
            uploadViewModel.onPollingDiscoveryReady = { discovery in
                handlePollingDiscoveryReady(discovery)
            }

            // Handle state restoration when user cancels "Discover Another" (e.g., cancels camera picker)
            // This restores the overlay and switches back to discoveries tab
            cameraViewModel.onStateRestored = { _ in
                activeOverlayTab = .camera
                selectedTab = .discoveries
            }
            uploadViewModel.onStateRestored = { _ in
                activeOverlayTab = .upload
                selectedTab = .discoveries
            }

            // Note: Audio generation is now triggered exclusively via sessionManager.onDiscoveryCompleted
            // (configured below) which runs before sessionDidComplete updates UI state.
            
            // Configure session manager callbacks for background discovery completion
            sessionManager.onDiscoveryCompleted = { [weak audioServices, weak storeObserver] summary, generateAudio in
                // Refresh discovery list to include new discovery
                Task { @MainActor in
                    await storeObserver?.upsert(summary)
                }
                // Trigger audio generation if user requested it
                if generateAudio {
                    audioServices?.playbackController.requestVoiceover(for: summary)
                }
            }
            sessionManager.onDiscoveryFailed = { _, _ in
                // Background discovery failures are silently ignored for now
            }

            handleTabChange(to: selectedTab, isInitial: true)
        }
        .onDisappear {
            summaryFallbackTask?.cancel()
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            print("[MainTabView] onChange(selectedTab): \(oldValue) -> \(newValue)")
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
        .onChange(of: activeOverlayTab) { oldValue, newValue in
            print("[MainTabView] onChange(activeOverlayTab): \(String(describing: oldValue)) -> \(String(describing: newValue))")
        }
        .onReceive(cameraViewModel.analysisBeganPublisher) { type in
            handleAnalysisBegan(type)
        }
        .onReceive(uploadViewModel.analysisBeganPublisher) { type in
            handleAnalysisBegan(type)
        }
        // Watch for free credits exhausted modal from either viewModel
        // We present at MainTabView level to ensure visibility regardless of flow state
        .onChange(of: cameraViewModel.showFreeCreditsExhaustedAtConfirm) { _, show in
            if show {
                // Reset viewModel flag immediately to prevent DiscoveryCreationFlowView from also presenting
                cameraViewModel.showFreeCreditsExhaustedAtConfirm = false
                showFreeCreditsExhaustedModal = true
            }
        }
        .onChange(of: uploadViewModel.showFreeCreditsExhaustedAtConfirm) { _, show in
            if show {
                // Reset viewModel flag immediately to prevent DiscoveryCreationFlowView from also presenting
                uploadViewModel.showFreeCreditsExhaustedAtConfirm = false
                showFreeCreditsExhaustedModal = true
            }
        }
        .fullScreenCover(isPresented: $showFreeCreditsExhaustedModal, onDismiss: {
            // Present credits sheet AFTER fullScreenCover is fully dismissed to avoid SwiftUI race condition
            if shouldPresentCreditsAfterDismiss {
                shouldPresentCreditsAfterDismiss = false
                if let maker = makeCreditsViewModel {
                    creditsExhaustedCreditsViewModel = maker()
                    // Small delay to ensure clean presentation after dismiss animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showCreditsSheetFromExhausted = true
                    }
                }
            }
        }) {
            CreditsExhaustedFullScreenView(
                discoveries: Array(storeObserver.discoveries.prefix(3)),
                playbackController: audioServices.playbackController,
                onGetCredits: {
                    // Set flag to present credits sheet after this fullScreenCover dismisses
                    shouldPresentCreditsAfterDismiss = true
                    showFreeCreditsExhaustedModal = false
                },
                onDismiss: {
                    shouldPresentCreditsAfterDismiss = false
                    showFreeCreditsExhaustedModal = false
                    // Cancel flows and return to discoveries - user hit intro limit
                    cameraViewModel.cancelFlow()
                    uploadViewModel.cancelFlow()
                    activeOverlayTab = nil
                    selectedTab = .discoveries
                }
            )
        }
    }

    private func handleTabChange(to tab: Tab, isInitial: Bool = false) {
        print("[MainTabView] handleTabChange called: tab=\(tab), isInitial=\(isInitial), activeOverlayTab=\(String(describing: activeOverlayTab))")
        // Track screen safety for compliance overlay deferral
        // Discoveries and Audio Guides are "safe" screens (not mid-action)
        // Camera and Upload are "unsafe" (user may be capturing/selecting)
        let isSafeScreen = (tab == .discoveries || tab == .audioGuides) && activeOverlayTab == nil
        onScreenSafetyChanged?(isSafeScreen)

        switch tab {
        case .camera:
            // Check if upload is analyzing - unsubscribe to allow background completion
            if case .analyzing = uploadViewModel.flowState {
                uploadViewModel.unsubscribe()
            } else {
                uploadViewModel.cancelFlow()
            }
            cameraViewModel.startFlow()
            activeOverlayTab = nil
        case .upload:
            // Check if camera is analyzing - unsubscribe to allow background completion
            if case .analyzing = cameraViewModel.flowState {
                cameraViewModel.unsubscribe()
            } else {
                cameraViewModel.cancelFlow()
            }
            uploadViewModel.startFlow()
            activeOverlayTab = nil
        case .discoveries:
            // Unsubscribe or cancel based on whether analyzing
            if activeOverlayTab != .camera {
                if case .analyzing = cameraViewModel.flowState {
                    cameraViewModel.unsubscribe()
                } else {
                    cameraViewModel.cancelFlow()
                }
            }
            if activeOverlayTab != .upload {
                if case .analyzing = uploadViewModel.flowState {
                    uploadViewModel.unsubscribe()
                } else {
                    uploadViewModel.cancelFlow()
                }
            }
            if isInitial {
                cameraViewModel.cancelFlow()
                uploadViewModel.cancelFlow()
            }
        case .audioGuides:
            // Unsubscribe or cancel based on whether analyzing
            if case .analyzing = cameraViewModel.flowState {
                cameraViewModel.unsubscribe()
            } else {
                cameraViewModel.cancelFlow()
            }
            if case .analyzing = uploadViewModel.flowState {
                uploadViewModel.unsubscribe()
            } else {
                uploadViewModel.cancelFlow()
            }
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
        print("[MainTabView] handleAnalysisBegan called with type: \(type)")
        print("[MainTabView] BEFORE: selectedTab=\(selectedTab), activeOverlayTab=\(String(describing: activeOverlayTab))")
        switch type {
        case .camera:
            activeOverlayTab = .camera
        case .upload:
            activeOverlayTab = .upload
        }
        selectedTab = .discoveries
        print("[MainTabView] AFTER: selectedTab=\(selectedTab), activeOverlayTab=\(String(describing: activeOverlayTab))")
    }

    private func handlePollingDiscoveryReady(_ discovery: DiscoverySummary) {
        // Upsert the discovery so it appears in the Discoveries tab
        // The ViewModel handles populating the streaming view with discovery data
        // User will dismiss the streaming view via normal flow (X button or swipe)
        Task {
            await storeObserver.upsert(discovery)
            await audioServices.discoveryStore.upsert(discovery)
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
            activeOverlayTab = nil
        }
    }

    private func updateOverlayVisibility(for tab: Tab, phase: DiscoveryCreationPhase) {
        print("[MainTabView] updateOverlayVisibility: tab=\(tab), phase=\(phase), activeOverlayTab=\(String(describing: activeOverlayTab))")
        guard activeOverlayTab == tab else {
            print("[MainTabView] updateOverlayVisibility: guard failed, activeOverlayTab != tab")
            return
        }
        if !shouldShowOverlay(for: phase) {
            print("[MainTabView] updateOverlayVisibility: clearing activeOverlayTab")
            activeOverlayTab = nil
            // Screen becomes safe when overlay dismissed on discoveries/audioGuides
            if selectedTab == .discoveries || selectedTab == .audioGuides {
                onScreenSafetyChanged?(true)
            }
        } else {
            // Screen is unsafe when overlay is active
            onScreenSafetyChanged?(false)
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

    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        // This effectively disables the 'break-through' transparency when scrolling to the edge,
        // ensuring the tab bar always has its standard background material.
        // This is necessary because our custom sheet transitions can confuse the system's
        // automatic bar visibility logic.
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().standardAppearance = appearance
    }

    private func presentCreditsSheetFromExhausted() {
        guard let factory = makeCreditsViewModel else { return }
        creditsExhaustedCreditsViewModel = factory()
        showCreditsSheetFromExhausted = true
    }
}

// MARK: - Credits Sheet Error View

/// Fallback view shown when the credits sheet fails to load properly
private struct CreditsSheetErrorView: View {
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Spacer()

            VStack(spacing: BrandSpacing.medium) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(palette.textSecondary)

                Text("Something went wrong")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)

                Text("We couldn't load the credits page. Please try again.")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.large)
            }

            Spacer()

            VStack(spacing: BrandSpacing.small) {
                Button(action: onRetry) {
                    Text("Try Again")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    Capsule()
                        .fill(palette.primaryAction)
                )

                Button(action: onDismiss) {
                    Text("Close")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.xLarge)
        }
        .background(palette.background.ignoresSafeArea())
    }
}

