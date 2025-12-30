import Foundation

public actor AuthUseCase: Sendable {
    private let service: AuthService

    public init(service: AuthService) {
        self.service = service
    }

    public func currentSession() async throws -> AuthSession {
        try await service.currentSession()
    }

    public func observeSession() async -> AsyncStream<AuthSession> {
        await service.sessionUpdates()
    }

    @discardableResult
    public func signIn(email: String, password: String) async throws -> SignInResult {
        try await service.signIn(email: email, password: password)
    }

    @discardableResult
    public func signUp(email: String, password: String) async throws -> SignUpResult {
        try await service.signUp(email: email, password: password)
    }

    @discardableResult
    public func signInWithGoogle() async throws -> AuthSession {
        try await service.signInWithGoogle()
    }

    @discardableResult
    public func signInWithApple() async throws -> AuthSession {
        try await service.signInWithApple()
    }

    public func signOut() async throws {
        try await service.signOut()
    }

    public func sendPasswordReset(email: String) async throws {
        try await service.sendPasswordReset(email: email)
    }

    @discardableResult
    public func bootstrapPasswordResetSession(from url: URL) async throws -> AuthenticatedUser {
        try await service.bootstrapPasswordResetSession(from: url)
    }

    public func updatePassword(to newPassword: String) async throws {
        try await service.updatePassword(to: newPassword)
    }

    public func deleteAccount() async throws {
        try await service.deleteAccount()
    }

    public func verifyEmailFromLink(url: URL) async throws {
        try await service.verifyEmailFromLink(url: url)
    }
}

