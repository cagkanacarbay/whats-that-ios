import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct ForgotPasswordForm: View {
    let onSubmit: (String, @escaping (AuthenticationFlowView.PasswordResetResult) -> Void) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var email: String = ""
    @State private var isLoading: Bool = false
    @State private var infoMessage: String?
    @State private var error: String?
    @State private var didAttemptSubmit = false

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
                    fieldType: .email,
                    errorText: emailError
                )
            }

            if infoMessage == nil {
                BrandPrimaryButton(
                    title: isLoading ? "Sending..." : "Send Reset Link",
                    isLoading: isLoading
                ) {
                    didAttemptSubmit = true
                    guard emailValidationError == nil else { return }
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
        guard shouldShowEmailError else { return nil }
        return emailValidationError
    }

    private var emailValidationError: String? {
        guard !email.isEmpty else { return "Please enter a valid email address" }
        let regex = try? NSRegularExpression(pattern: "[^\\s@]+@[^\\s@]+\\.[^\\s@]+")
        let range = NSRange(location: 0, length: email.utf16.count)
        let isValid = regex?.firstMatch(in: email, options: [], range: range) != nil
        return isValid ? nil : "Please enter a valid email address"
    }

    private var shouldShowEmailError: Bool {
        didAttemptSubmit && emailValidationError != nil
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

