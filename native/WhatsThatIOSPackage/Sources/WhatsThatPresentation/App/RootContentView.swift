import SwiftUI
import WhatsThatDomain
import WhatsThatShared
import CoreLocation
import UIKit
import Combine

public struct RootContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var passwordResetLinkCoordinator: PasswordResetLinkCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: AppRootViewModel
    @State private var authError: AuthError?
    @State private var authStartMode: AuthenticationFlowView.Mode = .signUp
    @State private var isSettingsPresented = false
    @State private var settingsSheetDetent: PresentationDetent = .fraction(0.8)
    @State private var mainTabDestination: MainTabDestination = .discoveries
    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.system.rawValue
    @State private var currentScreenIsSafe: Bool = true
    @State private var showSoftUpdateSheet: Bool = false
    @State private var showForceGraceSheet: Bool = false
    private let deletionUseCase: DiscoveryDeletionUseCase
    private let makeCreationViewModel: (DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel
    /// Single shared AudioServicesContainer instance created once and passed to MainTabView
    @StateObject private var audioServicesContainer: AudioServicesContainer
    /// Coordinates the discovery creation flow lifecycle (owns ViewModels, modal state, completion tracking)
    @StateObject private var creationFlowCoordinator: CreationFlowCoordinator
    @StateObject private var storeObserver: DiscoveryStoreObserver
    @StateObject private var postPurchaseConfigProvider: PostPurchaseConfigProvider
    private let makeCreditsViewModel: (() -> CreditsViewModel)?
    private let fetchCreditBalance: () async -> Result<Int, Error>
    private let clearAppStoreLocal: () async -> Result<Void, Error>
    private let makeNearbyCacheInspector: (() -> AnyView)?
    private let startLocationTracking: (() async -> Void)?
    private let stopLocationTracking: (() -> Void)?
    private let loadVoiceoverPreferences: () async -> VoiceoverPreferences
    private let saveVoiceoverPreferences: (VoiceoverPreferences) async -> Void
    private let fetchVoiceOptions: () async -> [VoiceModelOption]
    private let fetchVoiceSampleURL: (String) async -> URL?
    private let loadIPoPPreferences: () async -> IPoPPreferences?
    private let saveIPoPPreferences: (IPoPPreferences) async -> Void
    private let resetIPoPPreferences: () async -> Void
    private let clearAllUserData: () async -> Void
    private let voiceoverPreferencesStore: VoiceoverPreferencesStore
    private let complianceUseCase: ComplianceUseCase
    private let resolveIntroState: () async -> Void
    private let refreshCreditBalance: () async -> Void
    private let sampleDiscoveryService: SampleDiscoveryService?
    private let makeOnboardingVoiceoverController: (() -> VoiceoverPlaybackController)?
    #if DEBUG
    private let setCreditBalance: (Int) async -> Void
    #endif
    @State private var processedPasswordResetTokens: Set<String> = []
    @State private var processingPasswordResetToken: String?

    public init(
        deletionUseCase: DiscoveryDeletionUseCase,
        authUseCase: AuthUseCase,
        onboardingUseCase: OnboardingUseCase,
        flowResolver: AppFlowResolver = AppFlowResolver(),
        makeCreationViewModel: @escaping (DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel,
        makeAudioServicesContainer: (() -> AudioServicesContainer)? = nil,
        storeObserver: DiscoveryStoreObserver,
        makeCreditsViewModel: (() -> CreditsViewModel)? = nil,
        fetchCreditBalance: @escaping () async -> Result<Int, Error> = { .failure(AuthError.unknown) },
        clearAppStoreLocal: @escaping () async -> Result<Void, Error> = { .failure(AuthError.unknown) },
        makeNearbyCacheInspector: (() -> AnyView)? = nil,
        startLocationTracking: (() async -> Void)? = nil,
        stopLocationTracking: (() -> Void)? = nil,
        loadVoiceoverPreferences: @escaping () async -> VoiceoverPreferences,
        saveVoiceoverPreferences: @escaping (VoiceoverPreferences) async -> Void,
        fetchVoiceOptions: @escaping () async -> [VoiceModelOption],
        fetchVoiceSampleURL: @escaping (String) async -> URL?,
        loadIPoPPreferences: @escaping () async -> IPoPPreferences?,
        saveIPoPPreferences: @escaping (IPoPPreferences) async -> Void,
        resetIPoPPreferences: @escaping () async -> Void = {},
        clearAllUserData: @escaping () async -> Void,
        voiceoverPreferencesStore: VoiceoverPreferencesStore,
        complianceUseCase: ComplianceUseCase,
        setCreditBalance: @escaping (Int) async -> Void = { _ in },
        resolveIntroState: @escaping () async -> Void = {},
        refreshCreditBalance: @escaping () async -> Void = {},
        sampleDiscoveryService: SampleDiscoveryService? = nil,
        makeOnboardingVoiceoverController: (() -> VoiceoverPlaybackController)? = nil
    ) {
        #if DEBUG
        self.setCreditBalance = setCreditBalance
        #endif
        self.deletionUseCase = deletionUseCase
        self.makeCreationViewModel = makeCreationViewModel
        // Create AudioServicesContainer once here as StateObject to ensure single instance
        let audioServicesInstance: AudioServicesContainer
        if let factory = makeAudioServicesContainer {
            audioServicesInstance = factory()
            _audioServicesContainer = StateObject(wrappedValue: audioServicesInstance)
        } else {
            fatalError("AudioServicesContainer factory is required on iOS")
        }
        _storeObserver = StateObject(wrappedValue: storeObserver)
        // Create coordinator with stable VM instances and all creation-flow dependencies.
        // The coordinator owns the ViewModels (previously separate StateObjects) and
        // manages modal presentation, discovery completion tracking, and session manager config.
        let cameraVM = makeCreationViewModel(.camera)
        let uploadVM = makeCreationViewModel(.upload)
        _creationFlowCoordinator = StateObject(wrappedValue: CreationFlowCoordinator(
            cameraViewModel: cameraVM,
            uploadViewModel: uploadVM,
            audioServices: audioServicesInstance,
            storeObserver: storeObserver,
            makeCreditsViewModel: makeCreditsViewModel,
            loadVoiceoverPreferences: loadVoiceoverPreferences,
            saveVoiceoverPreferences: saveVoiceoverPreferences,
            fetchVoiceOptions: fetchVoiceOptions,
            fetchVoiceSampleURL: fetchVoiceSampleURL,
            loadIPoPPreferences: loadIPoPPreferences,
            saveIPoPPreferences: saveIPoPPreferences
        ))
        _postPurchaseConfigProvider = StateObject(wrappedValue: PostPurchaseConfigProvider(
            loadVoiceoverPreferences: loadVoiceoverPreferences,
            saveVoiceoverPreferences: saveVoiceoverPreferences,
            fetchVoiceOptions: fetchVoiceOptions,
            fetchVoiceSampleURL: fetchVoiceSampleURL,
            loadIPoPPreferences: loadIPoPPreferences,
            saveIPoPPreferences: saveIPoPPreferences
        ))
        self.makeCreditsViewModel = makeCreditsViewModel
        self.fetchCreditBalance = fetchCreditBalance
        self.clearAppStoreLocal = clearAppStoreLocal
        self.makeNearbyCacheInspector = makeNearbyCacheInspector
        self.startLocationTracking = startLocationTracking
        self.stopLocationTracking = stopLocationTracking
        self.loadVoiceoverPreferences = loadVoiceoverPreferences
        self.saveVoiceoverPreferences = saveVoiceoverPreferences
        self.fetchVoiceOptions = fetchVoiceOptions
        self.fetchVoiceSampleURL = fetchVoiceSampleURL
        self.loadIPoPPreferences = loadIPoPPreferences
        self.saveIPoPPreferences = saveIPoPPreferences
        self.resetIPoPPreferences = resetIPoPPreferences
        self.clearAllUserData = clearAllUserData
        self.voiceoverPreferencesStore = voiceoverPreferencesStore
        self.complianceUseCase = complianceUseCase
        self.resolveIntroState = resolveIntroState
        self.refreshCreditBalance = refreshCreditBalance
        self.sampleDiscoveryService = sampleDiscoveryService
        self.makeOnboardingVoiceoverController = makeOnboardingVoiceoverController

        // Compose clearAllUserData with observer reset to clear all UI state on sign-out
        let observerToReset = storeObserver
        let composedClearAll: () async -> Void = {
            await clearAllUserData()
            await MainActor.run {
                observerToReset.reset()
            }
        }

        _viewModel = StateObject<AppRootViewModel>(
            wrappedValue: AppRootViewModel(
                authUseCase: authUseCase,
                onboardingUseCase: onboardingUseCase,
                flowResolver: flowResolver,
                clearAllUserData: composedClearAll,
                voiceoverPreferencesStore: voiceoverPreferencesStore,
                complianceUseCase: complianceUseCase,
                resolveIntroState: resolveIntroState,
                refreshCreditBalance: refreshCreditBalance
            )
        )
    }

    public var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            mainContent
            passwordResetOverlay
            complianceOverlay
            emailVerificationOverlay
        }
        .modifier(RootContentPaddingModifier(flowState: viewModel.flowState))
        .animation(.easeInOut, value: viewModel.flowState)
        .environment(\.postPurchaseConfig, postPurchaseConfigProvider)
        .sheet(isPresented: $isSettingsPresented, onDismiss: {
            settingsSheetDetent = .fraction(0.8)
        }) {
            SettingsView(
                userEmail: settingsUser?.email,
                canRequestPasswordReset: settingsUser?.allowsPasswordReset ?? false,
                onResetOnboarding: {
                    await viewModel.resetOnboarding()
                    await resetIPoPPreferences()
                    return .success(())
                },
                onFetchCreditBalance: {
                    await fetchCreditBalance()
                },
                makeCreditsView: { balanceUpdate in
                    guard let makeCreditsViewModel else {
                        return AnyView(CreditsUnavailableView())
                    }
                    let viewModel = makeCreditsViewModel()
                    viewModel.onBalanceUpdated = { newBalance in
                        balanceUpdate(newBalance)
                    }
                    return AnyView(
                        CreditsView(
                            viewModel: viewModel,
                            backButtonTitle: "Settings",
                            loadVoiceoverPreferences: loadVoiceoverPreferences,
                            saveVoiceoverPreferences: saveVoiceoverPreferences,
                            fetchVoiceOptions: fetchVoiceOptions,
                            fetchVoiceSampleURL: fetchVoiceSampleURL,
                            loadIPoPPreferences: loadIPoPPreferences,
                            saveIPoPPreferences: saveIPoPPreferences
                        )
                    )
                },
                makeNearbyCacheInspector: { makeNearbyCacheInspector?() ?? AnyView(Text("Not available")) },
                onSendPasswordReset: { email in
                    do {
                        try await viewModel.requestPasswordReset(email: email)
                        return .success(())
                    } catch let error as AuthError {
                        return .failure(error)
                    } catch {
                        return .failure(.unknown)
                    }
                },
                onSignOut: {
                    do {
                        try await viewModel.signOut()
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                },
                onClearAppStoreAccount: {
                    await clearAppStoreLocal()
                },
                onDeleteAccount: {
                    do {
                        try await viewModel.deleteAccount()
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                },
                onClose: {
                    isSettingsPresented = false
                },
                loadVoiceoverPreferences: loadVoiceoverPreferences,
                saveVoiceoverPreferences: saveVoiceoverPreferences,
                fetchVoiceOptions: fetchVoiceOptions,
                fetchVoiceSampleURL: fetchVoiceSampleURL,
                loadIPoPPreferences: loadIPoPPreferences,
                saveIPoPPreferences: saveIPoPPreferences,
                onSetCreditBalance: { amount in
                    #if DEBUG
                    await setCreditBalance(amount)
                    #endif
                }
            )
            .presentationDetents([.fraction(0.8), .large], selection: $settingsSheetDetent)
        }
        .fullScreenCover(isPresented: $showSoftUpdateSheet) {
            if case .softUpdateReminder(let version, let url, let message) = viewModel.complianceNonBlockingState {
                SoftUpdatePromptView(
                    targetVersion: version,
                    currentVersion: Bundle.main.appVersion,
                    message: message,
                    onUpdate: {
                        if let appStoreUrl = URL(string: url) {
                            UIApplication.shared.open(appStoreUrl)
                        }
                        showSoftUpdateSheet = false
                    },
                    onDismiss: {
                        Task { await viewModel.dismissSoftUpdateReminder() }
                        showSoftUpdateSheet = false
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showForceGraceSheet) {
            if case .forceUpdateGrace(let version, let days, let url, let message) = viewModel.complianceNonBlockingState {
                ForceUpdateGracePromptView(
                    targetVersion: version,
                    currentVersion: Bundle.main.appVersion,
                    daysRemaining: days,
                    message: message,
                    onUpdate: {
                        if let appStoreUrl = URL(string: url) {
                            UIApplication.shared.open(appStoreUrl)
                        }
                        showForceGraceSheet = false
                    },
                    onDismiss: {
                        Task { await viewModel.dismissForceGracePeriodReminder() }
                        showForceGraceSheet = false
                    }
                )
            }
        }
        .alert(
            authError?.alertTitle ?? "Something went wrong",
            isPresented: Binding(
                get: { authError != nil },
                set: { isPresented in
                    if !isPresented { authError = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authError?.errorDescription ?? "Please try again.")
        }
        .preferredColorScheme(appearance.colorScheme)
        .onAppear(perform: syncBrandTheme)
        .onReceive(passwordResetLinkCoordinator.urlPublisher) { url in
            #if DEBUG
            print("[DeepLink] Received URL: \(url.absoluteString)")
            print("[DeepLink] isEmailVerificationURL: \(isEmailVerificationURL(url))")
            print("[DeepLink] Path: \(url.path)")
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                print("[DeepLink] Query items: \(components.queryItems ?? [])")
            }
            #endif
            if isEmailVerificationURL(url) {
                handleEmailVerificationURL(url)
            } else {
                handlePasswordResetURL(url)
            }
        }
        .onChange(of: viewModel.flowState) { previous, current in
            guard previous != current else { return }
            // Clear verification overlay instantly (no animation) so it doesn't
            // linger during the flowState transition and block touches.
            if viewModel.isVerifyingEmail, case .authentication = previous {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    viewModel.clearVerifyingEmail()
                }
            }
            if case .authentication = current {
                switch previous {
                case .main, .postOnboarding:
                    authStartMode = .signIn
                case .preOnboarding:
                    // Keep the authStartMode that was set by the button callback
                    // (signIn if user tapped "Sign in", signUp if user tapped "Create Your Own")
                    break
                default:
                    authStartMode = .signUp
                }
            }
            // Start/resume tracking when authenticated and app is active; stop when leaving main state
            if case .main = current, scenePhase == .active {
                if let startLocationTracking {
                    // print("[App][Flow] -> main (scene=active) starting location tracking")
                    Task { await startLocationTracking() }
                }
            }
            if case .main = previous, case .main = current {
                // still main -> no-op
            } else if case .main = previous {
                // print("[App][Flow] leaving main -> stopping location tracking")
                stopLocationTracking?()
            }
        }
        .onChange(of: storedAppearance) { _, _ in
            syncBrandTheme()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Start/resume tracking on foreground when authenticated; stop otherwise
            switch newPhase {
            case .active:
                if case .main = viewModel.flowState {
                    if let startLocationTracking {
                        // print("[App][ScenePhase] -> active (flow=main) starting location tracking")
                        Task { await startLocationTracking() }
                    } else {
                        // print("[App][ScenePhase] -> active (flow=main) but no startLocationTracking")
                    }

                    // Re-show non-blocking compliance sheets if they were dismissed but state still active
                    // This handles the case where user tapped "Update Now", went to App Store, and returned without updating
                    if currentScreenIsSafe {
                        if case .softUpdateReminder = viewModel.complianceNonBlockingState, !showSoftUpdateSheet {
                            showSoftUpdateSheet = true
                        } else if case .forceUpdateGrace = viewModel.complianceNonBlockingState, !showForceGraceSheet {
                            showForceGraceSheet = true
                        }
                    }

                    // Refresh compliance if stale when app returns to foreground
                    Task { await viewModel.refreshComplianceIfStale() }
                } else {
                    // print("[App][ScenePhase] -> active (flow=\(String(describing: viewModel.flowState))) not starting tracking")
                }
            case .background, .inactive:
                // print("[App][ScenePhase] -> \(newPhase == .background ? "background" : "inactive") stopping location tracking")
                stopLocationTracking?()
            @unknown default:
                break
            }
        }
        .onChange(of: viewModel.complianceNonBlockingState) { _, newValue in
            guard currentScreenIsSafe else { return }
            switch newValue {
            case .softUpdateReminder:
                showSoftUpdateSheet = true
            case .forceUpdateGrace:
                showForceGraceSheet = true
            case .none:
                break
            }
        }
    }

    private var settingsUser: AuthenticatedUser? {
        if case let .main(user) = viewModel.flowState {
            return user
        }
        return nil
    }



    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: storedAppearance) ?? .system
    }

    private func syncBrandTheme() {
        let mode = appearance.brandMode
        if BrandTheme.activeMode != mode {
            BrandTheme.activeMode = mode
        }
    }

    private func handleAuthOperation(_ operation: @escaping () async throws -> Void) async throws {
        do {
            try await operation()
        } catch let authError as AuthError {
            // Do not show alerts for user-cancelled sign-ins
            if authError != .cancelled {
                await MainActor.run { self.authError = authError }
            }
            throw authError
        } catch {
            await MainActor.run { self.authError = .unknown }
            throw AuthError.unknown
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.flowState {
        case .loading:
            ProgressView()
                .progressViewStyle(.circular)
        case .preOnboarding:
            preOnboardingView
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .authentication:
            AuthenticationFlowView(
                isPerformingAction: viewModel.isPerformingAuthAction,
                initialMode: authStartMode,
                onSignIn: { email, password in
                    do {
                        let outcome = try await viewModel.signIn(email: email, password: password)
                        switch outcome {
                        case .session:
                            return .success
                        case .verificationRequired(let email):
                            return .verificationRequired(email: email)
                        }
                    } catch {
                        try await handleAuthOperation { throw error }
                        throw error
                    }
                },
                onSignUp: { email, password in
                    do {
                        let outcome = try await viewModel.signUp(email: email, password: password)
                        switch outcome {
                        case .session:
                            return .success
                        case .verificationRequired:
                            return .verificationRequired
                        }
                    } catch {
                        // For generic errors, we want to show the alert.
                        // check handleAuthOperation usage: it rethrows.
                        // We must rethrow to let AuthenticationFlowView handle the failure state (stop loading).
                        // AND we want RootContentView to show the alert.
                        try await handleAuthOperation { throw error }
                        // The compiler needs a return, but handleAuthOperation throws.
                        // So this line is unreachable but required for flow analysis sometimes.
                        throw error
                    }
                },
                onForgotPassword: { email in
                    do {
                        try await viewModel.requestPasswordReset(email: email)
                        return .success
                    } catch let error as AuthError {
                        try? await handleAuthOperation { throw error }
                        return .failure(error)
                    } catch {
                        try? await handleAuthOperation { throw error }
                        return .failure(.unknown)
                    }
                },
                onGoogle: {
                    try await handleAuthOperation {
                        try await viewModel.signInWithGoogle()
                    }
                },
                onApple: {
                    try await handleAuthOperation {
                        try await viewModel.signInWithApple()
                    }
                }
            )
            .id(authStartMode)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .postOnboarding(_):
            PostOnboardingCarousel(
                onComplete: {
                    mainTabDestination = .discoveries
                    _ = Task { await viewModel.completePostOnboarding() }
                },
                onLaunchCamera: {
                    mainTabDestination = .camera
                    _ = Task { await viewModel.completePostOnboarding() }
                },
                onLaunchUpload: {
                    mainTabDestination = .upload
                    _ = Task { await viewModel.completePostOnboarding() }
                },
                isReturningUser: viewModel.isReturningOnboardingUser,
                loadVoiceoverPreferences: loadVoiceoverPreferences,
                saveVoiceoverPreferences: saveVoiceoverPreferences,
                fetchVoiceOptions: fetchVoiceOptions,
                fetchVoiceSampleURL: fetchVoiceSampleURL,
                loadIPoPPreferences: loadIPoPPreferences,
                saveIPoPPreferences: saveIPoPPreferences
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .main:
            MainTabView(
                coordinator: creationFlowCoordinator,
                storeObserver: storeObserver,
                deletionUseCase: deletionUseCase,
                audioServices: audioServicesContainer,
                initialTab: mainTabDestination,
                onSignOut: {
                    Task { try? await viewModel.signOut() }
                },
                onSettings: {
                    isSettingsPresented = true
                },
                isSettingsPresented: $isSettingsPresented,
                onScreenSafetyChanged: { isSafe in
                    currentScreenIsSafe = isSafe
                }
            )
            .onAppear {
                mainTabDestination = .discoveries
            }
        }
    }

    @ViewBuilder
    private var preOnboardingView: some View {
        if let service = sampleDiscoveryService, let makeController = makeOnboardingVoiceoverController {
            PreOnboardingCarousel(
                discoveryService: service,
                makeVoiceoverController: makeController,
                onContinue: {
                    authStartMode = .signUp
                    _ = Task { await viewModel.completePreOnboarding() }
                },
                onSignIn: {
                    authStartMode = .signIn
                    _ = Task { await viewModel.completePreOnboarding() }
                }
            )
            .id("preOnboardingDiscoveries") // Stable identity to prevent view recreation
        } else {
            // Fallback to legacy carousel when discovery service is not available
            PreOnboardingCarousel {
                _ = Task { await viewModel.completePreOnboarding() }
            }
            .id("preOnboardingLegacy")
        }
    }

    @ViewBuilder
    private var passwordResetOverlay: some View {
        if let user = viewModel.passwordResetUser {
            PasswordResetView(
                email: user.email,
                onSubmit: { newPassword in
                    if let error = await viewModel.completePasswordReset(newPassword: newPassword) {
                        return .failure(error)
                    } else {
                        return .success(())
                    }
                },
                onComplete: {
                    processedPasswordResetTokens.removeAll()
                    Task {
                        await viewModel.cancelPasswordResetFlow()
                        await MainActor.run {
                            authStartMode = .signIn
                        }
                    }
                },
                onCancel: {
                    processedPasswordResetTokens.removeAll()
                    Task {
                        await viewModel.cancelPasswordResetFlow()
                        await MainActor.run {
                            authStartMode = .signIn
                        }
                    }
                }
            )
            .transition(.opacity)
            .zIndex(1)
        }
    }

    @ViewBuilder
    private var complianceOverlay: some View {
        // Only show blocking overlays when:
        // 1. In main app state (authenticated and past onboarding)
        // 2. There's a blocking compliance state
        // 3. User is on a safe screen (Discoveries or Audio Guides tab, not in creation flow)
        //
        // This prevents compliance overlays from interrupting the discovery creation flow,
        // which has its own specialized flow logic that should not be disrupted.
        if case .main = viewModel.flowState,
           let blockingState = viewModel.complianceBlockingState,
           currentScreenIsSafe {
            ComplianceOverlayView(
                blockingState: blockingState,
                onAcceptTerms: { tosVersion, privacyVersion in
                    do {
                        try await viewModel.acceptTerms(tosVersion: tosVersion, privacyVersion: privacyVersion)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                },
                onSignOut: {
                    try? await viewModel.signOut()
                },
                onOpenAppStore: { url in
                    if let url = URL(string: url) {
                        UIApplication.shared.open(url)
                    }
                },
                onCheckAgain: {
                    await viewModel.checkCompliance()
                }
            )
            .transition(.opacity)
            .zIndex(2)
        }
    }

    @ViewBuilder
    private var emailVerificationOverlay: some View {
        if viewModel.isVerifyingEmail {
            ZStack {
                (colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    EmailVerificationSpinner()
                    Text("Signing you in...")
                        .font(.body)
                        .foregroundStyle(colorScheme == .dark ? .white : .primary)
                }
            }
            .zIndex(3)
        }
    }

    private func handlePasswordResetURL(_ url: URL) {
        guard let targetURL = extractPasswordResetURL(from: url) else { return }
        let tokenIdentifier = passwordResetTokenIdentifier(for: targetURL)
        if processingPasswordResetToken == tokenIdentifier { return }
        if processedPasswordResetTokens.contains(tokenIdentifier) { return }

        processingPasswordResetToken = tokenIdentifier
        Task {
            await MainActor.run {
                if isSettingsPresented {
                    isSettingsPresented = false
                }
            }
            let error = await viewModel.preparePasswordReset(from: targetURL)
            await MainActor.run {
                processingPasswordResetToken = nil
                if let error {
                    authError = error
                } else {
                    processedPasswordResetTokens.insert(tokenIdentifier)
                }
            }
        }
    }

    private func isPasswordResetURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "https" {
            let path = url.path.lowercased()
            return path.hasPrefix("/auth/reset")
        }
        // Accept custom scheme deep link for password reset as well
        if scheme == "whatsthat" { return true }
        return false
    }

    private func extractPasswordResetURL(from url: URL) -> URL? {
        if isPasswordResetURL(url) {
            return url
        }

        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let rawValue = components.queryItems?.first(where: { $0.name == "supabase_url" })?.value
        else {
            return nil
        }

        if let decoded = rawValue.removingPercentEncoding,
           let decodedURL = URL(string: decoded),
           isPasswordResetURL(decodedURL) {
            return decodedURL
        }

        if let url = URL(string: rawValue), isPasswordResetURL(url) {
            return url
        }

        return nil
    }

    private func passwordResetTokenIdentifier(for url: URL) -> String {
        if let fragment = url.fragment, fragment.contains("access_token=") {
            return fragment
        }

        if let query = url.query, query.contains("access_token=") {
            return query
        }

        return url.absoluteString
    }

    // MARK: - Email Verification Handling

    private func isEmailVerificationURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        
        // Check for custom scheme deep link: whatsthat://auth/verify
        // In this URL structure: host = "auth", path = "/verify"
        if scheme == "whatsthat" {
            let host = url.host?.lowercased() ?? ""
            let path = url.path.lowercased()
            return host == "auth" && path == "/verify"
        }
        
        // Check for https URL: https://whats-that.app/auth/verify
        if scheme == "https" {
            let path = url.path.lowercased()
            return path.hasPrefix("/auth/verify")
        }
        
        // Check query params for signup type as fallback
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let type = components.queryItems?.first(where: { $0.name == "type" })?.value?.lowercased() {
            return type == "signup" || type == "email"
        }
        
        return false
    }

    private func handleEmailVerificationURL(_ url: URL) {
        Task {
            let error = await viewModel.verifyEmail(from: url)
            await MainActor.run {
                if let error {
                    authError = error
                } else {
                    // Verification builds the session automatically, so no need to alert or switch mode manually.
                    // The view model's session state will update, triggering the flow transition.
                }
            }
        }
    }
}

private struct EmailVerificationSpinner: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            BrandColors.spinner.opacity(0.1),
                            BrandColors.spinner
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    .linear(duration: 1.2).repeatForever(autoreverses: false),
                    value: isAnimating
                )
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
        }
        .onAppear { isAnimating = true }
    }
}
