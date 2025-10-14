import XCTest
@testable import WhatsThatDomain

final class AppFlowResolverTests: XCTestCase {
    private let resolver = AppFlowResolver()

    func testResolveReturnsPreOnboardingWhenIntroNotCompleted() {
        let flags = OnboardingFlags(hasCompletedPreOnboarding: false, hasCompletedPostOnboarding: false)
        let result = resolver.resolve(session: .signedOut, flags: flags)
        XCTAssertEqual(result, .preOnboarding)
    }

    func testResolveReturnsAuthenticationWhenPreCompletedButNoSession() {
        let flags = OnboardingFlags(hasCompletedPreOnboarding: true, hasCompletedPostOnboarding: false)
        let result = resolver.resolve(session: .signedOut, flags: flags)
        XCTAssertEqual(result, .authentication)
    }

    func testResolveReturnsPostOnboardingWhenSessionExistsButPostIncomplete() {
        let user = AuthenticatedUser(id: UUID(), email: "test@example.com")
        let flags = OnboardingFlags(hasCompletedPreOnboarding: true, hasCompletedPostOnboarding: false)
        let result = resolver.resolve(session: .authenticated(user), flags: flags)
        XCTAssertEqual(result, .postOnboarding(user))
    }

    func testResolveReturnsMainWhenOnboardingComplete() {
        let user = AuthenticatedUser(id: UUID(), email: "test@example.com")
        let flags = OnboardingFlags(hasCompletedPreOnboarding: true, hasCompletedPostOnboarding: true)
        let result = resolver.resolve(session: .authenticated(user), flags: flags)
        XCTAssertEqual(result, .main(user))
    }
}
