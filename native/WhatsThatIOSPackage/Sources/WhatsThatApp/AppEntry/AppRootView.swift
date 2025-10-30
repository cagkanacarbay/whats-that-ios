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
        let voiceoverFactory: (() -> VoiceoverPlaybackController)? = {
            container.makeVoiceoverPlaybackController()
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
        #else
        let voiceoverFactory: (() -> VoiceoverPlaybackController)? = nil
        let creditsFactory: (() -> CreditsViewModel)? = nil
        let balanceFetcher: () async -> Result<Int, Error> = {
            .failure(AuthError.unknown)
        }
        let clearAppStoreLocal: () async -> Result<Void, Error> = {
            .failure(AuthError.unknown)
        }
        #endif

        return RootContentView(
            feedUseCase: container.discoveryFeedUseCase,
            deletionUseCase: container.discoveryDeletionUseCase,
            authUseCase: container.authUseCase,
            onboardingUseCase: container.onboardingUseCase,
            flowResolver: container.flowResolver,
            makeCreationViewModel: makeViewModel,
            makeVoiceoverController: voiceoverFactory,
            makeCreditsViewModel: creditsFactory,
            fetchCreditBalance: balanceFetcher,
            clearAppStoreLocal: clearAppStoreLocal
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
