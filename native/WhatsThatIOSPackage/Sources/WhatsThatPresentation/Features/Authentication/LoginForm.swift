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

    @Environment(\.colorScheme) private var colorScheme
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var showingLoading = false
    @State private var didAttemptSubmit = false
    @State private var hasEditedPassword = false

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
                .onChange(of: password) { _, _ in
                    guard !hasEditedPassword else { return }
                    hasEditedPassword = true
                }
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
                BrandSocialButton(kind: .google, isDisabled: isPerformingAction) {
                    handleSocialAuth(using: onGoogle)
                }
                BrandSocialButton(kind: .apple, isDisabled: isPerformingAction) {
                    handleSocialAuth(using: onApple)
                }
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
        shouldShowPasswordError ? "Password is required" : nil
    }

    private var shouldShowPasswordError: Bool {
        (hasEditedPassword || didAttemptSubmit) && password.isEmpty
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

    private func handleSocialAuth(
        using handler: (@escaping (Result<Void, AuthError>) -> Void) -> Void
    ) {
        showingLoading = true
        handler { result in
            showingLoading = false
            if case .failure(let error) = result {
                errorMessage = error.errorDescription
            }
        }
    }
}

