#if USE_REMOTE_DEPS && canImport(AuthenticationServices) && canImport(UIKit)
import AuthenticationServices
import CryptoKit
import Foundation
import OSLog
import Security
import UIKit

public struct SignInWithAppleAccount: Sendable {
    public let userIdentifier: String
    public let email: String?
    public let idToken: String
    public let nonce: String

    public init(
        userIdentifier: String,
        email: String?,
        idToken: String,
        nonce: String
    ) {
        self.userIdentifier = userIdentifier
        self.email = email
        self.idToken = idToken
        self.nonce = nonce
    }
}

public enum SignInWithAppleServiceError: LocalizedError {
    case missingPresentationAnchor
    case missingIdentityToken
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingPresentationAnchor:
            return "Unable to present Sign in with Apple flow."
        case .missingIdentityToken:
            return "Apple authorization did not include an identity token."
        case .cancelled:
            return "The sign-in flow was cancelled."
        }
    }
}

public protocol SignInWithAppleServicing: Sendable {
    func signIn() async throws -> SignInWithAppleAccount
}

@MainActor
public final class SignInWithAppleService: NSObject, @unchecked Sendable, SignInWithAppleServicing {
    private let logger = Logger(subsystem: "WhatsThatIOS", category: "SignInWithApple")
    private var continuation: CheckedContinuation<SignInWithAppleAccount, Error>?
    private var pendingNonce: String?

    public override init() {
        super.init()
    }

    public func signIn() async throws -> SignInWithAppleAccount {
        let nonce = Self.randomNonce()
        let hashedNonce = Self.sha256(nonce)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.pendingNonce = nonce

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

@MainActor
extension SignInWithAppleService: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8),
            let nonce = pendingNonce
        else {
            logger.error("Sign in with Apple missing identity token or nonce.")
            resume(with: .failure(SignInWithAppleServiceError.missingIdentityToken))
            return
        }

        let account = SignInWithAppleAccount(
            userIdentifier: credential.user,
            email: credential.email,
            idToken: token,
            nonce: nonce
        )
        resume(with: .success(account))
    }

    public func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        logger.error("Sign in with Apple failed: \(error, privacy: .public)")
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            resume(with: .failure(SignInWithAppleServiceError.cancelled))
        } else {
            resume(with: .failure(error))
        }
    }
}

@MainActor
extension SignInWithAppleService: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            .flatMap({ scene -> UIWindow? in
                if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                    return keyWindow
                }
                if let firstWindow = scene.windows.first {
                    return firstWindow
                }
                return nil
            })
        else {
            if let fallback = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first {
                return fallback
            }

            logger.error("Unable to find presentation anchor for Sign in with Apple.")
            resume(with: .failure(SignInWithAppleServiceError.missingPresentationAnchor))
            return UIWindow()
        }

        return window
    }
}

@MainActor
private extension SignInWithAppleService {
    func resume(with result: Result<SignInWithAppleAccount, Error>) {
        pendingNonce = nil
        guard let continuation else { return }
        self.continuation = nil

        switch result {
        case .success(let account):
            continuation.resume(returning: account)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate secure random bytes. SecRandomCopyBytes failed with code \(errorCode).")
            }

            randomBytes.forEach { value in
                guard remainingLength > 0 else { return }
                let index = Int(value)
                if index < charset.count {
                    result.append(charset[index])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
#endif
