import Foundation
import WhatsThatDomain
import WhatsThatShared

@MainActor
public final class AppRootViewModel: ObservableObject {
    @Published public private(set) var flowState: AppFlowState = .loading
    @Published public private(set) var isPerformingAuthAction = false
    @Published public private(set) var isVerifyingEmail = false
    @Published public private(set) var passwordResetUser: AuthenticatedUser?

    // Compliance state
    @Published public private(set) var complianceBlockingState: ComplianceBlockingState?
    @Published public private(set) var complianceNonBlockingState: ComplianceNonBlockingState?
    @Published public private(set) var pendingLegalAcceptance: Bool = false

    /// True if user previously saw post-onboarding but hasn't created their first discovery yet.
    /// Used to show "Welcome back" instead of "Now it's your turn".
    @Published public private(set) var isReturningOnboardingUser: Bool = false

    private let authUseCase: AuthUseCase
    private let onboardingUseCase: OnboardingUseCase
    private let flowResolver: AppFlowResolver
    private let clearAllUserData: () async -> Void
    private let voiceoverPreferencesStore: VoiceoverPreferencesStore
    private let complianceUseCase: ComplianceUseCase
    private let userAppVersion: String
    private let resolveIntroState: () async -> Void
    private let refreshCreditBalance: () async -> Void

    private var currentFlags = OnboardingFlags()
    private var latestSession: AuthSession = .signedOut
    private var observationTask: Task<Void, Never>?

    /// Monotonically increasing counter to prevent stale async Tasks from overriding newer flow state.
    /// Each call to `updateFlow` increments this. The async Task captures its generation and
    /// only updates `flowState` if no newer `updateFlow` call has occurred since.
    private var flowUpdateGeneration: UInt64 = 0

    /// Tracks if user started signup but is waiting for email verification.
    /// When they verify, we'll record their terms acceptance.
    private var pendingNewSignupVerification: Bool = false

    /// Set to true when user clicks through post-onboarding this session.
    /// Prevents re-showing post-onboarding until next app launch (even if they still have 0 discoveries).
    private var hasProceededPastPostOnboardingThisSession: Bool = false

    public init(
        authUseCase: AuthUseCase,
        onboardingUseCase: OnboardingUseCase,
        flowResolver: AppFlowResolver,
        clearAllUserData: @escaping () async -> Void,
        voiceoverPreferencesStore: VoiceoverPreferencesStore,
        complianceUseCase: ComplianceUseCase,
        userAppVersion: String = Bundle.main.appVersion,
        resolveIntroState: @escaping () async -> Void = {},
        refreshCreditBalance: @escaping () async -> Void = {}
    ) {
        self.authUseCase = authUseCase
        self.onboardingUseCase = onboardingUseCase
        self.flowResolver = flowResolver
        self.clearAllUserData = clearAllUserData
        self.voiceoverPreferencesStore = voiceoverPreferencesStore
        self.complianceUseCase = complianceUseCase
        self.userAppVersion = userAppVersion
        self.resolveIntroState = resolveIntroState
        self.refreshCreditBalance = refreshCreditBalance

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
        // Mark that user has proceeded past post-onboarding this session.
        // Prevents re-showing post-onboarding until next app launch.
        hasProceededPastPostOnboardingThisSession = true
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
            print("[SignUp] Result: \(result)")
            switch result {
            case .authenticated(let session):
                print("[SignUp] Authenticated immediately - calling updateFlow with isNewSignup=true")
                updateFlow(session: session, isNewSignup: true)
                return .session(session)
            case .verificationRequired:
                print("[SignUp] Verification required - setting pendingNewSignupVerification=true")
                pendingNewSignupVerification = true
                return .verificationRequired
            }
        } catch {
            print("[SignUp] Error: \(error)")
            throw AuthError.unknown
        }
    }

    public func signInWithGoogle() async throws {
        guard !isPerformingAuthAction else { return }

        isPerformingAuthAction = true
        defer { isPerformingAuthAction = false }

        do {
            let session = try await authUseCase.signInWithGoogle()
            updateFlow(session: session, isOAuthSignIn: true)
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
            updateFlow(session: session, isOAuthSignIn: true)
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
        isVerifyingEmail = true
        do {
            try await authUseCase.verifyEmailFromLink(url: url)
            // Don't clear isVerifyingEmail here — keep the overlay visible
            // until the auth session update transitions the flow state.
            // RootContentView clears it via clearVerifyingEmail() on flow state change.
            return nil
        } catch let error as AuthError {
            isVerifyingEmail = false
            return error
        } catch {
            isVerifyingEmail = false
            return .unknown
        }
    }

    /// Called by RootContentView when the flow state transitions away from authentication,
    /// ensuring the verification overlay stays visible until the actual screen transition.
    public func clearVerifyingEmail() {
        isVerifyingEmail = false
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

    private func updateFlow(session: AuthSession, isNewSignup: Bool = false, isOAuthSignIn: Bool = false) {
        print("[UpdateFlow] Called with isNewSignup=\(isNewSignup), isOAuthSignIn=\(isOAuthSignIn), session=\(session)")
        latestSession = session

        // Increment generation so any in-flight async Task from a previous updateFlow call
        // will detect it's stale and not override this newer state.
        flowUpdateGeneration &+= 1
        let myGeneration = flowUpdateGeneration

        // For signed-in users, we need to bind stores BEFORE resolving flow state
        // because flow resolution depends on user-specific flags
        if let user = session.user {
            print("[UpdateFlow] User authenticated: \(user.id) (generation=\(myGeneration))")
            Task {
                let userId = user.id.uuidString

                // 1. Bind all user-keyed stores first
                await onboardingUseCase.bind(to: userId)
                await voiceoverPreferencesStore.bind(to: userId)

                // 2. Bind the free credits alert tracker
                await FreeCreditsAlertTracker.shared.bind(to: userId)

                // 3. Resolve intro state for returning users (reinstall/new device)
                await self.resolveIntroState()

                // 3b. Fetch credit balance for the signed-in user
                await self.refreshCreditBalance()

                // 4. Now load flags with correct user binding
                let flags = await onboardingUseCase.flags()

                // 5. Check if user is a "returning onboarding user" (saw post-onboarding but never created a discovery)
                // Skip this check if user has already proceeded past post-onboarding this session
                let introDiscoveryCount = await FreeCreditsAlertTracker.shared.introDiscoveryCount
                let isInIntroMode = await FreeCreditsAlertTracker.shared.isInIntroMode
                let hasProceeded = self.hasProceededPastPostOnboardingThisSession
                let isReturningOnboardingUser = !hasProceeded
                    && flags.hasCompletedPostOnboarding
                    && introDiscoveryCount == 0
                    && isInIntroMode

                // 6. Resolve flow state with correct user flags
                // If returning onboarding user, override to show post-onboarding again
                // Guard: only update if no newer updateFlow call has occurred since we started.
                // This prevents stale async completions from overriding a more recent .signedOut
                // transition (e.g., when the auth observer fires during our async work).
                await MainActor.run {
                    guard myGeneration == self.flowUpdateGeneration else {
                        print("[UpdateFlow] Skipping stale flow update (generation=\(myGeneration), current=\(self.flowUpdateGeneration))")
                        return
                    }
                    self.currentFlags = flags
                    self.isReturningOnboardingUser = isReturningOnboardingUser

                    if isReturningOnboardingUser {
                        // User saw post-onboarding before but didn't create a discovery
                        // Show it again with "Welcome back" messaging
                        self.flowState = .postOnboarding(user)
                    } else {
                        self.flowState = self.flowResolver.resolve(session: session, flags: flags)
                    }
                }

                // Also skip post-flow-state work if generation is stale
                guard myGeneration == self.flowUpdateGeneration else { return }

                // 7. For new signups, record terms acceptance BEFORE checking compliance
                // This ensures the user doesn't see a terms modal immediately after signup
                // (they already agreed on the signup form)
                // Check both isNewSignup (immediate auth) and pendingNewSignupVerification (email verification flow)
                let shouldRecordTerms = isNewSignup || self.pendingNewSignupVerification
                if shouldRecordTerms {
                    print("[UpdateFlow] Recording terms acceptance (isNewSignup=\(isNewSignup), pendingVerification=\(self.pendingNewSignupVerification))")
                    // Clear the pending flag
                    await MainActor.run {
                        self.pendingNewSignupVerification = false
                    }
                    await self.recordTermsAcceptanceForNewUser()
                } else if isOAuthSignIn {
                    // For OAuth sign-ins, we don't know if they're new or returning
                    // Check if they have any prior acceptance records and record if not
                    print("[UpdateFlow] OAuth sign-in - checking if new user needs terms recorded")
                    await self.recordTermsForNewOAuthUserIfNeeded()
                } else {
                    print("[UpdateFlow] Skipping terms recording (returning user)")
                }

                // 8. Check compliance after user is authenticated
                await self.checkCompliance()
            }
        } else {
            // Not signed in - resolve immediately with current flags
            flowState = flowResolver.resolve(session: session, flags: currentFlags)

            // Clear compliance state when signed out
            complianceBlockingState = nil
            complianceNonBlockingState = nil
            pendingLegalAcceptance = false
            isReturningOnboardingUser = false
        }
    }

    /// Records terms acceptance for a newly signed up user.
    /// Called after successful signup since user agreed to terms on the signup form.
    private func recordTermsAcceptanceForNewUser() async {
        do {
            let config = try await complianceUseCase.fetchConfig(forceFresh: true)
            _ = try await complianceUseCase.acceptTerms(
                tosVersion: config.tos.version,
                privacyVersion: config.privacy.version
            )
            print("[ViewModel] Recorded terms acceptance for new user - tos=\(config.tos.version), privacy=\(config.privacy.version)")
        } catch {
            // Failure is acceptable - user will see modal on first safe screen
            print("[ViewModel] Failed to record terms acceptance for new user: \(error)")
        }
    }

    /// Records terms acceptance for OAuth users who are signing up for the first time.
    /// Only records if the user has no prior acceptance records (truly new user).
    /// For returning OAuth users, this is a no-op - compliance check will handle updated terms.
    private func recordTermsForNewOAuthUserIfNeeded() async {
        do {
            let config = try await complianceUseCase.fetchConfig(forceFresh: true)

            // Check if user has any prior acceptance records
            // A truly new OAuth user will have nil for both
            guard let userStatus = config.userStatus,
                  userStatus.acceptedTosVersion == nil && userStatus.acceptedPrivacyVersion == nil else {
                print("[ViewModel] OAuth user already has acceptance records, skipping auto-accept")
                return
            }

            // New OAuth user - record acceptance (they agreed by completing OAuth signup)
            _ = try await complianceUseCase.acceptTerms(
                tosVersion: config.tos.version,
                privacyVersion: config.privacy.version
            )
            print("[ViewModel] Recorded terms acceptance for new OAuth user - tos=\(config.tos.version), privacy=\(config.privacy.version)")
        } catch {
            // Failure is acceptable - user will see modal on first safe screen
            print("[ViewModel] Failed to record OAuth user terms: \(error)")
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

    /// Dismisses the force grace period reminder
    public func dismissForceGracePeriodReminder() async {
        await complianceUseCase.dismissForceGracePeriodReminder()
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
