
import Foundation

public enum AuthProvider: Equatable, Sendable {
    case email
    case google
    case apple
    case anonymous
    case unknown

    public init(rawValue: String?) {
        guard let rawValue = rawValue?.lowercased() else {
            self = .unknown
            return
        }

        switch rawValue {
        case "email":
            self = .email
        case "google":
            self = .google
        case "apple":
            self = .apple
        case "anonymous":
            self = .anonymous
        default:
            self = .unknown
        }
    }

    public var rawValue: String {
        switch self {
        case .email:
            return "email"
        case .google:
            return "google"
        case .apple:
            return "apple"
        case .anonymous:
            return "anonymous"
        case .unknown:
            return "unknown"
        }
    }

    public var allowsPasswordReset: Bool {
        self == .email
    }
}

public struct AuthenticatedUser: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let email: String
    public let provider: AuthProvider

    public init(id: UUID, email: String, provider: AuthProvider = .unknown) {
        self.id = id
        self.email = email
        self.provider = provider
    }

    public var allowsPasswordReset: Bool {
        provider.allowsPasswordReset
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
    case passwordResetRateLimited
    case passwordResetLinkInvalid
    case passwordResetLinkExpired
    case passwordUpdateFailed
    case passwordSame
    case cancelled
    case accountDeletionFailed
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
        case .passwordResetRateLimited:
            return "For security reasons, you've made too many reset requests. Please wait a few minutes before trying again."
        case .passwordResetLinkInvalid:
            return "That reset link isn't valid anymore. Please request a fresh one."
        case .passwordResetLinkExpired:
            return "Your reset link has expired. Request a new one to continue."
        case .passwordUpdateFailed:
            return "We couldn't update your password. Please try again."
        case .passwordSame:
            return "Your new password matches the current one. Please choose a different password."
        case .cancelled:
            return "The sign-in flow was cancelled."
        case .accountDeletionFailed:
            return "We couldn't delete your account. Please try again or contact support."
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
    func bootstrapPasswordResetSession(from url: URL) async throws -> AuthenticatedUser
    func updatePassword(to newPassword: String) async throws
    func deleteAccount() async throws
}
