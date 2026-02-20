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
    private let configuration: AppConfiguration
#if USE_REMOTE_DEPS && canImport(Security)
    private let deviceIdentifierService: DeviceIdentifierServicing
#endif
#if USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit)
    private var googleSignInService: GoogleSignInServicing?
#endif
#if USE_REMOTE_DEPS && canImport(AuthenticationServices) && canImport(UIKit)
    private var appleSignInService: SignInWithAppleServicing?
#endif

#if USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit) && USE_REMOTE_DEPS && canImport(AuthenticationServices) && canImport(UIKit)
    public init(
        client: SupabaseClient,
        configuration: AppConfiguration,
        deviceIdentifierService: DeviceIdentifierServicing,
        googleSignInService: GoogleSignInServicing?,
        appleSignInService: SignInWithAppleServicing?
    ) {
        self.client = client
        self.configuration = configuration
        self.deviceIdentifierService = deviceIdentifierService
        self.googleSignInService = googleSignInService
        self.appleSignInService = appleSignInService
    }
#elseif USE_REMOTE_DEPS && canImport(GoogleSignIn) && canImport(UIKit)
    public init(
        client: SupabaseClient,
        configuration: AppConfiguration,
        deviceIdentifierService: DeviceIdentifierServicing,
        googleSignInService: GoogleSignInServicing?
    ) {
        self.client = client
        self.configuration = configuration
        self.deviceIdentifierService = deviceIdentifierService
        self.googleSignInService = googleSignInService
    }
#elseif USE_REMOTE_DEPS && canImport(AuthenticationServices) && canImport(UIKit)
    public init(
        client: SupabaseClient,
        configuration: AppConfiguration,
        deviceIdentifierService: DeviceIdentifierServicing,
        appleSignInService: SignInWithAppleServicing?
    ) {
        self.client = client
        self.configuration = configuration
        self.deviceIdentifierService = deviceIdentifierService
        self.appleSignInService = appleSignInService
    }
#else
    public init(
        client: SupabaseClient,
        configuration: AppConfiguration,
        deviceIdentifierService: DeviceIdentifierServicing
    ) {
        self.client = client
        self.configuration = configuration
        self.deviceIdentifierService = deviceIdentifierService
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
                    supabaseAuthLogger.debug("Auth state change: event=\(String(describing: change.event)), hasSession=\(change.session != nil)")
                    continuation.yield(change.session.map { .authenticated($0.makeAuthenticatedUser()) } ?? .signedOut)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func signIn(email: String, password: String) async throws -> SignInResult {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            try await client.auth.signIn(email: normalizedEmail, password: password)
            return .authenticated(try await currentSession())
        } catch {
            // Check for email not confirmed error - this is a valid outcome, not an error
            if let authError = error as? Supabase.AuthError,
               case let .api(_, errorCode, _, _) = authError,
               errorCode == .emailNotConfirmed {
                supabaseAuthLogger.info("Sign in requires email verification for \(normalizedEmail)")
                return .verificationRequired
            }
            throw mapSignInError(error)
        }
    }

    public func signUp(email: String, password: String) async throws -> SignUpResult {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Get device ID for free credit abuse prevention
        let deviceId = deviceIdentifierService.getOrCreateDeviceId()
        
        do {
            let response = try await client.auth.signUp(
                email: normalizedEmail,
                password: password,
                data: ["device_id": .string(deviceId)]
            )
            
            // Check if email confirmation is required (no session returned)
            // This happens when Supabase has "Confirm email" enabled
            if response.session == nil {
                supabaseAuthLogger.info("Signup successful but email confirmation required for \(normalizedEmail)")
                return .verificationRequired
            }
            
            return .authenticated(try await currentSession())
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
            
            // Record device ID for credit tracking (OAuth flows don't pass metadata through trigger)
            await recordDeviceIdForCreditTracking()
            
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
            
            // Record device ID for credit tracking (OAuth flows don't pass metadata through trigger)
            await recordDeviceIdForCreditTracking()
            
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

    public func bootstrapPasswordResetSession(from url: URL) async throws -> AuthenticatedUser {
        var parameters = parseSupabaseParameters(from: url)
        let accessToken = parameters["access_token"]
        let refreshToken = parameters["refresh_token"]
        let recoveryCode = parameters["code"] ?? parameters["token"]
        var normalizedType = parameters["type"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let hasRecoveryTokens = (accessToken?.isEmpty == false && refreshToken?.isEmpty == false)
        let impliesRecovery = normalizedType == nil && (hasRecoveryTokens || recoveryCode?.isEmpty == false)

        if normalizedType != "recovery", normalizedType != nil, !impliesRecovery {
            supabaseAuthLogger.error("Password reset link missing recovery type.")
            throw DomainAuthError.passwordResetLinkInvalid
        }

        if normalizedType == nil, impliesRecovery {
            normalizedType = "recovery"
            parameters["type"] = "recovery"
        }

        if
            let accessToken = parameters["access_token"],
            let refreshToken = parameters["refresh_token"],
            accessToken.isEmpty == false,
            refreshToken.isEmpty == false,
            normalizedType == "recovery"
        {
            do {
                let session = try await client.auth.setSession(
                    accessToken: accessToken,
                    refreshToken: refreshToken
                )
                supabaseAuthLogger.notice("Password reset session established for \(session.user.email ?? "<unknown>")")
                return session.makeAuthenticatedUser()
            } catch {
                let mapped = mapPasswordResetBootstrapError(error)
                supabaseAuthLogger.error("Failed to establish password reset session: \(error, privacy: .public)")
                throw mapped
            }
        }

        if
            let code = parameters["code"] ?? parameters["token"],
            code.isEmpty == false,
            normalizedType == "recovery"
        {
            do {
                let session = try await client.auth.exchangeCodeForSession(authCode: code)
                supabaseAuthLogger.notice("Password reset session established via auth code for \(session.user.email ?? "<unknown>")")
                return session.makeAuthenticatedUser()
            } catch {
                let mapped = mapPasswordResetBootstrapError(error)
                supabaseAuthLogger.error("Password reset auth code exchange failed: \(error, privacy: .public)")
                throw mapped
            }
        }

        supabaseAuthLogger.error("Password reset link missing required tokens.")
        throw DomainAuthError.passwordResetLinkInvalid
    }

    public func updatePassword(to newPassword: String) async throws {
        do {
            _ = try await client.auth.update(user: UserAttributes(password: newPassword))
        } catch {
            let mapped = mapPasswordUpdateError(error)
            supabaseAuthLogger.error("Password update failed: \(error, privacy: .public)")
            throw mapped
        }
    }

    public func sendPasswordReset(email: String) async throws {
        do {
            try await client.auth.resetPasswordForEmail(
                email,
                redirectTo: configuration.passwordResetRedirectURL
            )
        } catch let authError as Supabase.AuthError {
            if case let .api(_, errorCode, _, response) = authError {
                if errorCode == .overEmailSendRateLimit ||
                    errorCode == .overRequestRateLimit ||
                    response.statusCode == 429 {
                    throw DomainAuthError.passwordResetRateLimited
                }
            }
            supabaseAuthLogger.error("Supabase password reset request failed: \(authError, privacy: .public)")
            throw DomainAuthError.passwordResetFailed
        } catch {
            supabaseAuthLogger.error("Password reset request failed: \(error, privacy: .public)")
            throw DomainAuthError.passwordResetFailed
        }
    }

    public func deleteAccount() async throws {
        guard let supabaseURL = configuration.supabaseURL else {
            supabaseAuthLogger.error("Account deletion failed: missing Supabase URL")
            throw DomainAuthError.accountDeletionFailed
        }

        guard let accessToken = client.auth.currentSession?.accessToken else {
            supabaseAuthLogger.error("Account deletion failed: no active session")
            throw DomainAuthError.accountDeletionFailed
        }

        let functionsURL = SupabaseDiscoveryAnalysisClient
            .functionsBaseURL(from: supabaseURL)
            .appendingPathComponent("delete-account")

        var request = URLRequest(url: functionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                supabaseAuthLogger.error("Account deletion failed: invalid response type")
                throw DomainAuthError.accountDeletionFailed
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                supabaseAuthLogger.error("Account deletion failed: status=\(httpResponse.statusCode) body=\(body, privacy: .public)")
                throw DomainAuthError.accountDeletionFailed
            }

            supabaseAuthLogger.info("Account deletion completed successfully")

            // Sign out locally after the account has been deleted on the server
            try? await signOut()
        } catch let error as DomainAuthError {
            throw error
        } catch {
            supabaseAuthLogger.error("Account deletion failed: \(error.localizedDescription, privacy: .public)")
            throw DomainAuthError.accountDeletionFailed
        }
    }

    public func verifyEmailFromLink(url: URL) async throws {
        // Progressive retry with increasing delays: immediate → 1s → 2s → 4s → 8s.
        // The token_hash is not consumed on failure, so retrying is safe and idempotent.
        // This handles transient failures (e.g. network hiccups, client not fully ready after backgrounding).
        let retryDelaysNanoseconds: [UInt64] = [
            1_000_000_000,  // 1s
            2_000_000_000,  // 2s
            4_000_000_000,  // 4s
            8_000_000_000,  // 8s
        ]

        // Attempt 1: immediate
        do {
            try await performEmailVerification(from: url)
            return
        } catch {
            supabaseAuthLogger.info("Email verification attempt 1 failed: \(error.localizedDescription, privacy: .public)")
        }

        // Attempts 2–5: progressive delays
        for (index, delay) in retryDelaysNanoseconds.enumerated() {
            let attemptNumber = index + 2
            supabaseAuthLogger.info("Email verification retrying (attempt \(attemptNumber)) after \(delay / 1_000_000_000)s delay...")
            try await Task.sleep(nanoseconds: delay)
            do {
                try await performEmailVerification(from: url)
                supabaseAuthLogger.info("Email verification succeeded on attempt \(attemptNumber)")
                return
            } catch {
                supabaseAuthLogger.info("Email verification attempt \(attemptNumber) failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        supabaseAuthLogger.error("Email verification failed after all retry attempts")
        throw DomainAuthError.emailVerificationFailed
    }

    private func performEmailVerification(from url: URL) async throws {
        let params = parseSupabaseParameters(from: url)

        // Handle token_hash verification (most common for email confirmation)
        if let tokenHash = params["token_hash"],
           !tokenHash.isEmpty,
           let type = params["type"]?.lowercased() {
            do {
                // Map string type to EmailOTPType
                let emailType: EmailOTPType
                switch type {
                case "signup":
                    emailType = .signup
                case "email":
                    emailType = .email
                case "email_change":
                    emailType = .emailChange
                default:
                    emailType = .signup
                }
                _ = try await client.auth.verifyOTP(tokenHash: tokenHash, type: emailType)
                supabaseAuthLogger.info("Email verification successful via token_hash")
                return
            } catch {
                supabaseAuthLogger.error("Email verification failed: \(error.localizedDescription, privacy: .public)")
                throw DomainAuthError.emailVerificationFailed
            }
        }

        // Handle PKCE code exchange
        if let code = params["code"], !code.isEmpty {
            do {
                _ = try await client.auth.exchangeCodeForSession(authCode: code)
                supabaseAuthLogger.info("Email verification successful via code exchange")
                return
            } catch {
                supabaseAuthLogger.error("Email verification code exchange failed: \(error.localizedDescription, privacy: .public)")
                throw DomainAuthError.emailVerificationFailed
            }
        }

        // Handle access_token + refresh_token (alternative format)
        if let accessToken = params["access_token"],
           let refreshToken = params["refresh_token"],
           !accessToken.isEmpty,
           !refreshToken.isEmpty {
            do {
                _ = try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
                supabaseAuthLogger.info("Email verification successful via session tokens")
                return
            } catch {
                supabaseAuthLogger.error("Email verification session setup failed: \(error.localizedDescription, privacy: .public)")
                throw DomainAuthError.emailVerificationFailed
            }
        }

        supabaseAuthLogger.error("Email verification link missing required tokens")
        throw DomainAuthError.emailVerificationFailed
    }

    private func mapSignInError(_ error: Error) -> DomainAuthError {
        if let authError = error as? Supabase.AuthError,
           case let .api(description, errorCode, _, _) = authError {
            supabaseAuthLogger.error("Sign in API error: \(String(describing: errorCode), privacy: .public) - \(description, privacy: .public)")
            switch errorCode {
            case .invalidCredentials:
                return .invalidCredentials
            case .emailAddressNotAuthorized:
                return .invalidCredentials
            case .overEmailSendRateLimit:
                return .rateLimitExceeded
            default:
                return .internalError(description)
            }
        }

        let nsError = error as NSError
        if nsError.code == 400 {
            return .invalidCredentials
        }
        if nsError.code == 429 {
            return .rateLimitExceeded
        }
        
        supabaseAuthLogger.error("Sign in unknown error: \(error.localizedDescription, privacy: .public)")
        return .unknown
    }

    private func mapSignUpError(_ error: Error) -> DomainAuthError {
        if let authError = error as? Supabase.AuthError {
            switch authError {
            case let .weakPassword(_, reasons):
                supabaseAuthLogger.error("Sign up password rejected as weak: \(reasons, privacy: .public)")
                return .passwordTooWeak
            case let .api(description, errorCode, _, _):
                supabaseAuthLogger.error("Sign up API error: \(String(describing: errorCode), privacy: .public) - \(description, privacy: .public)")
                switch errorCode {
                case .userAlreadyExists:
                    return .emailAlreadyInUse
                case .overEmailSendRateLimit:
                    return .rateLimitExceeded
                case .weakPassword:
                    return .passwordTooWeak
                default:
                    return .internalError(description)
                }
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.code == 422 {
            return .emailAlreadyInUse
        }
        if nsError.code == 429 {
            return .rateLimitExceeded
        }
        
        supabaseAuthLogger.error("Sign up unknown error: \(error.localizedDescription, privacy: .public)")
        return .unknown
    }


    private func parseSupabaseParameters(from url: URL) -> [String: String] {
        var parameters = Self.extractParameters(from: url)

        if let nestedValue = parameters["supabase_url"] {
            let decoded = nestedValue.removingPercentEncoding ?? nestedValue
            if let nestedURL = URL(string: decoded) {
                parameters.merge(Self.extractParameters(from: nestedURL)) { current, new in
                    new.isEmpty ? current : new
                }
            }
        }

        return parameters
    }

    private static func extractParameters(from url: URL) -> [String: String] {
        var parameters: [String: String] = [:]

        if let fragment = url.fragment, fragment.isEmpty == false {
            parameters.merge(parseQuery(fragment)) { $1 }
        }

        if let query = url.query, query.isEmpty == false {
            parameters.merge(parseQuery(query)) { $1 }
        }

        return parameters
    }

    private static func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for component in query.split(separator: "&") {
            let elements = component.split(separator: "=", maxSplits: 1).map(String.init)
            guard elements.count == 2 else { continue }
            let key = elements[0].removingPercentEncoding ?? elements[0]
            let value = elements[1].removingPercentEncoding ?? elements[1]
            result[key] = value
        }
        return result
    }

    private func mapPasswordResetBootstrapError(_ error: Error) -> DomainAuthError {
        if let authError = error as? Supabase.AuthError {
            switch authError {
            case .sessionMissing:
                return .passwordResetLinkExpired
            case let .api(_, errorCode, _, _):
                if errorCode == .otpExpired || errorCode == .invalidJWT {
                    return .passwordResetLinkExpired
                }
            default:
                break
            }
        }
        return .passwordResetLinkInvalid
    }

    private func mapPasswordUpdateError(_ error: Error) -> DomainAuthError {
        if let authError = error as? Supabase.AuthError {
            switch authError {
            case .sessionMissing:
                return .passwordResetLinkExpired
            case let .weakPassword(_, reasons):
                supabaseAuthLogger.error("Password rejected as weak: \(reasons, privacy: .public)")
                return .passwordTooWeak
            case let .api(_, errorCode, _, _):
                if errorCode == .weakPassword {
                    return .passwordTooWeak
                } else if errorCode == .reauthenticationNeeded || errorCode == .sessionNotFound {
                    return .passwordResetLinkExpired
                } else if errorCode == .samePassword {
                    return .passwordSame
                }
            default:
                break
            }
        }
        return .passwordUpdateFailed
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
    
    // MARK: - Device ID Tracking
    
    /// Records the device ID for credit tracking via RPC.
    /// This is needed for OAuth flows where we can't pass user metadata through the signup trigger.
    private func recordDeviceIdForCreditTracking() async {
        #if USE_REMOTE_DEPS && canImport(Security)
        let deviceId = deviceIdentifierService.getOrCreateDeviceId()
        
        do {
            try await client.rpc("record_device_for_credit_tracking", params: ["p_device_id": deviceId]).execute()
            supabaseAuthLogger.debug("Recorded device ID for credit tracking")
        } catch {
            // Non-fatal: log but don't fail the sign-in
            supabaseAuthLogger.error("Failed to record device ID for credit tracking: \(error.localizedDescription)")
        }
        #endif
    }
}

private extension Session {
    func makeAuthenticatedUser() -> AuthenticatedUser {
        AuthenticatedUser(
            id: user.id,
            email: user.email ?? "",
            provider: AuthProvider(rawValue: user.appMetadata["provider"]?.stringValue)
        )
    }
}
#endif
