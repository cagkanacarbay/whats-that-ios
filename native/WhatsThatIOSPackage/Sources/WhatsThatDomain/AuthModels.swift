import Foundation

public struct AuthenticatedUser: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let email: String

    public init(id: UUID, email: String) {
        self.id = id
        self.email = email
    }
}

public enum AuthSession: Equatable, Sendable {
    case signedOut
    case authenticated(AuthenticatedUser)

    public var user: AuthenticatedUser? {
        if case let .authenticated(user) = self {
            return user
        }
        return nil
    }

    public var isAuthenticated: Bool {
        user != nil
    }
}

public enum AuthError: LocalizedError, Equatable, Sendable {
    case invalidCredentials
    case emailAlreadyInUse
    case passwordTooWeak
    case passwordResetFailed
    case cancelled
    case unknown

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "We couldn't sign you in with those details. Double-check your email and password."
        case .emailAlreadyInUse:
            return "An account with this email already exists. Try signing in instead."
        case .passwordTooWeak:
            return "Try a stronger password with at least 8 characters."
        case .passwordResetFailed:
            return "We couldn't send the reset instructions. Please try again in a few minutes."
        case .cancelled:
            return "The sign-in flow was cancelled."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}

public protocol AuthService: Sendable {
    func currentSession() async throws -> AuthSession
    func sessionUpdates() async -> AsyncStream<AuthSession>
    func signIn(email: String, password: String) async throws -> AuthSession
    func signUp(email: String, password: String) async throws -> AuthSession
    func signInWithGoogle() async throws -> AuthSession
    func signInWithApple() async throws -> AuthSession
    func signOut() async throws
    func sendPasswordReset(email: String) async throws
}
