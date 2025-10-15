import Foundation
import WhatsThatData
import WhatsThatDomain
import WhatsThatInfrastructure
import WhatsThatShared
#if os(iOS)
import WhatsThatPresentation
#endif
#if USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit)
import GoogleSignIn
import UIKit
#endif

public struct AppDependencyContainer: Sendable {
    public let configuration: AppConfiguration
    public let discoveryFeedUseCase: DiscoveryFeedUseCase
    public let authUseCase: AuthUseCase
    public let onboardingUseCase: OnboardingUseCase
    public let flowResolver: AppFlowResolver
#if os(iOS)
    private let discoveryCreationProvider: DiscoveryCreationDependencyProvider
    private let voiceoverRepository: any DiscoveryVoiceoverRepository
#endif

#if os(iOS)
    init(
        configuration: AppConfiguration,
        discoveryRepository: DiscoveryRepository,
        authService: AuthService,
        onboardingRepository: OnboardingRepository,
        discoveryCreationProvider: DiscoveryCreationDependencyProvider,
        voiceoverRepository: any DiscoveryVoiceoverRepository
    ) {
        self.configuration = configuration
        self.discoveryFeedUseCase = DiscoveryFeedUseCase(repository: discoveryRepository)
        self.authUseCase = AuthUseCase(service: authService)
        self.onboardingUseCase = OnboardingUseCase(repository: onboardingRepository)
        self.flowResolver = AppFlowResolver()
        self.discoveryCreationProvider = discoveryCreationProvider
        self.voiceoverRepository = voiceoverRepository
    }
#else
    init(
        configuration: AppConfiguration,
        discoveryRepository: DiscoveryRepository,
        authService: AuthService,
        onboardingRepository: OnboardingRepository
    ) {
        self.configuration = configuration
        self.discoveryFeedUseCase = DiscoveryFeedUseCase(repository: discoveryRepository)
        self.authUseCase = AuthUseCase(service: authService)
        self.onboardingUseCase = OnboardingUseCase(repository: onboardingRepository)
        self.flowResolver = AppFlowResolver()
    }
#endif
}

public extension AppDependencyContainer {
    @MainActor
    static func bootstrap(
        configuration: AppConfiguration,
        session: URLSession = .shared
    ) -> AppDependencyContainer {
        #if USE_REMOTE_DEPS && canImport(Supabase)
        do {
            return try AppDependencyContainer.live(
                configuration: configuration,
                session: session
            )
        } catch {
            preconditionFailure("Failed to bootstrap live dependencies: \(error)")
        }
        #else
        preconditionFailure("Supabase dependencies are unavailable. Build with USE_REMOTE_DEPS=1 and resolve packages.")
        #endif
    }

    #if USE_REMOTE_DEPS && canImport(Supabase)
    @MainActor
    static func live(
        configuration: AppConfiguration,
        session: URLSession = .shared
    ) throws -> AppDependencyContainer {
        let client = try SupabaseClientFactory.makeClient(
            configuration: configuration,
            session: session
        )

        let discoveryRepository = SupabaseDiscoveryRepository(client: client)
        #if USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit)
        let googleService = try configuration.googleClientID.map { clientID in
            try GoogleSignInService(clientID: clientID)
        }
        let authService = try SupabaseAuthService(
            client: client,
            googleSignInService: googleService
        )
        #else
        let authService = try SupabaseAuthService(
            client: client
        )
        #endif
        let onboardingRepository = UserDefaultsOnboardingRepository()

        #if os(iOS)
        let captureService = CameraCaptureService()
        let selectionService = PhotoLibrarySelectionService()
        let creditsRepository = SupabaseCreditsRepository(client: client)
        let analysisClient = SupabaseDiscoveryAnalysisClient(
            client: client,
            configuration: configuration,
            urlSession: session
        )
        let imageEncoder = DefaultDiscoveryImageEncoder()
        let pushService = NativePushService()
        let locationService = CoreLocationDiscoveryLocationService()

        let discoveryCreationProvider = DiscoveryCreationDependencyProvider(
            maxImageDimension: 2048,
            recentHistoryLimit: 25,
            captureService: captureService,
            selectionService: selectionService,
            historyRepository: discoveryRepository,
            creditsRepository: creditsRepository,
            analysisClient: analysisClient,
            imageEncoder: imageEncoder,
            pushService: pushService,
            locationService: locationService
        )
        let voiceoverRepository = SupabaseVoiceoverRepository(client: client)
        #endif

        #if os(iOS)
        return AppDependencyContainer(
            configuration: configuration,
            discoveryRepository: discoveryRepository,
            authService: authService,
            onboardingRepository: onboardingRepository,
            discoveryCreationProvider: discoveryCreationProvider,
            voiceoverRepository: voiceoverRepository
        )
#else
        return AppDependencyContainer(
            configuration: configuration,
            discoveryRepository: discoveryRepository,
            authService: authService,
            onboardingRepository: onboardingRepository
        )
        #endif
    }
    #endif
}

#if os(iOS)
public extension AppDependencyContainer {
    @MainActor
    func makeDiscoveryCreationViewModel(
        for type: DiscoveryCreationFlowType
    ) -> DiscoveryCreationFlowViewModel {
        discoveryCreationProvider.makeViewModel(for: type)
    }

    @MainActor
    func makeVoiceoverPlaybackController() -> VoiceoverPlaybackController {
        VoiceoverPlaybackController(repository: voiceoverRepository)
    }
}
#endif
