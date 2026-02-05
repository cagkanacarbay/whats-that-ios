import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct SignUpForm: View {
    let isPerformingAction: Bool
    let onSubmit: (String, String, @escaping (Result<Void, AuthError>) -> Void) -> Void
    let onSwitchToSignIn: () -> Void
    let onGoogle: (@escaping (Result<Void, AuthError>) -> Void) -> Void
    let onApple: (@escaping (Result<Void, AuthError>) -> Void) -> Void
    let onFieldFocusChanged: (_ field: SignUpField?) -> Void

    init(
        isPerformingAction: Bool,
        onSubmit: @escaping (String, String, @escaping (Result<Void, AuthError>) -> Void) -> Void,
        onSwitchToSignIn: @escaping () -> Void,
        onGoogle: @escaping (@escaping (Result<Void, AuthError>) -> Void) -> Void,
        onApple: @escaping (@escaping (Result<Void, AuthError>) -> Void) -> Void,
        onFieldFocusChanged: @escaping (_ field: SignUpField?) -> Void = { _ in }
    ) {
        self.isPerformingAction = isPerformingAction
        self.onSubmit = onSubmit
        self.onSwitchToSignIn = onSwitchToSignIn
        self.onGoogle = onGoogle
        self.onApple = onApple
        self.onFieldFocusChanged = onFieldFocusChanged
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var agreedToTerms: Bool = false
    @State private var agreedToSocialTerms: Bool = false
    @State private var isLoading: Bool = false
    @State private var didAttemptSubmit: Bool = false
    @State private var didAttemptSocialAuth: Bool = false
    // Focus handling to show validation only after leaving a field
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool
    @FocusState private var confirmPasswordFocused: Bool
    @State private var emailDidBlur: Bool = false
    @State private var passwordDidBlur: Bool = false
    @State private var confirmPasswordDidBlur: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            Text("Your stories start here.")
                .font(.adaptiveSystem(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(titleColor)

            VStack(spacing: BrandSpacing.medium) {
                BrandFloatingField(
                    title: "Email Address",
                    placeholder: "name@email.com",
                    text: $email,
                    fieldType: .email,
                    errorText: emailError,
                    focus: $emailFocused
                )
                .id(SignUpField.email.anchorID)
                .onChange(of: emailFocused) { _, newValue in
                    if newValue == false { emailDidBlur = true }
                    if newValue == true { onFieldFocusChanged(.email) }
                }
                BrandFloatingField(
                    title: "Password",
                    placeholder: "••••••••",
                    text: $password,
                    fieldType: .password(showToggle: true),
                    errorText: passwordError,
                    focus: $passwordFocused
                )
                .id(SignUpField.password.anchorID)
                .onChange(of: passwordFocused) { _, newValue in
                    if newValue == false { passwordDidBlur = true }
                    if newValue == true { onFieldFocusChanged(.password) }
                }
                BrandFloatingField(
                    title: "Confirm Password",
                    placeholder: "••••••••",
                    text: $confirmPassword,
                    fieldType: .password(showToggle: true),
                    errorText: confirmPasswordError,
                    focus: $confirmPasswordFocused
                )
                .id(SignUpField.confirm.anchorID)
                .onChange(of: confirmPasswordFocused) { _, newValue in
                    if newValue == false { confirmPasswordDidBlur = true }
                    if newValue == true { onFieldFocusChanged(.confirm) }
                }
                Toggle(isOn: $agreedToTerms) {
                    Text(termsAgreementAttributedString)
                        .font(.adaptiveSystem(size: 14, weight: .medium))
                        .foregroundStyle(bodyColor)
                        .tint(primaryColor)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(SwitchToggleStyle(tint: primaryColor))
                if shouldShowTermsError {
                    Text("You must agree before continuing.")
                        .font(.adaptiveSystem(size: 12, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .animation(nil, value: shouldShowTermsError)
                }
            }

            // Compact vertical spacing around CTA + social auth (half-size gaps)
            VStack(spacing: BrandSpacing.medium) {
                BrandPrimaryButton(
                    title: isLoading || isPerformingAction ? "Signing up..." : "Sign up",
                    isLoading: isLoading || isPerformingAction
                ) {
                    submit()
                }
                .disabled(isPerformingAction || isLoading || !isFormValid)
                .padding(.top, -BrandSpacing.small)

                DividerWithLabel(label: "or")

                VStack(spacing: BrandSpacing.small) {
                    Toggle(isOn: $agreedToSocialTerms) {
                        Text(socialAuthAgreementAttributedString)
                            .font(.adaptiveSystem(size: 14, weight: .medium))
                            .foregroundStyle(bodyColor)
                            .tint(primaryColor)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: primaryColor))

                    if shouldShowSocialTermsError {
                        Text("You must agree before continuing.")
                            .font(.adaptiveSystem(size: 12, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .animation(nil, value: shouldShowSocialTermsError)
                    }

                    BrandSocialButton(kind: .google, isDisabled: isPerformingAction || !agreedToSocialTerms) {
                        handleSocialAuth(using: onGoogle)
                    }
                    BrandSocialButton(kind: .apple, isDisabled: isPerformingAction || !agreedToSocialTerms) {
                        handleSocialAuth(using: onApple)
                    }
                }
                // Set divider-to-text gap to half of the button-to-divider spacing (medium → half = small)
                .padding(.top, -BrandSpacing.small)

                // Slightly smaller gap to the account switch row
                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .font(.adaptiveBody())
                        .foregroundStyle(bodyColor)
                    Button("Log in") {
                        onSwitchToSignIn()
                    }
                    .buttonStyle(.plain)
                    .font(.adaptiveBody().weight(.semibold))
                    .foregroundStyle(primaryColor)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

        }
        .frame(maxWidth: UIDevice.isIPad ? IPadLayout.authContentMaxWidth : .infinity)
        .frame(maxWidth: .infinity, alignment: .center)
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
        guard shouldShowEmailError else { return nil }
        return EmailValidator.isValid(email) ? nil : "Please enter a valid email address"
    }

    private var passwordError: String? {
        guard shouldShowPasswordError else { return nil }
        let result = PasswordValidator.validate(password)
        if result.missing.contains(.length) {
            return "Password must be at least 8 characters"
        }
        // If length is OK but other requirements missing, show detailed guidance
        return PasswordValidator.missingRequirementsMessage(for: password)
    }

    private var confirmPasswordError: String? {
        guard shouldShowConfirmPasswordError else { return nil }
        return confirmPassword == password ? nil : "Passwords do not match"
    }

    private var shouldShowTermsError: Bool {
        didAttemptSubmit && !agreedToTerms
    }

    private var shouldShowSocialTermsError: Bool {
        didAttemptSocialAuth && !agreedToSocialTerms
    }

    private func submit() {
        didAttemptSubmit = true

        // Perform full validation only on submit; avoid doing it per‑keystroke.
        guard EmailValidator.isValid(email), PasswordValidator.validate(password).isStrong, confirmPassword == password, agreedToTerms else {
            return
        }
        isLoading = true
        onSubmit(email.lowercased(), password) { result in
            isLoading = false
            // Errors handled via pop-ups; no inline form error
        }
    }

    private func handleSocialAuth(
        using handler: (@escaping (Result<Void, AuthError>) -> Void) -> Void
    ) {
        didAttemptSocialAuth = true

        guard agreedToSocialTerms else {
            return
        }

        isLoading = true
        handler { result in
            isLoading = false
            // Errors (including cancellations) are surfaced via pop-ups elsewhere
        }
    }

    private var shouldShowEmailError: Bool {
        ((emailDidBlur) || didAttemptSubmit) && !EmailValidator.isValid(email)
    }

    private var shouldShowPasswordError: Bool {
        // Show error after blur or submit when password isn't strong (covers
        // both shorter-than-8 and weak-but-longer-than-8 cases)
        (passwordDidBlur || didAttemptSubmit) && !PasswordValidator.validate(password).isStrong
    }

    private var shouldShowConfirmPasswordError: Bool {
        ((confirmPasswordDidBlur) || didAttemptSubmit) && confirmPassword != password
    }

    private var isFormValid: Bool {
        // Avoid heavy validation while typing; only require fields to be non‑empty
        // and terms toggled for enabling the button. Full checks happen on submit.
        !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty && agreedToTerms
    }

    // MARK: - Legal Agreement Attributed Strings

    private var termsAgreementAttributedString: AttributedString {
        var result = AttributedString("I agree to the ")
        
        var terms = AttributedString("Terms and Conditions")
        terms.link = AppConfiguration.termsAndConditionsURL
        terms.underlineStyle = .single
        result.append(terms)
        
        result.append(AttributedString(" and "))
        
        var privacy = AttributedString("Privacy Policy")
        privacy.link = AppConfiguration.privacyPolicyURL
        privacy.underlineStyle = .single
        result.append(privacy)
        
        return result
    }

    private var socialAuthAgreementAttributedString: AttributedString {
        var result = AttributedString("I agree to the ")

        var terms = AttributedString("Terms and Conditions")
        terms.link = AppConfiguration.termsAndConditionsURL
        terms.underlineStyle = .single
        result.append(terms)

        result.append(AttributedString(" and "))

        var privacy = AttributedString("Privacy Policy")
        privacy.link = AppConfiguration.privacyPolicyURL
        privacy.underlineStyle = .single
        result.append(privacy)

        return result
    }
}

enum SignUpField {
    case email
    case password
    case confirm

    var anchorID: String {
        switch self {
        case .email: return "auth-signup-email"
        case .password: return "auth-signup-password"
        case .confirm: return "auth-signup-confirm"
        }
    }
}
