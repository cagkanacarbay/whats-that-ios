import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct AuthenticationFlowView: View {
    enum Mode: Equatable, Hashable {
        case signIn
        case signUp
        case forgotPassword
        case emailVerificationSent(email: String)
    }

    enum PasswordResetResult {
        case success
        case failure(AuthError)
    }

    public enum SignUpResult {
        case success
        case verificationRequired
    }

    public enum SignInResult {
        case success
        case verificationRequired(email: String)
    }

    let isPerformingAction: Bool
    let onSignIn: (String, String) async throws -> SignInResult
    let onSignUp: (String, String) async throws -> SignUpResult
    let onForgotPassword: (String) async -> PasswordResetResult
    let onGoogle: () async throws -> Void
    let onApple: () async throws -> Void

    @State private var mode: Mode
    @State private var globalError: String?
    @State private var focusedAnchor: String?

    init(
        isPerformingAction: Bool,
        initialMode: Mode = .signUp,
        onSignIn: @escaping (String, String) async throws -> SignInResult,
        onSignUp: @escaping (String, String) async throws -> SignUpResult,
        onForgotPassword: @escaping (String) async -> PasswordResetResult,
        onGoogle: @escaping () async throws -> Void,
        onApple: @escaping () async throws -> Void
    ) {
        self.isPerformingAction = isPerformingAction
        self.onSignIn = onSignIn
        self.onSignUp = onSignUp
        self.onForgotPassword = onForgotPassword
        self.onGoogle = onGoogle
        self.onApple = onApple
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        GeometryReader { geo in
            // Guard against NaN or invalid values during keyboard animations
            let rawHeight = geo.size.height
            let viewportHeight = rawHeight.isFinite && rawHeight > 0 ? rawHeight : nil
            ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: BrandSpacing.large) {
                        Image("BrandLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 130, height: 130)
                            .id("auth-top")

                    switch mode {
                    case .signIn:
                        LoginForm(
                            isPerformingAction: isPerformingAction,
                            onSubmit: handleSignIn,
                            onForgotPassword: { mode = .forgotPassword },
                            onSwitchToSignUp: { mode = .signUp },
                            onGoogle: handleGoogle,
                            onApple: handleApple,
                            onFieldFocusChanged: { field in
                                // Record focus for accessibility/analytics; scrolling handled globally on keyboard show
                                focusedAnchor = field?.anchorID
                            }
                        )
                    case .signUp:
                        SignUpForm(
                            isPerformingAction: isPerformingAction,
                            onSubmit: handleSignUp,
                            onSwitchToSignIn: { mode = .signIn },
                            onGoogle: handleGoogle,
                            onApple: handleApple,
                            onFieldFocusChanged: { field in
                                focusedAnchor = field?.anchorID
                            }
                        )
                    case .forgotPassword:
                        ForgotPasswordForm(
                            onSubmit: handleForgotPassword,
                            onDismiss: { mode = .signIn },
                            onFieldFocusChanged: { field in
                                focusedAnchor = field?.anchorID
                            }
                        )
                    case .emailVerificationSent(let email):
                        EmailVerificationSentView(
                            email: email,
                            onBackToLogin: { mode = .signIn }
                        )
                    }

                    if let globalError {
                        Text(globalError)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                    }
                    // No manual content height tracking; rely on SwiftUI's
                    // automatic scroll view keyboard adjustments.
                    .padding(.horizontal, BrandSpacing.large)
                    .padding(.bottom, BrandSpacing.large)
                    // Center vertically when content is shorter than viewport.
                    // Only apply minHeight when we have a valid viewport size.
                    .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .center)
                }
            }
            // Keep default scroll behavior and keyboard handling; no custom
            // insets or programmatic scroll.
        }


    private func handleSignIn(email: String, password: String, completion: @escaping (Result<Void, AuthError>) -> Void) {
        Task {
            do {
                let result = try await onSignIn(email, password)
                await MainActor.run {
                    switch result {
                    case .success:
                        completion(.success(()))
                    case .verificationRequired(let email):
                        mode = .emailVerificationSent(email: email)
                        completion(.success(()))
                    }
                }
            } catch let authError as AuthError {
                await MainActor.run { completion(.failure(authError)) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    private func handleSignUp(email: String, password: String, completion: @escaping (Result<Void, AuthError>) -> Void) {
        Task {
            do {
                let result = try await onSignUp(email, password)
                await MainActor.run {
                    switch result {
                    case .success:
                        completion(.success(()))
                    case .verificationRequired:
                        mode = .emailVerificationSent(email: email)
                        completion(.success(()))
                    }
                }
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
        handleSocialAuth(operation: onGoogle, completion: completion)
    }

    private func handleApple(completion: @escaping (Result<Void, AuthError>) -> Void) {
        handleSocialAuth(operation: onApple, completion: completion)
    }

    private func handleSocialAuth(
        operation: @escaping () async throws -> Void,
        completion: @escaping (Result<Void, AuthError>) -> Void
    ) {
        Task {
            do {
                try await operation()
                await MainActor.run { completion(.success(())) }
            } catch let error as AuthError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// Avoid custom content height tracking and keyboard insets; these can fight
// with UIKit's keyboard container and produce unsatisfiable constraint logs.
