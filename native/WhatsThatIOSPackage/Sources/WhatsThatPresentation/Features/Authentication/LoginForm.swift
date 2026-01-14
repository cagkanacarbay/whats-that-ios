import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct LoginForm: View {
    let isPerformingAction: Bool
    let onSubmit: (String, String, @escaping (Result<Void, AuthError>) -> Void) -> Void
    let onForgotPassword: () -> Void
    let onSwitchToSignUp: () -> Void
    let onGoogle: (@escaping (Result<Void, AuthError>) -> Void) -> Void
    let onApple: (@escaping (Result<Void, AuthError>) -> Void) -> Void
    let onFieldFocusChanged: (_ field: LoginField?) -> Void

    init(
        isPerformingAction: Bool,
        onSubmit: @escaping (String, String, @escaping (Result<Void, AuthError>) -> Void) -> Void,
        onForgotPassword: @escaping () -> Void,
        onSwitchToSignUp: @escaping () -> Void,
        onGoogle: @escaping (@escaping (Result<Void, AuthError>) -> Void) -> Void,
        onApple: @escaping (@escaping (Result<Void, AuthError>) -> Void) -> Void,
        onFieldFocusChanged: @escaping (_ field: LoginField?) -> Void = { _ in }
    ) {
        self.isPerformingAction = isPerformingAction
        self.onSubmit = onSubmit
        self.onForgotPassword = onForgotPassword
        self.onSwitchToSignUp = onSwitchToSignUp
        self.onGoogle = onGoogle
        self.onApple = onApple
        self.onFieldFocusChanged = onFieldFocusChanged
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showingLoading = false
    @State private var didAttemptSubmit = false
    // Focus handling to show validation only after leaving a field
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool
    @State private var emailDidBlur: Bool = false
    @State private var passwordDidBlur: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.large) {
            VStack(spacing: BrandSpacing.small) {
                Text("Welcome back!")
                    .font(.adaptiveSystem(size: 28, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(titleColor)
            }

            VStack(spacing: BrandSpacing.medium) {
                BrandFloatingField(
                    title: "Email Address",
                    placeholder: "name@email.com",
                    text: $email,
                    fieldType: .email,
                    errorText: errorForEmail,
                    focus: $emailFocused
                )
                .id(LoginField.email.anchorID)
                .onChange(of: emailFocused) { _, newValue in
                    if newValue == false { emailDidBlur = true }
                    if newValue == true { onFieldFocusChanged(.email) }
                }
                BrandFloatingField(
                    title: "Password",
                    placeholder: "••••••••",
                    text: $password,
                    fieldType: .password(showToggle: true),
                    errorText: errorForPassword,
                    focus: $passwordFocused
                )
                .id(LoginField.password.anchorID)
                .onChange(of: passwordFocused) { _, newValue in
                    if newValue == false { passwordDidBlur = true }
                    if newValue == true { onFieldFocusChanged(.password) }
                }
            }

            BrandPrimaryButton(
                title: showingLoading ? "Logging in..." : "Log in",
                isLoading: showingLoading || isPerformingAction
            ) {
                submit()
            }
            .disabled(isPerformingAction || showingLoading || !isFormValid)

            Button("Forgot password?") {
                onForgotPassword()
            }
            .buttonStyle(.plain)
            .font(.adaptiveSystem(size: 15, weight: .semibold))
            .foregroundStyle(primaryColor)
            .frame(maxWidth: .infinity, alignment: .center)

            DividerWithLabel(label: "or")

            VStack(spacing: BrandSpacing.small) {
                BrandSocialButton(kind: .google, isDisabled: isPerformingAction) {
                    handleSocialAuth(using: onGoogle)
                }
                BrandSocialButton(kind: .apple, isDisabled: isPerformingAction) {
                    handleSocialAuth(using: onApple)
                }
            }

            HStack(spacing: 4) {
                Text("Don't have an account?")
                    .font(.adaptiveBody())
                    .foregroundStyle(bodyColor)
                Button("Sign up") {
                    onSwitchToSignUp()
                }
                .buttonStyle(.plain)
                .font(.adaptiveBody().weight(.semibold))
                .foregroundStyle(primaryColor)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: UIDevice.isIPad ? IPadLayout.authContentMaxWidth : .infinity)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var errorForEmail: String? {
        guard shouldShowEmailError else { return nil }
        return EmailValidator.isValid(email) ? nil : "Please enter a valid email address"
    }

    private var errorForPassword: String? {
        shouldShowPasswordError ? "Password is required" : nil
    }

    private var shouldShowPasswordError: Bool {
        ((passwordDidBlur) || didAttemptSubmit) && password.isEmpty
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
        didAttemptSubmit = true

        guard EmailValidator.isValid(email), !password.isEmpty else {
            return
        }

        showingLoading = true
        onSubmit(email.lowercased(), password) { result in
            showingLoading = false
            // Errors are handled by higher-level pop-ups; no inline form error
        }
    }

    private func handleSocialAuth(
        using handler: (@escaping (Result<Void, AuthError>) -> Void) -> Void
    ) {
        showingLoading = true
        handler { result in
            showingLoading = false
            // Errors (including cancellations) are surfaced via pop-ups elsewhere
        }
    }

    private var shouldShowEmailError: Bool {
        ((emailDidBlur) || didAttemptSubmit) && !EmailValidator.isValid(email)
    }

    // No per‑keystroke validation for UX performance. Full validation happens
    // on blur (for error copy) and on submit.

    private var isFormValid: Bool {
        // Avoid heavy validation while typing; allow submit when non-empty.
        !email.isEmpty && !password.isEmpty
    }
}

enum LoginField {
    case email
    case password

    var anchorID: String {
        switch self {
        case .email: return "auth-login-email"
        case .password: return "auth-login-password"
        }
    }
}
