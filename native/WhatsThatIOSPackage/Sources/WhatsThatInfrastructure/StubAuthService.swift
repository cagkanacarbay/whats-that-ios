import Foundation
import WhatsThatDomain

public actor StubAuthService: AuthService {
    private struct StoredCredential {
        var password: String
        var id: UUID
    }

    private var storedCredentials: [String: StoredCredential]
    private var currentUser: AuthenticatedUser?
    private var continuations: [UUID: AsyncStream<AuthSession>.Continuation] = [:]

    public init(
        initialUser: AuthenticatedUser? = nil,
        storedCredentials: [String: (password: String, id: UUID)] = [:]
    ) {
        self.currentUser = initialUser
        self.storedCredentials = storedCredentials.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key.lowercased()] = StoredCredential(password: entry.value.password, id: entry.value.id)
        }
        if let user = initialUser, self.storedCredentials[user.email.lowercased()] == nil {
            self.storedCredentials[user.email.lowercased()] = StoredCredential(password: "password", id: user.id)
        }
    }

    private var currentSession: AuthSession {
        if let user = currentUser {
            return .authenticated(user)
        } else {
            return .signedOut
        }
    }

    public func currentSession() async throws -> AuthSession {
        currentSession
    }

    public func sessionUpdates() async -> AsyncStream<AuthSession> {
        AsyncStream { continuation in
            let token = UUID()
            Task { [weak self] in
                await self?.registerContinuation(id: token, continuation: continuation)
            }
        }
    }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let credentials = storedCredentials[normalizedEmail],
              credentials.password == password
        else {
            throw AuthError.invalidCredentials
        }

        let user = AuthenticatedUser(id: credentials.id, email: normalizedEmail)
        currentUser = user
        let session = AuthSession.authenticated(user)
        notify(session: session)
        return session
    }

    public func signUp(email: String, password: String) async throws -> AuthSession {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if storedCredentials[normalizedEmail] != nil {
            throw AuthError.emailAlreadyInUse
        }

        let userId = UUID()
        storedCredentials[normalizedEmail] = StoredCredential(password: password, id: userId)
        let user = AuthenticatedUser(id: userId, email: normalizedEmail)
        currentUser = user
        let session = AuthSession.authenticated(user)
        notify(session: session)
        return session
    }

    public func signInWithGoogle() async throws -> AuthSession {
        let user = AuthenticatedUser(id: UUID(), email: "google-user@example.com")
        currentUser = user
        let session = AuthSession.authenticated(user)
        notify(session: session)
        return session
    }

    public func signOut() async throws {
        guard currentUser != nil else { return }
        currentUser = nil
        notify(session: .signedOut)
    }

    public func sendPasswordReset(email _: String) async throws {
        // Stub implementation: pretend the request succeeded.
    }

    // MARK: - Continuation Management

    private func registerContinuation(
        id: UUID,
        continuation: AsyncStream<AuthSession>.Continuation
    ) async {
        continuations[id] = continuation
        continuation.yield(currentSession)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id: id) }
        }
    }

    private func removeContinuation(id: UUID) async {
        continuations[id] = nil
    }

    private func notify(session: AuthSession) {
        for continuation in continuations.values {
            continuation.yield(session)
        }
    }
}
