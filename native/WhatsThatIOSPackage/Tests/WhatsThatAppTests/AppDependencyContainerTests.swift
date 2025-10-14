import XCTest
@testable import WhatsThatApp
@testable import WhatsThatDomain
import WhatsThatData
import WhatsThatInfrastructure

final class AppDependencyContainerTests: XCTestCase {
    func testPreviewContainerProvidesUseCases() async throws {
        let container = AppDependencyContainer(
            configuration: .preview,
            discoveryRepository: StubDiscoveryRepository(transport: StubSupabaseTransport()),
            authService: TestAuthService(),
            onboardingRepository: TestOnboardingRepository()
        )
        XCTAssertNotNil(container.discoveryFeedUseCase)

        let session = try await container.authUseCase.currentSession()
        XCTAssertEqual(session, .signedOut)

        let flags = await container.onboardingUseCase.flags()
        XCTAssertFalse(flags.hasCompletedPreOnboarding)

        let resolved = container.flowResolver.resolve(session: session, flags: flags)
        XCTAssertEqual(resolved, .preOnboarding)
    }
}

private actor TestAuthService: AuthService {
    func currentSession() async throws -> AuthSession { .signedOut }

    func sessionUpdates() async -> AsyncStream<AuthSession> {
        AsyncStream { continuation in
            continuation.yield(.signedOut)
            continuation.finish()
        }
    }

    func signIn(email _: String, password _: String) async throws -> AuthSession {
        throw AuthError.unknown
    }

    func signUp(email _: String, password _: String) async throws -> AuthSession {
        throw AuthError.unknown
    }

    func signInWithGoogle() async throws -> AuthSession {
        throw AuthError.unknown
    }

    func signOut() async throws {}

    func sendPasswordReset(email _: String) async throws {}
}

private actor TestOnboardingRepository: OnboardingRepository {
    private var flags = OnboardingFlags()

    func loadFlags() async -> OnboardingFlags { flags }
    func markPreOnboardingComplete() async { flags.hasCompletedPreOnboarding = true }
    func markPostOnboardingComplete() async { flags.hasCompletedPostOnboarding = true }
    func reset() async { flags = OnboardingFlags() }
}
