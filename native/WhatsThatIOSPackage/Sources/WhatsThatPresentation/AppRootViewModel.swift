import Foundation
import WhatsThatDomain
import WhatsThatShared

@MainActor
public final class AppRootViewModel: ObservableObject {
    @Published public private(set) var flowState: AppFlowState = .loading
    @Published public private(set) var isPerformingAuthAction = false

    private let authUseCase: AuthUseCase
    private let onboardingUseCase: OnboardingUseCase
    private let flowResolver: AppFlowResolver

    private var currentFlags = OnboardingFlags()
    private var latestSession: AuthSession = .signedOut
    private var observationTask: Task<Void, Never>?

    public init(
        authUseCase: AuthUseCase,
        onboardingUseCase: OnboardingUseCase,
        flowResolver: AppFlowResolver
    ) {
        self.authUseCase = authUseCase
        self.onboardingUseCase = onboardingUseCase
        self.flowResolver = flowResolver

        Task(priority: .utility) {
            await DiscoveryAssetCache.shared.purgeExpiredEntries()
        }

        Task {
            await bootstrap()
        }
    }

    deinit {
        observationTask?.cancel()
    }

    public func reload() async {
        await bootstrap()
    }

    public func completePreOnboarding() async {
        await onboardingUseCase.markPreOnboardingComplete()
        currentFlags.hasCompletedPreOnboarding = true
        updateFlow(session: latestSession)
    }

    public func completePostOnboarding() async {
        await onboardingUseCase.markPostOnboardingComplete()
        currentFlags.hasCompletedPostOnboarding = true
        updateFlow(session: latestSession)
    }

    public func signIn(email: String, password: String) async throws {
        guard !isPerformingAuthAction else { return }

        isPerformingAuthAction = true
        defer { isPerformingAuthAction = false }

        do {
            let session = try await authUseCase.signIn(email: email, password: password)
            updateFlow(session: session)
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown
        }
    }

    public func signUp(email: String, password: String) async throws {
        guard !isPerformingAuthAction else { return }

        isPerformingAuthAction = true
        defer { isPerformingAuthAction = false }

        do {
            let session = try await authUseCase.signUp(email: email, password: password)
            updateFlow(session: session)
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown
        }
    }

    public func signInWithGoogle() async throws {
        guard !isPerformingAuthAction else { return }

        isPerformingAuthAction = true
        defer { isPerformingAuthAction = false }

        do {
            let session = try await authUseCase.signInWithGoogle()
            updateFlow(session: session)
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown
        }
    }

    public func signInWithApple() async throws {
        guard !isPerformingAuthAction else { return }

        isPerformingAuthAction = true
        defer { isPerformingAuthAction = false }

        do {
            let session = try await authUseCase.signInWithApple()
            updateFlow(session: session)
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown
        }
    }

    public func signOut() async throws {
        try await authUseCase.signOut()
        await DiscoveryAssetCache.shared.clearAll()
        updateFlow(session: .signedOut)
    }

    public func resetOnboarding() async {
        await onboardingUseCase.reset()
        currentFlags = OnboardingFlags()
        updateFlow(session: latestSession)
    }

    public func requestPasswordReset(email: String) async throws {
        do {
            try await authUseCase.sendPasswordReset(email: email)
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.passwordResetFailed
        }
    }

    // MARK: - Private

    private func bootstrap() async {
        flowState = .loading
        currentFlags = await onboardingUseCase.flags()

        let session: AuthSession
        do {
            session = try await authUseCase.currentSession()
        } catch {
            session = .signedOut
        }

        updateFlow(session: session)
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.authUseCase.observeSession()
            for await sessionUpdate in stream {
                await MainActor.run {
                    self.handleSessionUpdate(sessionUpdate)
                }
            }
        }
    }

    private func handleSessionUpdate(_ session: AuthSession) {
        updateFlow(session: session)
    }

    private func updateFlow(session: AuthSession) {
        latestSession = session
        flowState = flowResolver.resolve(session: session, flags: currentFlags)
    }
}
