import XCTest
@testable import WhatsThatDomain
@testable import WhatsThatInfrastructure

final class StubAuthServiceTests: XCTestCase {
    func testSignUpCreatesAuthenticatedSession() async throws {
        let service = StubAuthService()
        let session = try await service.signUp(email: "new@example.com", password: "strongpassword")
        guard case let .authenticated(user) = session else {
            return XCTFail("Expected authenticated session")
        }
        XCTAssertEqual(user.email, "new@example.com")

        let current = try await service.currentSession()
        XCTAssertEqual(current, session)
    }

    func testSignInValidatesExistingCredentials() async {
        let userID = UUID()
        let service = StubAuthService(
            storedCredentials: [
                "user@example.com": (password: "secret123", id: userID)
            ]
        )

        do {
            _ = try await service.signIn(email: "user@example.com", password: "wrong")
            XCTFail("Expected invalid credentials error")
        } catch let error as AuthError {
            XCTAssertEqual(error, .invalidCredentials)
        } catch {
            XCTFail("Expected AuthError, got \(error)")
        }
    }

    func testSessionUpdatesEmitChanges() async throws {
        let service = StubAuthService()
        let stream = await service.sessionUpdates()
        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        XCTAssertEqual(initial, .some(.signedOut))

        _ = try await service.signUp(email: "listener@example.com", password: "password123")
        let afterSignIn = await iterator.next()
        guard case let .authenticated(user)? = afterSignIn else {
            return XCTFail("Expected authenticated session after sign in")
        }
        XCTAssertEqual(user.email, "listener@example.com")

        try await service.signOut()
        let afterSignOut = await iterator.next()
        XCTAssertEqual(afterSignOut, .some(.signedOut))
    }
}
