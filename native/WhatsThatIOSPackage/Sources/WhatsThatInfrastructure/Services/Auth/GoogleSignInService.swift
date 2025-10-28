#if USE_REMOTE_DEPS && canImport(GoogleSignIn)
@preconcurrency import GoogleSignIn
import UIKit

public struct GoogleSignInAccount: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let email: String?
    public let name: String?

    public init(
        accessToken: String,
        refreshToken: String?,
        idToken: String?,
        email: String?,
        name: String?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.email = email
        self.name = name
    }
}

public enum GoogleSignInServiceError: LocalizedError {
    case missingClientID
    case missingResult

    public var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Google Client ID is missing from configuration."
        case .missingResult:
            return "Google Sign-In did not return a result."
        }
    }
}

public protocol GoogleSignInServicing: Sendable {
    func signIn(presenting viewController: UIViewController) async throws -> GoogleSignInAccount
    func restorePreviousSignIn() -> GoogleSignInAccount?
    func clearCredentials() async
}

public final class GoogleSignInService: @unchecked Sendable, GoogleSignInServicing {
    private let configuration: GIDConfiguration

    public init(clientID: String) throws {
        guard clientID.isEmpty == false else {
            throw GoogleSignInServiceError.missingClientID
        }
        self.configuration = GIDConfiguration(clientID: clientID)
    }

    @MainActor
    public func signIn(presenting viewController: UIViewController) async throws -> GoogleSignInAccount {
        GIDSignIn.sharedInstance.configuration = configuration
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
        return Self.makeAccount(from: result.user)
    }

    public func restorePreviousSignIn() -> GoogleSignInAccount? {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            return nil
        }
        return Self.makeAccount(from: currentUser)
    }

    @MainActor
    public func clearCredentials() async {
        let signIn = GIDSignIn.sharedInstance
        let hadPrevious = signIn.hasPreviousSignIn()
        if signIn.currentUser != nil {
            signIn.signOut()
        }
        guard hadPrevious else { return }
        try? await signIn.disconnect()
    }

    private static func makeAccount(from user: GIDGoogleUser) -> GoogleSignInAccount {
        GoogleSignInAccount(
            accessToken: user.accessToken.tokenString,
            refreshToken: Optional(user.refreshToken)?.tokenString,
            idToken: user.idToken?.tokenString,
            email: user.profile?.email,
            name: user.profile?.name
        )
    }
}
#endif
