import Foundation
import XCTest
@testable import WhatsThatDomain
@testable import WhatsThatPresentation

final class AppRootViewModelTests: XCTestCase {
    func testInitialStateIsPreOnboarding() async {
        let viewModel = await makeViewModel()
        await waitForState(in: viewModel) { state in
            state == .preOnboarding
        }
    }

    func testCompletingPreOnboardingTransitionsToAuthentication() async {
        let viewModel = await makeViewModel()

        await waitForState(in: viewModel) { $0 == .preOnboarding }
        await viewModel.completePreOnboarding()
        await waitForState(in: viewModel) { $0 == .authentication }
    }

    func testSigningUpAdvancesToPostOnboarding() async throws {
        let viewModel = await makeViewModel()

        await waitForState(in: viewModel) { $0 == .preOnboarding }
        await viewModel.completePreOnboarding()
        await waitForState(in: viewModel) { $0 == .authentication }

        try await viewModel.signUp(email: "person@example.com", password: "password123")

        await waitForState(in: viewModel) { state in
            if case let .postOnboarding(user) = state {
                XCTAssertEqual(user.email, "person@example.com")
                return true
            }
            return false
        }
    }

    func testSignInWithAppleAdvancesToPostOnboarding() async throws {
        let viewModel = await makeViewModel()

        await waitForState(in: viewModel) { $0 == .preOnboarding }
        await viewModel.completePreOnboarding()
        await waitForState(in: viewModel) { $0 == .authentication }

        try await viewModel.signInWithApple()

        await waitForState(in: viewModel) { state in
            if case let .postOnboarding(user) = state {
                XCTAssertEqual(user.email, "apple-user@example.com")
                return true
            }
            return false
        }
    }

    // MARK: - Helpers

    @MainActor
    private func makeViewModel() -> AppRootViewModel {
        let authService = TestAuthService()
        let authUseCase = AuthUseCase(service: authService)
        let onboardingRepository = TestOnboardingRepository()
        let onboardingUseCase = OnboardingUseCase(repository: onboardingRepository)
        return AppRootViewModel(
            authUseCase: authUseCase,
            onboardingUseCase: onboardingUseCase,
            flowResolver: AppFlowResolver()
        )
    }

    private func waitForState(
        in viewModel: AppRootViewModel,
        timeout: TimeInterval = 1,
        predicate: @escaping (AppFlowState) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let current = await MainActor.run { viewModel.flowState }
            if predicate(current) {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Timed out waiting for expected state change", file: file, line: line)
    }
}

private actor TestAuthService: AuthService {
    private struct StoredCredential {
        var password: String
        var id: UUID
    }

    private var storedCredentials: [String: StoredCredential] = [:]
    private var currentUser: AuthenticatedUser?
    private var continuations: [UUID: AsyncStream<AuthSession>.Continuation] = [:]

    func currentSession() async throws -> AuthSession {
        currentSessionValue
    }

    func sessionUpdates() async -> AsyncStream<AuthSession> {
        AsyncStream { continuation in
            let token = UUID()
            Task { [weak self] in
                await self?.registerContinuation(id: token, continuation: continuation)
            }
        }
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let credentials = storedCredentials[normalizedEmail],
              credentials.password == password
        else {
            throw AuthError.invalidCredentials
        }

        let user = AuthenticatedUser(id: credentials.id, email: normalizedEmail)
        currentUser = user
        let session = AuthSession.authenticated(user)
        notify(session: session)
        return session
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if storedCredentials[normalizedEmail] != nil {
            throw AuthError.emailAlreadyInUse
        }

        let userId = UUID()
        storedCredentials[normalizedEmail] = StoredCredential(password: password, id: userId)
        let user = AuthenticatedUser(id: userId, email: normalizedEmail)
        currentUser = user
        let session = AuthSession.authenticated(user)
        notify(session: session)
        return session
    }

    func signInWithGoogle() async throws -> AuthSession {
        let user = AuthenticatedUser(id: UUID(), email: "google-user@example.com")
        currentUser = user
        let session = AuthSession.authenticated(user)
        notify(session: session)
        return session
    }

    func signInWithApple() async throws -> AuthSession {
        let user = AuthenticatedUser(id: UUID(), email: "apple-user@example.com")
        currentUser = user
        let session = AuthSession.authenticated(user)
        notify(session: session)
        return session
    }

    func signOut() async throws {
        guard currentUser != nil else { return }
        currentUser = nil
        notify(session: .signedOut)
    }

    func sendPasswordReset(email _: String) async throws {}

    func bootstrapPasswordResetSession(from _: URL) async throws -> AuthenticatedUser {
        throw AuthError.passwordResetLinkInvalid
    }

    func updatePassword(to _: String) async throws {}

    private func registerContinuation(
        id: UUID,
        continuation: AsyncStream<AuthSession>.Continuation
    ) async {
        continuations[id] = continuation
        continuation.yield(currentSessionValue)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id: id) }
        }
    }

    private func removeContinuation(id: UUID) async {
        continuations[id] = nil
    }

    private func notify(session: AuthSession) {
        for continuation in continuations.values {
            continuation.yield(session)
        }
    }

    private var currentSessionValue: AuthSession {
        if let user = currentUser {
            return .authenticated(user)
        } else {
            return .signedOut
        }
    }
}

private actor TestOnboardingRepository: OnboardingRepository {
    private var flags = OnboardingFlags()

    func loadFlags() async -> OnboardingFlags {
        flags
    }

    func markPreOnboardingComplete() async {
        flags.hasCompletedPreOnboarding = true
    }

    func markPostOnboardingComplete() async {
        flags.hasCompletedPostOnboarding = true
    }

    func reset() async {
        flags = OnboardingFlags()
    }
}
