import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct PasswordResetView: View {
    let email: String
    let onSubmit: (String) async -> Result<Void, AuthError>
    let onComplete: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading = false
    @State private var didAttemptSubmit = false
    @State private var errorMessage: String?
    @State private var isComplete = false

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack {
                Spacer(minLength: 0)

                VStack(spacing: BrandSpacing.large) {
                    VStack(spacing: BrandSpacing.small) {
                        Image("BrandLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 110)

                        Text(isComplete ? "Password Updated" : "Reset Password")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(titleColor)

                        Text(messageCopy)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(bodyColor)
                            .multilineTextAlignment(.center)
                    }

                    if !isComplete {
                        VStack(spacing: BrandSpacing.medium) {
                            BrandFloatingField(
                                title: "New Password",
                                placeholder: "At least 8 characters",
                                text: $newPassword,
                                fieldType: .password(showToggle: true),
                                errorText: passwordError
                            )

                            BrandFloatingField(
                                title: "Confirm Password",
                                placeholder: "Re-enter new password",
                                text: $confirmPassword,
                                fieldType: .password(showToggle: true),
                                errorText: confirmPasswordError
                            )
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }

                    if isComplete {
                        BrandPrimaryButton(title: "Back to Sign In") {
                            onComplete()
                        }
                    } else {
                        BrandPrimaryButton(
                            title: isLoading ? "Updating..." : "Update Password",
                            isLoading: isLoading
                        ) {
                            submit()
                        }
                        .disabled(isLoading)

                        Button("Cancel") {
                            onCancel()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(primaryColor)
                        .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, BrandSpacing.large)

                Spacer(minLength: 0)
            }
        }
    }

    private var messageCopy: String {
        if isComplete {
            return "You're all set. Sign in with your new password to get back to exploring."
        } else {
            return "Enter a new password for \(email)."
        }
    }

    private var passwordError: String? {
        guard didAttemptSubmit else { return nil }
        if newPassword.isEmpty {
            return "Please enter a new password."
        }
        if newPassword.count < 8 {
            return "Password must be at least 8 characters."
        }
        return nil
    }

    private var confirmPasswordError: String? {
        guard didAttemptSubmit else { return nil }
        if confirmPassword.isEmpty {
            return "Please confirm your new password."
        }
        if confirmPassword != newPassword {
            return "Passwords do not match."
        }
        return nil
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

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }

    private func submit() {
        didAttemptSubmit = true
        guard passwordError == nil, confirmPasswordError == nil else { return }

        errorMessage = nil
        isLoading = true
        Task {
            let result = await onSubmit(newPassword)
            await MainActor.run {
                isLoading = false
                switch result {
                case .success:
                    isComplete = true
                case .failure(let error):
                    errorMessage = error.errorDescription ?? "We couldn't update your password. Please try again."
                }
            }
        }
    }
}

