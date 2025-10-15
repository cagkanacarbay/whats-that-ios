import SwiftUI
import WhatsThatDomain
import WhatsThatShared
#if os(iOS)
import CoreLocation
import UIKit
#endif

public struct RootContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: AppRootViewModel
    @State private var authError: AuthError?
    @State private var isSettingsPresented = false
    private let feedUseCase: DiscoveryFeedUseCase
    private let makeCreationViewModel: (DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel

    public init(
        feedUseCase: DiscoveryFeedUseCase,
        authUseCase: AuthUseCase,
        onboardingUseCase: OnboardingUseCase,
        flowResolver: AppFlowResolver = AppFlowResolver(),
        makeCreationViewModel: @escaping (DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel
    ) {
        self.feedUseCase = feedUseCase
        self.makeCreationViewModel = makeCreationViewModel
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
                        }
                    )
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
                    MainTabView(
                        feedUseCase: feedUseCase,
                        cameraViewModel: makeCreationViewModel(.camera),
                        uploadViewModel: makeCreationViewModel(.upload),
                        onSignOut: {
                            Task { try? await viewModel.signOut() }
                        },
                        onSettings: {
                            isSettingsPresented = true
                        }
                    )
            }
        }
            .modifier(RootContentPaddingModifier(flowState: viewModel.flowState))
        }
        .animation(.easeInOut, value: viewModel.flowState)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(
                onResetOnboarding: {
                    await viewModel.resetOnboarding()
                    return .success(())
                },
                onClose: {
                    isSettingsPresented = false
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert(
            authError?.errorDescription ?? "Something went wrong",
            isPresented: Binding(
                get: { authError != nil },
                set: { isPresented in
                    if !isPresented { authError = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }

    private func handleAuthOperation(_ operation: @escaping () async throws -> Void) async throws {
        do {
            try await operation()
        } catch let authError as AuthError {
            await MainActor.run { self.authError = authError }
            throw authError
        } catch {
            await MainActor.run { self.authError = .unknown }
            throw AuthError.unknown
        }
    }
}

private struct RootContentPaddingModifier: ViewModifier {
    let flowState: AppFlowState

    func body(content: Content) -> some View {
        if case .main = flowState {
            content
        } else {
            content
                .padding(.horizontal, BrandSpacing.large)
                .padding(.top, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.xLarge)
        }
    }
}

// MARK: - Pre Onboarding

private struct PreOnboardingCarousel: View {
    struct Slide: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let imageName: String
    }

    private let slides: [Slide] = [
        Slide(
            title: "We give the world a voice.",
            message: "Point your camera and let the world share its stories.",
            imageName: "OnboardingIntro"
        ),
        Slide(
            title: "Stories tailored to you.",
            message: "Answers adapt to your interests and get smarter with every photo.",
            imageName: "OnboardingStories"
        )
    ]

    @State private var index: Int = 0
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Spacer()

            TabView(selection: $index) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { offset, slide in
                    VStack(spacing: BrandSpacing.large) {
                        Image(slide.imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .accessibilityHidden(false)

                        VStack(spacing: BrandSpacing.small) {
                            Text(slide.title)
                                .font(.system(size: 28, weight: .bold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(titleColor)
                            Text(slide.message)
                                .font(.system(size: 17, weight: .medium))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(bodyColor)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                    .tag(offset)
                }
            }
#if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
#endif
            .frame(height: 420)

            PageIndicators(count: slides.count, currentIndex: index)

            if index == slides.count - 1 {
                BrandPrimaryButton(title: "Get Started", action: onContinue)
            } else {
                HStack(spacing: BrandSpacing.medium) {
                    BrandSecondaryButton(title: "Skip") {
                        onContinue()
                    }
                    BrandPrimaryButton(title: "Next") {
                        withAnimation { index += 1 }
                    }
                }
            }
            Spacer()
        }
        .padding(.top, BrandSpacing.large)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }
}

private struct PageIndicators: View {
    let count: Int
    let currentIndex: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { idx in
                Capsule()
                    .fill(idx == currentIndex ? activeColor : inactiveColor)
                    .frame(width: idx == currentIndex ? 24 : 8, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
        }
    }

    private var activeColor: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }

    private var inactiveColor: Color {
        colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
    }
}

// MARK: - Authentication Flow

private struct AuthenticationFlowView: View {
    enum Mode {
        case signIn
        case signUp
        case forgotPassword
    }

    enum PasswordResetResult {
        case success
        case failure(AuthError)
    }

    let isPerformingAction: Bool
    let onSignIn: (String, String) async throws -> Void
    let onSignUp: (String, String) async throws -> Void
    let onForgotPassword: (String) async -> PasswordResetResult
    let onGoogle: () async throws -> Void

    @State private var mode: Mode = .signIn
    @State private var globalError: String?

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 130, height: 130)
                .padding(.top, BrandSpacing.large)

            switch mode {
            case .signIn:
                LoginForm(
                    isPerformingAction: isPerformingAction,
                    onSubmit: handleSignIn,
                    onForgotPassword: { mode = .forgotPassword },
                    onSwitchToSignUp: { mode = .signUp },
                    onGoogle: handleGoogle
                )
            case .signUp:
                SignUpForm(
                    isPerformingAction: isPerformingAction,
                    onSubmit: handleSignUp,
                    onSwitchToSignIn: { mode = .signIn },
                    onGoogle: handleGoogle
                )
            case .forgotPassword:
                ForgotPasswordForm(
                    onSubmit: handleForgotPassword,
                    onDismiss: { mode = .signIn }
                )
            }

            if let globalError {
                Text(globalError)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: 500)
    }

    private func handleSignIn(email: String, password: String, completion: @escaping (Result<Void, AuthError>) -> Void) {
        Task {
            do {
                try await onSignIn(email, password)
                await MainActor.run { completion(.success(())) }
            } catch let error as AuthError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    private func handleSignUp(email: String, password: String, completion: @escaping (Result<Void, AuthError>) -> Void) {
        Task {
            do {
                try await onSignUp(email, password)
                await MainActor.run { completion(.success(())) }
            } catch let error as AuthError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    private func handleForgotPassword(email: String, completion: @escaping (PasswordResetResult) -> Void) {
        Task {
            let result = await onForgotPassword(email)
            await MainActor.run {
                completion(result)
            }
        }
    }

    private func handleGoogle(completion: @escaping (Result<Void, AuthError>) -> Void) {
        Task {
            do {
                try await onGoogle()
                await MainActor.run { completion(.success(())) }
            } catch let error as AuthError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Login Form

private struct LoginForm: View {
    let isPerformingAction: Bool
    let onSubmit: (String, String, @escaping (Result<Void, AuthError>) -> Void) -> Void
    let onForgotPassword: () -> Void
    let onSwitchToSignUp: () -> Void
    let onGoogle: (@escaping (Result<Void, AuthError>) -> Void) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var showingLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.large) {
            VStack(spacing: BrandSpacing.small) {
                Text("Welcome back!")
                    .font(.system(size: 28, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(titleColor)
                Text("Log in to pick up where you left off.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(bodyColor)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            VStack(spacing: BrandSpacing.medium) {
                BrandFloatingField(
                    title: "Email Address",
                    placeholder: "name@email.com",
                    text: $email,
                    fieldType: .plain,
                    errorText: errorForEmail
                )
                BrandFloatingField(
                    title: "Password",
                    placeholder: "••••••••",
                    text: $password,
                    fieldType: .password(showToggle: true),
                    errorText: errorForPassword
                )
            }

            BrandPrimaryButton(
                title: showingLoading ? "Logging in..." : "Log in",
                isLoading: showingLoading || isPerformingAction
            ) {
                submit()
            }
            .disabled(isPerformingAction || showingLoading)

            Button("Forgot password?") {
                onForgotPassword()
            }
            .buttonStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(primaryColor)
            .frame(maxWidth: .infinity, alignment: .center)

            DividerWithLabel(label: "or")

            VStack(spacing: BrandSpacing.small) {
                BrandSocialButton(kind: .google, isDisabled: isPerformingAction) { handleSocialAuth() }
                BrandSocialButton(kind: .apple, isDisabled: true) { }
                    .overlay(
                        Text("Coming soon")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(bodyColor)
                            .padding(.trailing, 12),
                        alignment: .trailing
                    )
            }

            HStack(spacing: 4) {
                Text("Don't have an account?")
                    .foregroundStyle(bodyColor)
                Button("Sign up") {
                    onSwitchToSignUp()
                }
                .buttonStyle(.plain)
                .foregroundStyle(primaryColor)
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var errorForEmail: String? {
        guard !email.isEmpty else { return nil }
        let regex = try? NSRegularExpression(pattern: "[^\\s@]+@[^\\s@]+\\.[^\\s@]+")
        let range = NSRange(location: 0, length: email.utf16.count)
        let isValid = regex?.firstMatch(in: email, options: [], range: range) != nil
        return isValid ? nil : "Please enter a valid email address"
    }

    private var errorForPassword: String? {
        password.isEmpty ? "Password is required" : nil
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var primaryColor: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }

    private func submit() {
        guard errorForEmail == nil, errorForPassword == nil, !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in both fields to continue."
            return
        }

        errorMessage = nil
        showingLoading = true
        onSubmit(email.lowercased(), password) { result in
            showingLoading = false
            switch result {
            case .success:
                errorMessage = nil
            case .failure(let error):
                errorMessage = error.errorDescription
            }
        }
    }

    private func handleSocialAuth() {
        showingLoading = true
        onGoogle { result in
            showingLoading = false
            if case .failure(let error) = result {
                errorMessage = error.errorDescription
            }
        }
    }
}

// MARK: - Sign Up Form

private struct SignUpForm: View {
    let isPerformingAction: Bool
    let onSubmit: (String, String, @escaping (Result<Void, AuthError>) -> Void) -> Void
    let onSwitchToSignIn: () -> Void
    let onGoogle: (@escaping (Result<Void, AuthError>) -> Void) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var agreedToTerms: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.large) {
            Text("Create your account")
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(titleColor)

            VStack(spacing: BrandSpacing.medium) {
                BrandFloatingField(
                    title: "Email Address",
                    placeholder: "name@email.com",
                    text: $email,
                    fieldType: .plain,
                    errorText: emailError
                )
                BrandFloatingField(
                    title: "Password",
                    placeholder: "••••••••",
                    text: $password,
                    fieldType: .password(showToggle: true),
                    errorText: passwordError
                )
                BrandFloatingField(
                    title: "Confirm Password",
                    placeholder: "••••••••",
                    text: $confirmPassword,
                    fieldType: .password(showToggle: true),
                    errorText: confirmPasswordError
                )
                Toggle(isOn: $agreedToTerms) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I agree to the Terms and Conditions and Privacy Policy")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(bodyColor)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: primaryColor))
                if termsError != nil {
                    Text("You must agree before continuing.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.85))
                }
            }

            BrandPrimaryButton(
                title: isLoading || isPerformingAction ? "Signing up..." : "Sign up",
                isLoading: isLoading || isPerformingAction
            ) {
                submit()
            }
            .disabled(isPerformingAction || isLoading)

            DividerWithLabel(label: "or")

            VStack(spacing: BrandSpacing.small) {
                Text("By continuing with Google or Apple, you agree to our Terms and Privacy Policy.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(bodyColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                BrandSocialButton(kind: .google, isDisabled: isPerformingAction) { handleSocialAuth() }
                BrandSocialButton(kind: .apple, isDisabled: true) { }
                    .overlay(
                        Text("Coming soon")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(bodyColor)
                            .padding(.trailing, 12),
                        alignment: .trailing
                    )
            }

            HStack(spacing: 4) {
                Text("Already have an account?")
                    .foregroundStyle(bodyColor)
                Button("Log in") {
                    onSwitchToSignIn()
                }
                .buttonStyle(.plain)
                .foregroundStyle(primaryColor)
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var primaryColor: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }

    private var emailError: String? {
        guard !email.isEmpty else { return nil }
        let regex = try? NSRegularExpression(pattern: "[^\\s@]+@[^\\s@]+\\.[^\\s@]+")
        let range = NSRange(location: 0, length: email.utf16.count)
        let isValid = regex?.firstMatch(in: email, options: [], range: range) != nil
        return isValid ? nil : "Please enter a valid email address"
    }

    private var passwordError: String? {
        guard !password.isEmpty else { return nil }
        return password.count >= 6 ? nil : "Password must be at least 6 characters"
    }

    private var confirmPasswordError: String? {
        guard !confirmPassword.isEmpty else { return nil }
        return confirmPassword == password ? nil : "Passwords do not match"
    }

    private var termsError: String? {
        agreedToTerms ? nil : "You must agree to continue."
    }

    private func submit() {
        guard emailError == nil, passwordError == nil, confirmPasswordError == nil, termsError == nil else {
            errorMessage = "Please resolve the highlighted fields."
            return
        }

        errorMessage = nil
        isLoading = true
        onSubmit(email.lowercased(), password) { result in
            isLoading = false
            switch result {
            case .success:
                errorMessage = nil
            case .failure(let error):
                errorMessage = error.errorDescription
            }
        }
    }

    private func handleSocialAuth() {
        isLoading = true
        onGoogle { result in
            isLoading = false
            if case .failure(let error) = result {
                errorMessage = error.errorDescription
            }
        }
    }
}

// MARK: - Forgot Password Form

private struct ForgotPasswordForm: View {
    let onSubmit: (String, @escaping (AuthenticationFlowView.PasswordResetResult) -> Void) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var email: String = ""
    @State private var isLoading: Bool = false
    @State private var infoMessage: String?
    @State private var error: String?

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            VStack(spacing: BrandSpacing.small) {
                Text(infoMessage == nil ? "Forgot Password" : "Check Your Email")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(titleColor)
                Text(infoMessage == nil ? "Enter your email to receive a password reset link." : infoMessage ?? "")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(bodyColor)
                    .multilineTextAlignment(.center)
            }

            if infoMessage == nil {
                BrandFloatingField(
                    title: "Email Address",
                    placeholder: "name@email.com",
                    text: $email,
                    fieldType: .plain,
                    errorText: emailError
                )
            }

            if infoMessage == nil {
                BrandPrimaryButton(
                    title: isLoading ? "Sending..." : "Send Reset Link",
                    isLoading: isLoading
                ) {
                    guard emailError == nil else { return }
                    isLoading = true
                    onSubmit(email.lowercased()) { result in
                        isLoading = false
                        switch result {
                        case .success:
                            infoMessage = "We've sent password reset instructions to \(email)."
                            error = nil
                        case .failure(let authError):
                            error = authError.errorDescription
                        }
                    }
                }
            }

            Button("Back to Login") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(primaryColor)
            .fontWeight(.semibold)

            if let error {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var emailError: String? {
        guard !email.isEmpty else { return nil }
        let regex = try? NSRegularExpression(pattern: "[^\\s@]+@[^\\s@]+\\.[^\\s@]+")
        let range = NSRange(location: 0, length: email.utf16.count)
        let isValid = regex?.firstMatch(in: email, options: [], range: range) != nil
        return isValid ? nil : "Please enter a valid email address"
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var primaryColor: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }
}

private struct DividerWithLabel: View {
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: BrandSpacing.small) {
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(borderColor)
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)
        }
    }

    private var borderColor: Color {
        colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
    }
}

// MARK: - Post Onboarding

private struct PostOnboardingSummary: View {
    let user: AuthenticatedUser
    let onContinue: () -> Void
    let onSignOut: () -> Void
    @Environment(\.colorScheme) private var colorScheme
#if os(iOS)
    @StateObject private var permissionsCoordinator = OnboardingPermissionsCoordinator()
#endif

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: BrandSpacing.medium) {
                Text("Welcome aboard, \(user.email)!")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(titleColor)
                VStack(alignment: .leading, spacing: BrandSpacing.small) {
                    Label("You’ve got 3 free credits ready to explore.", systemImage: "sparkles")
                    Label("Point your camera or upload a photo to get instant stories.", systemImage: "camera.viewfinder")
                    Label("Enable location later for richer, nearby context.", systemImage: "location")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(bodyColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

#if os(iOS)
            OnboardingPermissionsSection(permissions: permissionsCoordinator)
#endif

            BrandPrimaryButton(title: "Start Exploring", action: onContinue)

            Button("Sign out") {
                onSignOut()
            }
            .buttonStyle(.plain)
            .foregroundStyle(bodyColor)
            .font(.system(size: 14, weight: .semibold))

            Spacer()
        }
        .frame(maxWidth: 520)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }
}

#if os(iOS)
private struct OnboardingPermissionsSection: View {
    @ObservedObject var permissions: OnboardingPermissionsCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            Text("Quick Permissions")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(titleColor)

            VStack(alignment: .leading, spacing: BrandSpacing.small) {
                PermissionRow(
                    title: "Location",
                    description: "Enable richer, nearby context in your discoveries.",
                    status: locationStatusText,
                    actionTitle: locationActionTitle,
                    action: locationAction()
                )

                PermissionRow(
                    title: "Notifications",
                    description: "Get a heads up when new stories are ready.",
                    status: notificationStatusText,
                    actionTitle: notificationActionTitle,
                    action: notificationAction()
                )
            }
            .padding()
            .background(cardBackground)
            .cornerRadius(BrandCornerRadius.medium)
            .overlay {
                RoundedRectangle(cornerRadius: BrandCornerRadius.medium)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var borderColor: Color {
        colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
    }

    private var cardBackground: Color {
        colorScheme == .dark ? BrandColors.Dark.secondaryAction.opacity(0.5) : BrandColors.Light.secondaryAction.opacity(0.6)
    }

    private var locationStatusText: String {
        switch permissions.locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Enabled"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    private var notificationStatusText: String {
        switch permissions.notificationStatus {
        case .authorized, .provisional:
            return "Enabled"
        case .denied:
            return "Denied"
        case .ephemeral:
            return "Temporarily enabled"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    private var locationActionTitle: String? {
        switch permissions.locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return nil
        case .denied:
            return "Open Settings"
        default:
            return "Enable Location"
        }
    }

    private func locationAction() -> (() -> Void)? {
        switch permissions.locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return nil
        case .denied:
            return { openAppSettings() }
        default:
            return { permissions.requestLocationPermission() }
        }
    }

    private var notificationActionTitle: String? {
        switch permissions.notificationStatus {
        case .authorized, .provisional:
            return nil
        default:
            return "Enable Notifications"
        }
    }

    private func notificationAction() -> (() -> Void)? {
        notificationActionTitle == nil ? nil : { permissions.requestNotificationPermission() }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private struct PermissionRow: View {
        let title: String
        let description: String
        let status: String
        let actionTitle: String?
        let action: (() -> Void)?

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(status)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(bodyColor)

                if let actionTitle, let action {
                    BrandSecondaryButton(title: actionTitle, action: action)
                }
            }
        }

        private var bodyColor: Color {
            colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
        }

        private var statusColor: Color {
            colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
        }
    }
}
#endif
