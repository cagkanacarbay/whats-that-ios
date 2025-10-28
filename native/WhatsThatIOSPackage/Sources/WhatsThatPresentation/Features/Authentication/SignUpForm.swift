import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct SignUpForm: View {
    let isPerformingAction: Bool
    let onSubmit: (String, String, @escaping (Result<Void, AuthError>) -> Void) -> Void
    let onSwitchToSignIn: () -> Void
    let onGoogle: (@escaping (Result<Void, AuthError>) -> Void) -> Void
    let onApple: (@escaping (Result<Void, AuthError>) -> Void) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var agreedToTerms: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading: Bool = false
    @State private var didAttemptSubmit: Bool = false

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
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: primaryColor))
                if shouldShowTermsError {
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
                BrandSocialButton(kind: .google, isDisabled: isPerformingAction) {
                    handleSocialAuth(using: onGoogle)
                }
                BrandSocialButton(kind: .apple, isDisabled: isPerformingAction) {
                    handleSocialAuth(using: onApple)
                }
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
        return password.count >= 8 ? nil : "Password must be at least 8 characters"
    }

    private var confirmPasswordError: String? {
        guard !confirmPassword.isEmpty else { return nil }
        return confirmPassword == password ? nil : "Passwords do not match"
    }

    private var shouldShowTermsError: Bool {
        didAttemptSubmit && !agreedToTerms
    }

    private func submit() {
        didAttemptSubmit = true

        guard emailError == nil, passwordError == nil, confirmPasswordError == nil, agreedToTerms else {
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

    private func handleSocialAuth(
        using handler: (@escaping (Result<Void, AuthError>) -> Void) -> Void
    ) {
        isLoading = true
        handler { result in
            isLoading = false
            if case .failure(let error) = result {
                errorMessage = error.errorDescription
            }
        }
    }
}

