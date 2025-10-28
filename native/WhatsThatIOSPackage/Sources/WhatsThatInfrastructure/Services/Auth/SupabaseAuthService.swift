#if USE_REMOTE_DEPS && canImport(Supabase)
import Foundation
import OSLog
import Supabase
import WhatsThatDomain
import WhatsThatShared
#if canImport(UIKit)
import UIKit
#endif
#if USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit)
import GoogleSignIn
#endif
#if USE_REMOTE_DEPS && canImport(AuthenticationServices) && canImport(UIKit)
import AuthenticationServices
#endif

private typealias DomainAuthError = WhatsThatDomain.AuthError
private let supabaseAuthLogger = Logger(subsystem: "WhatsThatIOS", category: "SupabaseAuthService")

public final actor SupabaseAuthService: AuthService {
    private let client: SupabaseClient
#if USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit)
    private var googleSignInService: GoogleSignInServicing?
#endif
#if USE_REMOTE_DEPS && canImport(AuthenticationServices) && canImport(UIKit)
    private var appleSignInService: SignInWithAppleServicing?
#endif

#if USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit) && USE_REMOTE_DEPS && canImport(AuthenticationServices) && canImport(UIKit)
    public init(
        client: SupabaseClient,
        googleSignInService: GoogleSignInServicing?,
        appleSignInService: SignInWithAppleServicing?
    ) {
        self.client = client
        self.googleSignInService = googleSignInService
        self.appleSignInService = appleSignInService
    }
#elseif USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit)
    public init(
        client: SupabaseClient,
        googleSignInService: GoogleSignInServicing?
    ) {
        self.client = client
        self.googleSignInService = googleSignInService
    }
#elseif USE_REMOTE_DEPS && canImport(AuthenticationServices) && canImport(UIKit)
    public init(
        client: SupabaseClient,
        appleSignInService: SignInWithAppleServicing?
    ) {
        self.client = client
        self.appleSignInService = appleSignInService
    }
#else
    public init(client: SupabaseClient) {
        self.client = client
    }
#endif

    // Note: configuration-based factory initializers were removed to satisfy
    // Swift 6 actor initializer rules. Use SupabaseClientFactory to build a client,
    // then call one of the designated `init(client: ...)` variants above.

    public func currentSession() async throws -> AuthSession {
        if let session = client.auth.currentSession {
            return .authenticated(session.makeAuthenticatedUser())
        } else {
            return .signedOut
        }
    }

    public func sessionUpdates() async -> AsyncStream<AuthSession> {
        return AsyncStream { continuation in
            let task = Task {
                for await change in client.auth.authStateChanges {
                    continuation.yield(change.session.map { .authenticated($0.makeAuthenticatedUser()) } ?? .signedOut)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            try await client.auth.signIn(email: normalizedEmail, password: password)
            return try await currentSession()
        } catch {
            throw mapSignInError(error)
        }
    }

    public func signUp(email: String, password: String) async throws -> AuthSession {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            _ = try await client.auth.signUp(
                email: normalizedEmail,
                password: password
            )
            return try await currentSession()
        } catch {
            throw mapSignUpError(error)
        }
    }

    public func signInWithGoogle() async throws -> AuthSession {
        #if USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit)
        guard let googleSignInService else {
            throw DomainAuthError.unknown
        }

        let presentingController = try await Self.findPresentingViewController()
        let account: GoogleSignInAccount

        do {
            account = try await googleSignInService.signIn(presenting: presentingController)
        } catch {
            if let mapped = Self.mapGoogleSignInError(error) {
                throw mapped
            }
            throw DomainAuthError.unknown
        }

        guard let idToken = account.idToken else {
            throw DomainAuthError.unknown
        }

        do {
            let credentials = OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: account.accessToken
            )
            try await client.auth.signInWithIdToken(credentials: credentials)
            return try await currentSession()
        } catch {
            throw mapSignInError(error)
        }
        #else
        throw DomainAuthError.unknown
        #endif
    }

    public func signInWithApple() async throws -> AuthSession {
        #if USE_REMOTE_DEPS && canImport(AuthenticationServices) && canImport(UIKit)
        guard let appleSignInService else {
            supabaseAuthLogger.error("Sign in with Apple unavailable: missing service instance.")
            throw DomainAuthError.unknown
        }

        let account: SignInWithAppleAccount
        do {
            account = try await appleSignInService.signIn()
        } catch {
            if let mapped = Self.mapAppleSignInError(error) {
                throw mapped
            }
            supabaseAuthLogger.error("Sign in with Apple flow failed: \(error, privacy: .public)")
            throw DomainAuthError.unknown
        }

        do {
            let credentials = OpenIDConnectCredentials(
                provider: .apple,
                idToken: account.idToken,
                accessToken: nil,
                nonce: account.nonce
            )
            try await client.auth.signInWithIdToken(credentials: credentials)
            return try await currentSession()
        } catch {
            supabaseAuthLogger.error("Supabase Apple sign-in exchange failed: \(error, privacy: .public)")
            throw mapSignInError(error)
        }
        #else
        throw DomainAuthError.unknown
        #endif
    }

    public func signOut() async throws {
        try await client.auth.signOut()
        #if USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit)
        if let googleSignInService {
            await googleSignInService.clearCredentials()
        }
        #endif
    }

    public func sendPasswordReset(email: String) async throws {
        do {
            try await client.auth.resetPasswordForEmail(email)
        } catch {
            throw DomainAuthError.passwordResetFailed
        }
    }

    private func mapSignInError(_ error: Error) -> DomainAuthError {
        if let authError = error as? Supabase.AuthError,
           case let .api(_, errorCode, _, _) = authError {
            switch errorCode {
            case .invalidCredentials:
                return .invalidCredentials
            case .emailAddressNotAuthorized:
                return .invalidCredentials
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.code == 400 {
            return .invalidCredentials
        }
        return .unknown
    }

    private func mapSignUpError(_ error: Error) -> DomainAuthError {
        if let authError = error as? Supabase.AuthError,
           case let .api(_, errorCode, _, _) = authError {
            switch errorCode {
            case .userAlreadyExists:
                return .emailAlreadyInUse
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.code == 422 {
            return .emailAlreadyInUse
        }
        return .unknown
    }

    #if USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit)
    @MainActor
    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        guard let root else { return nil }
        if let presented = root.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = root as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        return root
    }

    private static func findPresentingViewController() async throws -> UIViewController {
        try await MainActor.run {
            guard
                let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                let controller = topViewController(from: window.rootViewController)
            else {
                throw DomainAuthError.unknown
            }
            return controller
        }
    }

    private static func mapGoogleSignInError(_ error: Error) -> DomainAuthError? {
        let nsError = error as NSError
        if nsError.domain == kGIDSignInErrorDomain,
           nsError.code == -5 {
            return .cancelled
        }
        return nil
    }
    #endif

    #if USE_REMOTE_DEPS && canImport(AuthenticationServices) && canImport(UIKit)
    private static func mapAppleSignInError(_ error: Error) -> DomainAuthError? {
        if let serviceError = error as? SignInWithAppleServiceError {
            switch serviceError {
            case .cancelled:
                return .cancelled
            default:
                return .unknown
            }
        }

        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            return .cancelled
        }

        return nil
    }
    #endif
}

private extension Session {
    func makeAuthenticatedUser() -> AuthenticatedUser {
        AuthenticatedUser(
            id: user.id,
            email: user.email ?? ""
        )
    }
}
#endif
