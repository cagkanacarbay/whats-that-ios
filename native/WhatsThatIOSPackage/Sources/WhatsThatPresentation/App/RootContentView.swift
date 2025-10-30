import SwiftUI
import WhatsThatDomain
import WhatsThatShared
import CoreLocation
import UIKit
import Combine

public struct RootContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var passwordResetLinkCoordinator: PasswordResetLinkCoordinator
    @StateObject private var viewModel: AppRootViewModel
    @State private var authError: AuthError?
    @State private var authStartMode: AuthenticationFlowView.Mode = .signUp
    @State private var isSettingsPresented = false
    @State private var settingsSheetDetent: PresentationDetent = .fraction(0.8)
    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.system.rawValue
    private let feedUseCase: DiscoveryFeedUseCase
    private let deletionUseCase: DiscoveryDeletionUseCase
    private let makeCreationViewModel: (DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel
    private let makeVoiceoverController: (() -> VoiceoverPlaybackController)?
    private let makeCreditsViewModel: (() -> CreditsViewModel)?
    private let fetchCreditBalance: () async -> Result<Int, Error>
    private let clearAppStoreLocal: () async -> Result<Void, Error>
    @State private var processedPasswordResetTokens: Set<String> = []
    @State private var processingPasswordResetToken: String?

    public init(
        feedUseCase: DiscoveryFeedUseCase,
        deletionUseCase: DiscoveryDeletionUseCase,
        authUseCase: AuthUseCase,
        onboardingUseCase: OnboardingUseCase,
        flowResolver: AppFlowResolver = AppFlowResolver(),
        makeCreationViewModel: @escaping (DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel,
        makeVoiceoverController: (() -> VoiceoverPlaybackController)? = nil,
        makeCreditsViewModel: (() -> CreditsViewModel)? = nil,
        fetchCreditBalance: @escaping () async -> Result<Int, Error> = { .failure(AuthError.unknown) },
        clearAppStoreLocal: @escaping () async -> Result<Void, Error> = { .failure(AuthError.unknown) }
    ) {
        self.feedUseCase = feedUseCase
        self.deletionUseCase = deletionUseCase
        self.makeCreationViewModel = makeCreationViewModel
        self.makeVoiceoverController = makeVoiceoverController
        self.makeCreditsViewModel = makeCreditsViewModel
        self.fetchCreditBalance = fetchCreditBalance
        self.clearAppStoreLocal = clearAppStoreLocal
        _viewModel = StateObject(
            wrappedValue: AppRootViewModel(
                authUseCase: authUseCase,
                onboardingUseCase: onboardingUseCase,
                flowResolver: flowResolver
            )
        )
    }

    public var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            Group {
                switch viewModel.flowState {
                case .loading:
                    ProgressView()
                        .progressViewStyle(.circular)
                case .preOnboarding:
                    PreOnboardingCarousel {
                        Task { await viewModel.completePreOnboarding() }
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
                case let .postOnboarding(user):
                    PostOnboardingSummary(
                        user: user,
                        onContinue: {
                            Task { await viewModel.completePostOnboarding() }
                        },
                        onSignOut: {
                            Task { try? await viewModel.signOut() }
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .main:
                    if let makeVoiceoverController {
                        MainTabView(
                            feedUseCase: feedUseCase,
                            deletionUseCase: deletionUseCase,
                            cameraViewModel: makeCreationViewModel(.camera),
                            uploadViewModel: makeCreationViewModel(.upload),
                            voiceoverControllerFactory: makeVoiceoverController,
                            onSignOut: {
                                Task { try? await viewModel.signOut() }
                            },
                            onSettings: {
                                isSettingsPresented = true
                            },
                            makeCreditsViewModel: makeCreditsViewModel
                        )
                    } else {
                        Text("Voiceover playback is available on iOS builds only.")
                            .font(.headline)
                    }
            }
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
            .modifier(RootContentPaddingModifier(flowState: viewModel.flowState))
        }
        .animation(.easeInOut, value: viewModel.flowState)
        .sheet(isPresented: $isSettingsPresented, onDismiss: {
            settingsSheetDetent = .fraction(0.8)
        }) {
            SettingsView(
                userEmail: settingsUser?.email,
                canRequestPasswordReset: settingsUser?.allowsPasswordReset ?? false,
                onResetOnboarding: {
                    await viewModel.resetOnboarding()
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
                    return AnyView(CreditsView(viewModel: viewModel))
                },
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
                onClose: {
                    isSettingsPresented = false
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
        }
        .onChange(of: storedAppearance) { _, _ in
            syncBrandTheme()
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
        case .cancelled:
            return "Sign in cancelled"
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
        case .cancelled:
            return "This sign in was cancelled."
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
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return false }
        let path = url.path.lowercased()
        return path.hasPrefix("/auth/reset")
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
