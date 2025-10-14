import Foundation
import WhatsThatData
import WhatsThatDomain
import WhatsThatInfrastructure
import WhatsThatShared
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

    public init(
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
}

public extension AppDependencyContainer {
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
    static func live(
        configuration: AppConfiguration,
        session: URLSession = .shared
    ) throws -> AppDependencyContainer {
        let discoveryRepository = try SupabaseDiscoveryRepository(
            configuration: configuration,
            session: session
        )
        #if USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit)
        let googleService = try configuration.googleClientID.map { clientID in
            try GoogleSignInService(clientID: clientID)
        }
        let authService = try SupabaseAuthService(
            configuration: configuration,
            session: session,
            googleSignInService: googleService
        )
        #else
        let authService = try SupabaseAuthService(
            configuration: configuration,
            session: session
        )
        #endif
        let onboardingRepository = UserDefaultsOnboardingRepository()

        return AppDependencyContainer(
            configuration: configuration,
            discoveryRepository: discoveryRepository,
            authService: authService,
            onboardingRepository: onboardingRepository
        )
    }
    #endif
}
