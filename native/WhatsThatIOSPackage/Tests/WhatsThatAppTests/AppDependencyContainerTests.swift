import XCTest
@testable import WhatsThatApp
@testable import WhatsThatDomain

final class AppDependencyContainerTests: XCTestCase {
    func testPreviewContainerProvidesUseCases() async throws {
        let container = AppDependencyContainer.preview()
        XCTAssertNotNil(container.discoveryFeedUseCase)

        let session = try await container.authUseCase.currentSession()
        XCTAssertEqual(session, .signedOut)

        let flags = await container.onboardingUseCase.flags()
        XCTAssertFalse(flags.hasCompletedPreOnboarding)

        let resolved = container.flowResolver.resolve(session: session, flags: flags)
        XCTAssertEqual(resolved, .preOnboarding)
    }
}
