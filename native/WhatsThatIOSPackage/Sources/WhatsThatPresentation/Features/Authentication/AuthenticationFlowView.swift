import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct AuthenticationFlowView: View {
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
    let onApple: () async throws -> Void

    @State private var mode: Mode
    @State private var globalError: String?

    init(
        isPerformingAction: Bool,
        initialMode: Mode = .signUp,
        onSignIn: @escaping (String, String) async throws -> Void,
        onSignUp: @escaping (String, String) async throws -> Void,
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
                    onGoogle: handleGoogle,
                    onApple: handleApple
                )
            case .signUp:
                SignUpForm(
                    isPerformingAction: isPerformingAction,
                    onSubmit: handleSignUp,
                    onSwitchToSignIn: { mode = .signIn },
                    onGoogle: handleGoogle,
                    onApple: handleApple
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

