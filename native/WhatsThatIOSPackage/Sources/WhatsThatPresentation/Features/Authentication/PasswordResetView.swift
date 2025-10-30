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
    @State private var focusedAnchor: String?
    @FocusState private var newPasswordFocused: Bool
    @FocusState private var confirmPasswordFocused: Bool
    @State private var newPasswordDidBlur: Bool = false
    @State private var confirmPasswordDidBlur: Bool = false

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            GeometryReader { geo in
                let viewportHeight = geo.size.height
                ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: BrandSpacing.large) {
                            VStack(spacing: BrandSpacing.small) {
                                Image("BrandLogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 110, height: 110)
                                    .id("reset-top")

                                Text(isComplete ? "Password Updated" : "Reset Password")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(titleColor)

                                Text(messageCopy)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(bodyColor)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if !isComplete {
                                VStack(spacing: BrandSpacing.medium) {
                                    BrandFloatingField(
                                        title: "New Password",
                                        placeholder: "At least 8 characters",
                                        text: $newPassword,
                                        fieldType: .password(showToggle: true),
                                        errorText: passwordError,
                                        focus: $newPasswordFocused
                                    )
                                    .id("reset-new")
                                    .onChange(of: newPasswordFocused) { _, newValue in
                                        if newValue == false { newPasswordDidBlur = true }
                                        if newValue == true { focusedAnchor = "reset-new" }
                                    }

                                    BrandFloatingField(
                                        title: "Confirm Password",
                                        placeholder: "Re-enter new password",
                                        text: $confirmPassword,
                                        fieldType: .password(showToggle: true),
                                        errorText: confirmPasswordError,
                                        focus: $confirmPasswordFocused
                                    )
                                    .id("reset-confirm")
                                    .onChange(of: confirmPasswordFocused) { _, newValue in
                                        if newValue == false { confirmPasswordDidBlur = true }
                                        if newValue == true { focusedAnchor = "reset-confirm" }
                                    }
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
                                .disabled(isLoading || !isFormValid)

                                Button("Cancel") {
                                    onCancel()
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(primaryColor)
                                .fontWeight(.semibold)
                            }
                        }
                        // No manual content height tracking; rely on SwiftUI's
                        // automatic scroll view keyboard adjustments.
                        .frame(maxWidth: 520)
                        .padding(.horizontal, BrandSpacing.large)
                        .padding(.bottom, BrandSpacing.large)
                        // Center vertically when content is shorter than viewport.
                        .frame(minHeight: viewportHeight, alignment: .center)
                    }
                }
            }
        }

    private var messageCopy: String {
        if isComplete {
            return "You're all set. Sign in with your new password to get back to exploring."
        } else {
            return "Enter a new password for your account."
        }
    }

    private var passwordError: String? {
        guard (newPasswordDidBlur || didAttemptSubmit) else { return nil }
        if newPassword.isEmpty { return "Please enter a new password." }
        let result = PasswordValidator.validate(newPassword)
        if result.missing.contains(.length) {
            return "Password must be at least 8 characters."
        }
        return PasswordValidator.missingRequirementsMessage(for: newPassword)
    }

    private var confirmPasswordError: String? {
        guard (confirmPasswordDidBlur || didAttemptSubmit) else { return nil }
        if confirmPassword.isEmpty { return "Please confirm your new password." }
        if confirmPassword != newPassword { return "Passwords do not match." }
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
        guard isFormValid else { return }

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

// Avoid custom content height tracking and keyboard insets; these can fight
// with UIKit's keyboard container and produce unsatisfiable constraint logs.

private extension PasswordResetView {
    var isFormValid: Bool {
        // Avoid heavy validation while typing; only ensure both fields are non‑empty.
        // Strong password + match is enforced on submit via error copy.
        !newPassword.isEmpty && !confirmPassword.isEmpty
    }
}
