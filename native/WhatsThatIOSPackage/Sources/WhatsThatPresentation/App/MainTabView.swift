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
    @State private var audioGuidesMode: AudioGuidesDisplayMode = .hero
    @State private var openFirstDetailFromAudioGuides = false
    @State private var audioGuidesTargetDiscoveryId: Int64?
    @State private var audioGuidesTargetDiscoverySummary: DiscoverySummary?

    // Modal presentation state for creation flow (replaces overlay ZStack)
    @State private var activeCreationFlowType: DiscoveryCreationFlowType?
    // Pending flow type for "Discover More" or tab tap during dismiss animation
    @State private var pendingCreationFlowAfterDismiss: DiscoveryCreationFlowType?
    // True between activeCreationFlowType=nil and fullScreenCover's onDismiss callback.
    // Prevents setting a new activeCreationFlowType during the dismiss animation,
    // which SwiftUI silently drops (leaving the state stuck).
    @State private var isDismissingModal = false

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
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // Camera tab — pure trigger, no content
                TabTriggerPlaceholder()
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

                // Gallery tab — pure trigger, no content
                TabTriggerPlaceholder()
                    .tag(Tab.upload)
                    .tabItem {
                        Label("Gallery", systemImage: "photo.on.rectangle")
                    }
            }

            // Global mini player overlay (visible when no modal is showing)
            MiniPlayerVisibilityWrapper(
                controller: audioServices.playbackController,
                miniPlayerPresence: audioServices.miniPlayerPresence,
                isAudioGuidesTab: selectedTab == .audioGuides,
                audioGuidesMode: audioGuidesMode,
                activeOverlayPhase: nil
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
        .audioServices(audioServices)
        // Creation flow presented as a fullScreenCover modal
        .fullScreenCover(item: $activeCreationFlowType, onDismiss: {
            // Dismiss animation is complete — safe to present again
            isDismissingModal = false
            // Check if there's a pending request (from "Discover More" or tab tap during dismiss)
            if let pendingType = pendingCreationFlowAfterDismiss {
                pendingCreationFlowAfterDismiss = nil
                // Don't call startFlow() here — the modal's .task will call it once
                // the view is actually on screen, ensuring the photo picker / camera
                // presents on the correct view controller.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Present instantly (no slide-up animation)
                    var transaction = Transaction(animation: .none)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        activeCreationFlowType = pendingType
                    }
                }
            }
            // selectedTab is already .discoveries — set by the onDismiss closure
            // inside DiscoveryCreationFlowView before activeCreationFlowType was nil'd.
            // Don't override it here as it can race with user tab selection.
        }) { flowType in
            let viewModel = flowType == .camera ? cameraViewModel : uploadViewModel
            DiscoveryCreationFlowView(
                viewModel: viewModel,
                onRequestNewDiscovery: { type in handleNewDiscoveryRequest(type: type) },
                onDismiss: {
                    selectedTab = .discoveries
                    isDismissingModal = true
                    // Dismiss instantly (no slide-down animation)
                    var transaction = Transaction(animation: .none)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        activeCreationFlowType = nil
                    }
                },
                makeCreditsViewModel: makeCreditsViewModel,
                fetchRecentDiscoveries: { storeObserver.discoveries },
                audioServices: audioServices,
                loadVoiceoverPreferences: loadVoiceoverPreferences,
                saveVoiceoverPreferences: saveVoiceoverPreferences,
                fetchVoiceOptions: fetchVoiceOptions,
                fetchVoiceSampleURL: fetchVoiceSampleURL,
                loadIPoPPreferences: loadIPoPPreferences,
                saveIPoPPreferences: saveIPoPPreferences
            )
            .task {
                // Start the flow once the modal is on screen. This ensures the
                // camera/photo picker presents on the modal's view controller,
                // not the root VC. Without this, the picker races with the
                // fullScreenCover presentation and can block it entirely.
                if viewModel.flowState.phase == .idle {
                    viewModel.startFlow()
                }
            }
        }
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
        .onChange(of: selectedTab) { _, newValue in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                handleTabChange(to: newValue)
            }
        }
    }

    private func handleTabChange(to tab: Tab, isInitial: Bool = false) {
        // Track screen safety for compliance overlay deferral
        let isSafeScreen = (tab == .discoveries || tab == .audioGuides)
        onScreenSafetyChanged?(isSafeScreen)

        // Camera/Gallery tabs are pure triggers — present the creation flow modal
        if tab == .camera || tab == .upload {
            let flowType: DiscoveryCreationFlowType = tab == .camera ? .camera : .upload
            // Don't start a new flow if a modal is already active
            guard activeCreationFlowType == nil else { return }
            // If a dismiss animation is in progress, queue the request.
            // Setting activeCreationFlowType during the animation causes SwiftUI to
            // silently drop the presentation, leaving the state stuck.
            if isDismissingModal {
                pendingCreationFlowAfterDismiss = flowType
                return
            }
            // Don't call startFlow() here — the modal's .task will call it once
            // the fullScreenCover is on screen. Calling it here races with the
            // fullScreenCover presentation: the camera/photo picker tries to present
            // on the root VC before the modal is ready, blocking the modal presentation.
            // Present instantly (no slide-up animation)
            var transaction = Transaction(animation: .none)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                activeCreationFlowType = flowType
            }
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
        // Do not pre-select the discovery from the feed; keep the modal active during creation.
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

    /// Handles "Discover More" request from within the creation flow modal.
    /// Stores the pending type, unsubscribes the current flow, and dismisses.
    /// The fullScreenCover's onDismiss callback picks up the pending type and re-presents.
    private func handleNewDiscoveryRequest(type: DiscoveryCreationFlowType) {
        let currentViewModel = activeCreationFlowType == .some(.camera) ? cameraViewModel : uploadViewModel
        currentViewModel.unsubscribe()
        pendingCreationFlowAfterDismiss = type
        isDismissingModal = true
        // Dismiss instantly (no slide-down animation)
        var transaction = Transaction(animation: .none)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeCreationFlowType = nil
        }
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

}

// MARK: - Tab Trigger Placeholder

/// Branded placeholder shown briefly on Camera/Gallery tab before the modal presents.
/// Uses the app logo with a spinning ring for a polished loading appearance.
private struct TabTriggerPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            (colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background)
                .ignoresSafeArea()
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                BrandColors.spinner.opacity(0.1),
                                BrandColors.spinner
                            ]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(
                        .linear(duration: 1.2).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
            }
        }
        .onAppear { isAnimating = true }
    }
}

