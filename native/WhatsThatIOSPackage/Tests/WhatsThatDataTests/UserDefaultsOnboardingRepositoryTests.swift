import XCTest
@testable import WhatsThatData
import WhatsThatDomain

final class UserDefaultsOnboardingRepositoryTests: XCTestCase {
    func testFlagsPersistAcrossOperations() async {
        let suiteName = "test.onboarding.\(UUID().uuidString)"
        let repository = UserDefaultsOnboardingRepository(suiteName: suiteName)

        var flags = await repository.loadFlags()
        XCTAssertFalse(flags.hasCompletedPreOnboarding)
        XCTAssertFalse(flags.hasCompletedPostOnboarding)

        await repository.markPreOnboardingComplete()
        flags = await repository.loadFlags()
        XCTAssertTrue(flags.hasCompletedPreOnboarding)
        XCTAssertFalse(flags.hasCompletedPostOnboarding)

        await repository.markPostOnboardingComplete()
        flags = await repository.loadFlags()
        XCTAssertTrue(flags.hasCompletedPreOnboarding)
        XCTAssertTrue(flags.hasCompletedPostOnboarding)

        await repository.reset()
        flags = await repository.loadFlags()
        XCTAssertFalse(flags.hasCompletedPreOnboarding)
        XCTAssertFalse(flags.hasCompletedPostOnboarding)
    }
}
