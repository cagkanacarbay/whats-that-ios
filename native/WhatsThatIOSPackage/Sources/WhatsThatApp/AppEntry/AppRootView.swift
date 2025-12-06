import Foundation
import SwiftUI
import WhatsThatDomain
import WhatsThatPresentation
import WhatsThatShared

public struct AppRootView: View {
    private let container: AppDependencyContainer
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locationPermissionCache = LocationPermissionCache.shared
    #endif

    public init(
        configuration: AppConfiguration = .fromBundle(),
        session: URLSession = .shared
    ) {
        self.container = AppDependencyContainer.bootstrap(
            configuration: configuration,
            session: session
        )
    }

    public var body: some View {
        #if os(iOS)
        let makeViewModel: (DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel = {
            container.makeDiscoveryCreationViewModel(for: $0)
        }
        #else
        let makeViewModel: (DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel = { _ in
            fatalError("Discovery creation flow is only supported on iOS.")
        }
        #endif

        #if os(iOS)
        let audioServicesFactory: (() -> AudioServicesContainer)? = {
            container.makeAudioServicesContainer()
        }
        let creditsFactory: (() -> CreditsViewModel)? = {
            container.makeCreditsViewModel()
        }
        let balanceFetcher: () async -> Result<Int, Error> = {
            await container.fetchCreditBalance()
        }
        let clearAppStoreLocal: () async -> Result<Void, Error> = {
            await container.clearAppStoreLocalState()
        }
        let loadVoiceoverPreferences: () async -> VoiceoverPreferences = {
            await container.loadVoiceoverPreferences()
        }
        let saveVoiceoverPreferences: (VoiceoverPreferences) async -> Void = { prefs in
            await container.saveVoiceoverPreferences(prefs)
        }
        let fetchVoiceOptions: () async -> [VoiceModelOption] = {
            await container.fetchVoiceOptions()
        }
        let fetchVoiceSampleURL: (String) async -> URL? = {
            await container.fetchVoiceSampleURL(voiceName: $0)
        }
        let loadIPoPPreferences: () async -> IPoPPreferences? = {
            await container.loadIPoPPreferences()
        }
        let saveIPoPPreferences: (IPoPPreferences) async -> Void = { preferences in
            await container.saveIPoPPreferences(preferences)
        }
        let resetIPoPPreferences: () async -> Void = {
            await container.resetIPoPPreferences()
        }
        #else
        let audioServicesFactory: (() -> AudioServicesContainer)? = nil
        let creditsFactory: (() -> CreditsViewModel)? = nil
        let balanceFetcher: () async -> Result<Int, Error> = {
            .failure(AuthError.unknown)
        }
        let clearAppStoreLocal: () async -> Result<Void, Error> = {
            .failure(AuthError.unknown)
        }
        let loadVoiceoverPreferences: () async -> VoiceoverPreferences = {
            VoiceoverPreferences(
                autoEnabled: false,
                voiceModelId: "",
                ttsModel: "s1"
            )
        }
        let saveVoiceoverPreferences: (VoiceoverPreferences) async -> Void = { _ in }
        let fetchVoiceOptions: () async -> [VoiceModelOption] = { [] }
        let fetchVoiceSampleURL: (String) async -> URL? = { _ in nil }
        let loadIPoPPreferences: () async -> IPoPPreferences? = { nil }
        let saveIPoPPreferences: (IPoPPreferences) async -> Void = { _ in }
        let resetIPoPPreferences: () async -> Void = { }
        #endif

        let nearbyInspectorFactory: (() -> AnyView)? = {
            AnyView(
                NearbyCacheInspectorView(
                    loadSnapshots: { await container.listNearbyCache() },
                    loadCurrent: { await container.currentLocationForCache() },
                    clearSnapshots: { await container.clearNearbyCache() }
                )
            )
        }

        return RootContentView(
            feedUseCase: container.discoveryFeedUseCase,
            deletionUseCase: container.discoveryDeletionUseCase,
            authUseCase: container.authUseCase,
            onboardingUseCase: container.onboardingUseCase,
            flowResolver: container.flowResolver,
            makeCreationViewModel: makeViewModel,
            makeAudioServicesContainer: audioServicesFactory,
            makeCreditsViewModel: creditsFactory,
            fetchCreditBalance: balanceFetcher,
            clearAppStoreLocal: clearAppStoreLocal,
            makeNearbyCacheInspector: nearbyInspectorFactory,
            startLocationTracking: {
                await container.startAppLocationTracking()
            },
            stopLocationTracking: {
                container.stopAppLocationTracking()
            },
            loadVoiceoverPreferences: loadVoiceoverPreferences,
            saveVoiceoverPreferences: saveVoiceoverPreferences,
            fetchVoiceOptions: fetchVoiceOptions,
            fetchVoiceSampleURL: fetchVoiceSampleURL,
            loadIPoPPreferences: loadIPoPPreferences,
            saveIPoPPreferences: saveIPoPPreferences,
            resetIPoPPreferences: resetIPoPPreferences
        )
        .task {
            // Listen for StoreKit transaction updates to avoid missing successful purchases.
            await container.startStoreKitTransactionListener()
            #if os(iOS)
            // Seed permission cache on launch
            LocationPermissionCache.shared.refreshFromSystem()
            #endif
        }
        #if os(iOS)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Refresh permission snapshot when app becomes active
                LocationPermissionCache.shared.refreshFromSystem()
            }
        }
        #endif
    }
}
