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
    private let deletionUseCase: DiscoveryDeletionUseCase
    private let makeCreationViewModel: (DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel
    private let makeAudioServicesContainer: (() -> AudioServicesContainer)?
    @StateObject private var storeObserver: DiscoveryStoreObserver
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
        setCreditBalance: @escaping (Int) async -> Void = { _ in }
    ) {
        #if DEBUG
        self.setCreditBalance = setCreditBalance
        #endif
        self.deletionUseCase = deletionUseCase
        self.makeCreationViewModel = makeCreationViewModel
        self.makeAudioServicesContainer = makeAudioServicesContainer
        _storeObserver = StateObject(wrappedValue: storeObserver)
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
                voiceoverPreferencesStore: voiceoverPreferencesStore
            )
        )
    }

    public var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            mainContent
            passwordResetOverlay
        }
        .modifier(RootContentPaddingModifier(flowState: viewModel.flowState))
        .animation(.easeInOut, value: viewModel.flowState)
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
                            backButtonTitle: "Settings"
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
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { authError != nil },
                set: { isPresented in
                    if !isPresented { authError = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .preferredColorScheme(appearance.colorScheme)
        .onAppear(perform: syncBrandTheme)
        .onReceive(passwordResetLinkCoordinator.urlPublisher) { url in
            handlePasswordResetURL(url)
        }
        .onChange(of: viewModel.flowState) { previous, current in
            guard previous != current else { return }
            if case .authentication = current {
                switch previous {
                case .main, .postOnboarding:
                    authStartMode = .signIn
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
    }

    private var settingsUser: AuthenticatedUser? {
        if case let .main(user) = viewModel.flowState {
            return user
        }
        return nil
    }

    // MARK: - Alert Copy

    private var alertTitle: String {
        guard let authError else { return "Something went wrong" }
        switch authError {
        case .invalidCredentials:
            return "Invalid credentials"
        case .emailAlreadyInUse:
            return "Email already in use"
        case .passwordTooWeak:
            return "Weak password"
        case .passwordResetFailed:
            return "Whoops"
        case .passwordResetRateLimited:
            return "Too many attempts"
        case .passwordResetLinkInvalid:
            return "Invalid link"
        case .passwordResetLinkExpired:
            return "Link expired"
        case .passwordUpdateFailed:
            return "Update failed"
        case .passwordSame:
            return "Use a different password"
        case .cancelled:
            return "Sign in cancelled"
        case .accountDeletionFailed:
            return "Couldn't delete account"
        case .unknown:
            return "Something went wrong"
        }
    }

    private var alertMessage: String {
        guard let authError else { return "Please try again." }
        switch authError {
        case .invalidCredentials:
            return "We couldn't sign you in. Check your email and password are correct."
        case .emailAlreadyInUse:
            return "An account with this email already exists. Try signing in instead."
        case .passwordTooWeak:
            return "Your password must be at least 8 characters and include an uppercase letter, a lowercase letter, a number, and a symbol."
        case .passwordResetFailed:
            return "There was an issue resetting your password. Please try again in a few minutes."
        case .passwordResetRateLimited:
            return "For security reasons, we have rate-limited your request. Please try again in a few minutes."
        case .passwordResetLinkInvalid:
            return "That reset link isn't valid anymore. Please request a fresh one."
        case .passwordResetLinkExpired:
            return "Your reset link has expired. Request a new one to continue."
        case .passwordUpdateFailed:
            return "We couldn't update your password. Please try again."
        case .passwordSame:
            return "Your new password is the same as your current password. Please choose a different one."
        case .cancelled:
            return "This sign in was cancelled."
        case .accountDeletionFailed:
            return "We couldn't delete your account. Please try again or contact support."
        case .unknown:
            return "Please try again."
        }
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
            PreOnboardingCarousel {
                _ = Task { await viewModel.completePreOnboarding() }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .authentication:
            AuthenticationFlowView(
                isPerformingAction: viewModel.isPerformingAuthAction,
                initialMode: authStartMode,
                onSignIn: { email, password in
                    try await handleAuthOperation {
                        try await viewModel.signIn(email: email, password: password)
                    }
                },
                onSignUp: { email, password in
                    try await handleAuthOperation {
                        try await viewModel.signUp(email: email, password: password)
                    }
                },
                onForgotPassword: { email in
                    do {
                        try await viewModel.requestPasswordReset(email: email)
                        return .success
                    } catch let error as AuthError {
                        return .failure(error)
                    } catch {
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
                loadVoiceoverPreferences: loadVoiceoverPreferences,
                saveVoiceoverPreferences: saveVoiceoverPreferences,
                fetchVoiceOptions: fetchVoiceOptions,
                fetchVoiceSampleURL: fetchVoiceSampleURL,
                loadIPoPPreferences: loadIPoPPreferences,
                saveIPoPPreferences: saveIPoPPreferences
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .main:
            if let makeAudioServicesContainer {
                MainTabView(
                    storeObserver: storeObserver,
                    deletionUseCase: deletionUseCase,
                    cameraViewModel: makeCreationViewModel(.camera),
                    uploadViewModel: makeCreationViewModel(.upload),
                    audioServicesFactory: makeAudioServicesContainer,
                    initialTab: mainTabDestination,
                    onSignOut: {
                        Task { try? await viewModel.signOut() }
                    },
                    onSettings: {
                        isSettingsPresented = true
                    },
                    makeCreditsViewModel: makeCreditsViewModel
                )
                .onAppear {
                    mainTabDestination = .discoveries
                }
            } else {
                Text("Audio services are available on iOS builds only.")
                    .font(.headline)
            }
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
}
