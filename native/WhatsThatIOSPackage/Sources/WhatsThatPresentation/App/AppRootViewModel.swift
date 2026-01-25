import Foundation
import WhatsThatDomain
import WhatsThatShared

@MainActor
public final class AppRootViewModel: ObservableObject {
    @Published public private(set) var flowState: AppFlowState = .loading
    @Published public private(set) var isPerformingAuthAction = false
    @Published public private(set) var passwordResetUser: AuthenticatedUser?

    // Compliance state
    @Published public private(set) var complianceBlockingState: ComplianceBlockingState?
    @Published public private(set) var complianceNonBlockingState: ComplianceNonBlockingState?
    @Published public private(set) var pendingLegalAcceptance: Bool = false

    private let authUseCase: AuthUseCase
    private let onboardingUseCase: OnboardingUseCase
    private let flowResolver: AppFlowResolver
    private let clearAllUserData: () async -> Void
    private let voiceoverPreferencesStore: VoiceoverPreferencesStore
    private let complianceUseCase: ComplianceUseCase
    private let userAppVersion: String
    private let resolveIntroState: () async -> Void

    private var currentFlags = OnboardingFlags()
    private var latestSession: AuthSession = .signedOut
    private var observationTask: Task<Void, Never>?

    public init(
        authUseCase: AuthUseCase,
        onboardingUseCase: OnboardingUseCase,
        flowResolver: AppFlowResolver,
        clearAllUserData: @escaping () async -> Void,
        voiceoverPreferencesStore: VoiceoverPreferencesStore,
        complianceUseCase: ComplianceUseCase,
        userAppVersion: String = Bundle.main.appVersion,
        resolveIntroState: @escaping () async -> Void = {}
    ) {
        self.authUseCase = authUseCase
        self.onboardingUseCase = onboardingUseCase
        self.flowResolver = flowResolver
        self.clearAllUserData = clearAllUserData
        self.voiceoverPreferencesStore = voiceoverPreferencesStore
        self.complianceUseCase = complianceUseCase
        self.userAppVersion = userAppVersion
        self.resolveIntroState = resolveIntroState

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

    public enum SignInOutcome {
        case session(AuthSession)
        case verificationRequired(email: String)
    }

    public func signIn(email: String, password: String) async throws -> SignInOutcome {
        guard !isPerformingAuthAction else { return .session(latestSession) }

        isPerformingAuthAction = true
        defer { isPerformingAuthAction = false }

        do {
            let result = try await authUseCase.signIn(email: email, password: password)
            switch result {
            case .authenticated(let session):
                updateFlow(session: session)
                return .session(session)
            case .verificationRequired:
                return .verificationRequired(email: email)
            }
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown
        }
    }

    public enum SignUpOutcome {
        case session(AuthSession)
        case verificationRequired
    }

    public func signUp(email: String, password: String) async throws -> SignUpOutcome {
        guard !isPerformingAuthAction else {
             // Return early or throw? Generally we guard in UI, but safe to throw invalid state or just return
             // If we return, we need a valid outcome. Let's stick to existing guard logic but throws is cleaner for rate limiting etc.
             // Actually existing logic just returns if performing.
             // But the signature expects a return.
             // Let's assume the UI prevents this, but for safety throw rate limit or ignored.
             return .session(latestSession) 
        }

        isPerformingAuthAction = true
        defer { isPerformingAuthAction = false }

        do {
            let result = try await authUseCase.signUp(email: email, password: password)
            switch result {
            case .authenticated(let session):
                updateFlow(session: session)
                return .session(session)
            case .verificationRequired:
                return .verificationRequired
            }
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
        await clearAllUserData()
        passwordResetUser = nil
        updateFlow(session: .signedOut)
    }

    public func resetOnboarding() async {
        await onboardingUseCase.reset()
        currentFlags = OnboardingFlags()
        updateFlow(session: latestSession)
    }

    public func deleteAccount() async throws {
        do {
            try await authUseCase.deleteAccount()
            await clearAllUserData()
            passwordResetUser = nil
            updateFlow(session: .signedOut)
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.accountDeletionFailed
        }
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

    public func preparePasswordReset(from url: URL) async -> AuthError? {
        do {
            let user = try await authUseCase.bootstrapPasswordResetSession(from: url)
            passwordResetUser = user
            latestSession = .authenticated(user)
            updateFlow(session: latestSession)
            return nil
        } catch let error as AuthError {
            return error
        } catch {
            return .passwordResetLinkInvalid
        }
    }

    public func completePasswordReset(newPassword: String) async -> AuthError? {
        do {
            try await authUseCase.updatePassword(to: newPassword)
        } catch let error as AuthError {
            return error
        } catch {
            return .passwordUpdateFailed
        }
        return nil
    }

    public func cancelPasswordResetFlow() async {
        try? await signOut()
    }

    public func verifyEmail(from url: URL) async -> AuthError? {
        do {
            try await authUseCase.verifyEmailFromLink(url: url)
            return nil
        } catch let error as AuthError {
            return error
        } catch {
            return .unknown
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
        
        // For signed-in users, we need to bind stores BEFORE resolving flow state
        // because flow resolution depends on user-specific flags
        if let user = session.user {
            Task {
                let userId = user.id.uuidString
                
                // 1. Bind all user-keyed stores first
                await onboardingUseCase.bind(to: userId)
                await voiceoverPreferencesStore.bind(to: userId)
                
                // 2. Bind the free credits alert tracker
                await FreeCreditsAlertTracker.shared.bind(to: userId)

                // 3. Resolve intro state for returning users (reinstall/new device)
                await self.resolveIntroState()

                // 4. Now load flags with correct user binding
                let flags = await onboardingUseCase.flags()

                // 5. Resolve flow state with correct user flags
                await MainActor.run {
                    self.currentFlags = flags
                    self.flowState = self.flowResolver.resolve(session: session, flags: flags)
                }

                // 6. Check compliance after user is authenticated
                await self.checkCompliance()
            }
        } else {
            // Not signed in - resolve immediately with current flags
            flowState = flowResolver.resolve(session: session, flags: currentFlags)

            // Clear compliance state when signed out
            complianceBlockingState = nil
            complianceNonBlockingState = nil
            pendingLegalAcceptance = false
        }
    }

    // MARK: - Compliance

    /// Checks compliance status (maintenance, version updates, legal acceptance)
    public func checkCompliance() async {
        do {
            let config = try await complianceUseCase.fetchConfig(forceFresh: true)
            await updateComplianceState(config: config)
        } catch {
            // Check for cached maintenance state on failure
            if let maintenanceState = await complianceUseCase.getMaintenanceStateForOffline() {
                await MainActor.run {
                    self.complianceBlockingState = .maintenance(message: maintenanceState.message)
                }
            }
            // If no cached maintenance state, proceed normally (fail-open)
        }
    }

    /// Refreshes compliance if the cached config is stale
    public func refreshComplianceIfStale() async {
        guard await complianceUseCase.isConfigStale() else { return }
        await checkCompliance()
    }

    /// Accepts terms and/or privacy policy
    /// - Parameters:
    ///   - tosVersion: The ToS version to accept (nil if not accepting)
    ///   - privacyVersion: The Privacy version to accept (nil if not accepting)
    public func acceptTerms(tosVersion: String?, privacyVersion: String?) async throws {
        print("[ViewModel] acceptTerms called - tos=\(tosVersion ?? "nil"), privacy=\(privacyVersion ?? "nil")")
        do {
            let response = try await complianceUseCase.acceptTerms(tosVersion: tosVersion, privacyVersion: privacyVersion)
            print("[ViewModel] acceptTerms success: \(response)")
        } catch {
            print("[ViewModel] acceptTerms ERROR: \(error)")
            throw error
        }

        // Refresh compliance state
        if let config = await complianceUseCase.getCachedConfig() {
            await updateComplianceState(config: config)
        }

        await MainActor.run {
            self.pendingLegalAcceptance = false
        }
    }

    /// Dismisses the soft update reminder
    public func dismissSoftUpdateReminder() async {
        await complianceUseCase.markSoftReminderShown()
        await MainActor.run {
            self.complianceNonBlockingState = nil
        }
    }

    private func updateComplianceState(config: AppConfigResponse) async {
        let blockingState = await complianceUseCase.determineBlockingState(
            config: config,
            userAppVersion: userAppVersion
        )

        let nonBlockingState: ComplianceNonBlockingState?
        if blockingState == nil {
            nonBlockingState = await complianceUseCase.determineNonBlockingState(
                config: config,
                userAppVersion: userAppVersion
            )
        } else {
            nonBlockingState = nil
        }

        await MainActor.run {
            self.complianceBlockingState = blockingState
            self.complianceNonBlockingState = nonBlockingState

            // Set pending flag for legal acceptance (used for safe-screen deferral)
            if case .legalAcceptance = blockingState {
                self.pendingLegalAcceptance = true
            } else {
                self.pendingLegalAcceptance = false
            }
        }
    }
}
