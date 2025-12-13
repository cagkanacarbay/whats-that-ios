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
    public let discoveryDeletionUseCase: DiscoveryDeletionUseCase
    public let authUseCase: AuthUseCase
    public let onboardingUseCase: OnboardingUseCase
    public let flowResolver: AppFlowResolver
#if os(iOS)
    private let discoveryCreationProvider: DiscoveryCreationDependencyProvider
    private let discoveryRepository: DiscoveryRepository
    private let voiceoverRepository: any DiscoveryVoiceoverRepository
    private let voiceInventoryRepository: VoiceInventoryRepository
    private let voiceoverPreferencesStore: VoiceoverPreferencesStore
    private let ipopPreferencesStore: IPoPPreferencesStore
    private let creditsRepository: DiscoveryCreditsRepository
    private let creditsStore: any CreditsStore
    private let creditBalanceStore: CreditBalanceStore
    private let locationService: DiscoveryLocationService
#endif

#if os(iOS)
    init(
        configuration: AppConfiguration,
        discoveryRepository: DiscoveryRepository,
        authService: AuthService,
        onboardingRepository: OnboardingRepository,
        discoveryCreationProvider: DiscoveryCreationDependencyProvider,
        voiceoverRepository: any DiscoveryVoiceoverRepository,
        voiceInventoryRepository: VoiceInventoryRepository,
        voiceoverPreferencesStore: VoiceoverPreferencesStore,
        ipopPreferencesStore: IPoPPreferencesStore,
        creditsRepository: DiscoveryCreditsRepository,
        creditsStore: any CreditsStore,
        creditBalanceStore: CreditBalanceStore,
        locationService: DiscoveryLocationService
    ) {
        self.configuration = configuration
        self.discoveryFeedUseCase = DiscoveryFeedUseCase(repository: discoveryRepository)
        self.discoveryDeletionUseCase = DiscoveryDeletionUseCase(repository: discoveryRepository)
        self.authUseCase = AuthUseCase(service: authService)
        self.onboardingUseCase = OnboardingUseCase(repository: onboardingRepository)
        self.flowResolver = AppFlowResolver()
        self.discoveryCreationProvider = discoveryCreationProvider
        self.discoveryRepository = discoveryRepository
        self.voiceoverRepository = voiceoverRepository
        self.voiceInventoryRepository = voiceInventoryRepository
        self.voiceoverPreferencesStore = voiceoverPreferencesStore
        self.ipopPreferencesStore = ipopPreferencesStore
        self.creditsRepository = creditsRepository
        self.creditsStore = creditsStore
        self.creditBalanceStore = creditBalanceStore
        self.locationService = locationService
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
        self.discoveryDeletionUseCase = DiscoveryDeletionUseCase(repository: discoveryRepository)
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
        let authService: SupabaseAuthService
        #if USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit) && USE_REMOTE_DEPS && canImport(AuthenticationServices) && canImport(UIKit)
        let googleService = try configuration.googleClientID.map { clientID in
            try GoogleSignInService(clientID: clientID)
        }
        let appleService = SignInWithAppleService()
        authService = SupabaseAuthService(
            client: client,
            configuration: configuration,
            googleSignInService: googleService,
            appleSignInService: appleService
        )
        #elseif USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit)
        let googleService = try configuration.googleClientID.map { clientID in
            try GoogleSignInService(clientID: clientID)
        }
        authService = SupabaseAuthService(
            client: client,
            configuration: configuration,
            googleSignInService: googleService
        )
        #elseif USE_REMOTE_DEPS && canImport(AuthenticationServices) && canImport(UIKit)
        let appleService = SignInWithAppleService()
        authService = SupabaseAuthService(
            client: client,
            configuration: configuration,
            appleSignInService: appleService
        )
        #else
        authService = SupabaseAuthService(
            client: client,
            configuration: configuration
        )
        #endif
        let onboardingRepository = UserDefaultsOnboardingRepository()

        #if os(iOS)
        let captureService = CameraCaptureService()
        let selectionService = PhotoLibrarySelectionService()
        let creditsRepository = SupabaseCreditsRepository(client: client)
        let creditPackIdentifiers = CreditPackCatalog.standardPacks.map(\.id)
        let creditsStore = StoreKitCreditsStore(
            productIdentifiers: creditPackIdentifiers,
            configuration: configuration,
            client: client,
            urlSession: session
        )
        let creditBalanceStore = CreditBalanceStore(repository: creditsRepository)
        let analysisClient = SupabaseDiscoveryAnalysisClient(
            client: client,
            configuration: configuration,
            urlSession: session
        )
        let imageEncoder = DefaultDiscoveryImageEncoder()
        let pushService = NativePushService()
        let nearbyPlacesFetcher = SupabaseNearbyPlacesFetcher(
            client: client,
            configuration: configuration,
            urlSession: session
        )
        let locationService = CoreLocationDiscoveryLocationService(
            configuration: .default,
            nearbyPlacesFetcher: nearbyPlacesFetcher
        )

        let voiceoverRepository = SupabaseVoiceoverRepository(
            client: client,
            configuration: configuration,
            urlSession: session
        )
        let voiceInventoryRepository = VoiceInventoryRepository(client: client)
        let voiceoverPreferencesStore = VoiceoverPreferencesStore()
        let ipopPreferencesStore = IPoPPreferencesStore()
        let discoveryCreationProvider = DiscoveryCreationDependencyProvider(
            maxImageDimension: 2048,
            recentHistoryLimit: 25,
            captureService: captureService,
            selectionService: selectionService,
            historyRepository: discoveryRepository,
            creditsRepository: creditsRepository,
            creditBalanceStore: creditBalanceStore,
            analysisClient: analysisClient,
            imageEncoder: imageEncoder,
            pushService: pushService,
            locationService: locationService,
            voiceoverRepository: voiceoverRepository,
            voiceoverPreferencesStore: voiceoverPreferencesStore,
            ipopPreferencesStore: ipopPreferencesStore
        )
        #endif

        #if os(iOS)
        return AppDependencyContainer(
            configuration: configuration,
            discoveryRepository: discoveryRepository,
            authService: authService,
            onboardingRepository: onboardingRepository,
            discoveryCreationProvider: discoveryCreationProvider,
            voiceoverRepository: voiceoverRepository,
            voiceInventoryRepository: voiceInventoryRepository,
            voiceoverPreferencesStore: voiceoverPreferencesStore,
            ipopPreferencesStore: ipopPreferencesStore,
            creditsRepository: creditsRepository,
            creditsStore: creditsStore,
            creditBalanceStore: creditBalanceStore,
            locationService: locationService
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
    /// Begin listening for StoreKit transaction updates at app launch.
    /// Ensures pending purchases are validated and credit balance refreshed.
    func startStoreKitTransactionListener() async {
        if let store = creditsStore as? StoreKitCreditsStore {
            _ = await store.startListeningForTransactionUpdates(balanceStore: creditBalanceStore)
        }
    }
    @MainActor
    func makeDiscoveryCreationViewModel(
        for type: DiscoveryCreationFlowType
    ) -> DiscoveryCreationFlowViewModel {
        discoveryCreationProvider.makeViewModel(for: type)
    }

    @MainActor
    func makeVoiceoverPlaybackController() -> VoiceoverPlaybackController {
        let controller = VoiceoverPlaybackController(
            repository: voiceoverRepository,
            preferencesStore: voiceoverPreferencesStore
        )
        Task {
            let preferences = await voiceoverPreferencesStore.load()
            await MainActor.run {
                controller.updatePreferences(preferences)
            }
        }
        return controller
    }
    
    @MainActor
    func makeAudioServicesContainer() -> AudioServicesContainer {
        AudioServicesContainer(
            repository: discoveryRepository,
            voiceoverRepository: voiceoverRepository,
            creditBalanceStore: creditBalanceStore
        )
    }

    func loadVoiceoverPreferences() async -> VoiceoverPreferences {
        await voiceoverPreferencesStore.load()
    }

    func saveVoiceoverPreferences(_ preferences: VoiceoverPreferences) async {
        await voiceoverPreferencesStore.save(preferences)
    }

    func loadIPoPPreferences() async -> IPoPPreferences? {
        await ipopPreferencesStore.load()
    }

    func saveIPoPPreferences(_ preferences: IPoPPreferences) async {
        await ipopPreferencesStore.save(preferences)
    }

    func resetIPoPPreferences() async {
        await ipopPreferencesStore.reset()
    }

    func fetchVoiceOptions() async -> [VoiceModelOption] {
        await voiceInventoryRepository.fetchVoiceOptions()
    }

    func fetchVoiceSampleURL(voiceName: String) async -> URL? {
        await voiceInventoryRepository.fetchVoiceSampleURL(voiceName: voiceName)
    }

    @MainActor
    func makeCreditsViewModel() -> CreditsViewModel {
        CreditsViewModel(
            creditsRepository: creditsRepository,
            store: creditsStore,
            balanceStore: creditBalanceStore
        )
    }

    func fetchCreditBalance() async -> Result<Int, Error> {
        do {
            let balance = try await creditBalanceStore.refreshIfStale()
            return .success(balance)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - App-wide Location Lifecycle
    @MainActor
    func startAppLocationTracking() async {
        // print("[App][LocationLifecycle] startAppLocationTracking() -> startTrackingIfNeeded + one-shot fresh")
        await locationService.startTrackingIfNeeded()
        _ = await locationService.currentLocation(requireFresh: true)
    }

    func stopAppLocationTracking() {
        // print("[App][LocationLifecycle] stopAppLocationTracking() -> stopTracking")
        locationService.stopTracking()
    }

    // MARK: - Dev/QA: Nearby Cache Inspection
    func listNearbyCache() async -> [NearbyPlacesSnapshot] {
        await locationService.listNearbyCache()
    }

    func currentLocationForCache() async -> DiscoveryLocation? {
        await locationService.currentLocation()
    }

    func clearNearbyCache() async {
        await locationService.clearNearbyCache()
    }

    /// Clears local App Store state used by this app for testing purposes.
    /// - Removes the on-disk App Store receipt (if present)
    /// - Clears cached StoreKit products
    /// - Clears cached credit balance
    func clearAppStoreLocalState() async -> Result<Void, Error> {
        if let store = creditsStore as? StoreKitCreditsStore {
            await store.clearLocalStoreState(deleteReceipt: true)
        }
        _ = await creditBalanceStore.set(nil)
        return .success(())
    }
}
#endif
