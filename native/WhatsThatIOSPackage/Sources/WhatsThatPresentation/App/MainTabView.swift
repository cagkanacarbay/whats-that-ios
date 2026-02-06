import Combine
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
    @ObservedObject private var coordinator: CreationFlowCoordinator
    @ObservedObject private var audioServices: AudioServicesContainer
    @ObservedObject private var storeObserver: DiscoveryStoreObserver
    @State private var pendingDiscoveryId: Int64?
    @State private var audioGuidesMode: AudioGuidesDisplayMode = .hero
    @State private var openFirstDetailFromAudioGuides = false
    @State private var audioGuidesTargetDiscoveryId: Int64?
    @State private var audioGuidesTargetDiscoverySummary: DiscoverySummary?

    private let deletionUseCase: DiscoveryDeletionUseCase
    private let onSignOut: () -> Void
    private let onSettings: (() -> Void)?
    @Binding private var isSettingsPresented: Bool
    private let onScreenSafetyChanged: ((Bool) -> Void)?

    init(
        coordinator: CreationFlowCoordinator,
        storeObserver: DiscoveryStoreObserver,
        deletionUseCase: DiscoveryDeletionUseCase,
        audioServices: AudioServicesContainer,
        initialTab: MainTabDestination = .discoveries,
        onSignOut: @escaping () -> Void,
        onSettings: (() -> Void)? = nil,
        isSettingsPresented: Binding<Bool> = .constant(false),
        onScreenSafetyChanged: ((Bool) -> Void)? = nil
    ) {
        self._coordinator = ObservedObject(wrappedValue: coordinator)
        self._storeObserver = ObservedObject(wrappedValue: storeObserver)
        self._audioServices = ObservedObject(wrappedValue: audioServices)
        self.deletionUseCase = deletionUseCase
        self.onSignOut = onSignOut
        self.onSettings = onSettings
        self._isSettingsPresented = isSettingsPresented
        self.onScreenSafetyChanged = onScreenSafetyChanged
        _selectedTab = State(initialValue: Self.tab(for: initialTab))

        Self.configureTabBarAppearance()
    }

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
                    },
                    onReconnectSession: { item in
                        coordinator.reconnectToSession(item)
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
                    makeCreditsViewModel: coordinator.makeCreditsViewModel,
                    loadVoiceoverPreferences: coordinator.loadVoiceoverPreferences,
                    saveVoiceoverPreferences: coordinator.saveVoiceoverPreferences,
                    fetchVoiceOptions: coordinator.fetchVoiceOptions,
                    fetchVoiceSampleURL: coordinator.fetchVoiceSampleURL,
                    loadIPoPPreferences: coordinator.loadIPoPPreferences,
                    saveIPoPPreferences: coordinator.saveIPoPPreferences
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
        // Creation flow presented as a fullScreenCover modal (driven by coordinator)
        .fullScreenCover(item: $coordinator.activeFlowType, onDismiss: {
            coordinator.handleModalDismissCompleted()
        }) { flowType in
            let viewModel = coordinator.viewModel(for: flowType)
            DiscoveryCreationFlowView(
                viewModel: viewModel,
                onDismiss: {
                    selectedTab = .discoveries
                    coordinator.dismissFlow()
                },
                makeCreditsViewModel: coordinator.makeCreditsViewModel,
                fetchRecentDiscoveries: { storeObserver.discoveries },
                audioServices: coordinator.audioServices,
                loadVoiceoverPreferences: coordinator.loadVoiceoverPreferences,
                saveVoiceoverPreferences: coordinator.saveVoiceoverPreferences,
                fetchVoiceOptions: coordinator.fetchVoiceOptions,
                fetchVoiceSampleURL: coordinator.fetchVoiceSampleURL,
                loadIPoPPreferences: coordinator.loadIPoPPreferences,
                saveIPoPPreferences: coordinator.saveIPoPPreferences
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
            coordinator.configureSessionManager()
            handleTabChange(to: selectedTab, isInitial: true)
        }
        .onDisappear {
            coordinator.cleanup()
        }
        .onChange(of: selectedTab) { _, newValue in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                handleTabChange(to: newValue)
            }
        }
        // Observe ViewModel published properties via coordinator's VMs.
        .onReceive(coordinator.cameraViewModel.$createdDiscoveryId.compactMap { $0 }) { discoveryId in
            coordinator.handleDiscoveryCreated(discoveryId)
        }
        .onReceive(coordinator.uploadViewModel.$createdDiscoveryId.compactMap { $0 }) { discoveryId in
            coordinator.handleDiscoveryCreated(discoveryId)
        }
        .onReceive(coordinator.cameraViewModel.$completedDiscovery.compactMap { $0 }) { summary in
            coordinator.handleCompletedDiscovery(summary)
        }
        .onReceive(coordinator.uploadViewModel.$completedDiscovery.compactMap { $0 }) { summary in
            coordinator.handleCompletedDiscovery(summary)
        }
    }

    // MARK: - Tab Change

    private func handleTabChange(to tab: Tab, isInitial: Bool = false) {
        // Track screen safety for compliance overlay deferral
        let isSafeScreen = (tab == .discoveries || tab == .audioGuides)
        onScreenSafetyChanged?(isSafeScreen)

        // Camera/Gallery tabs are pure triggers — present the creation flow modal
        if tab == .camera || tab == .upload {
            let flowType: DiscoveryCreationFlowType = tab == .camera ? .camera : .upload
            coordinator.tryPresentFlow(type: flowType)
        }
    }

    // MARK: - Audio Guides Navigation

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

    // MARK: - Helpers

    private static func tab(for destination: MainTabDestination) -> Tab {
        switch destination {
        case .camera: return .camera
        case .discoveries: return .discoveries
        case .upload: return .upload
        case .audioGuides: return .audioGuides
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
