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
    
    func testPreOnboardingIsDeviceLevelPostOnboardingIsUserSpecific() async {
        let suiteName = "test.onboarding.\(UUID().uuidString)"
        let repository = UserDefaultsOnboardingRepository(suiteName: suiteName)
        
        // User A completes both onboarding stages
        await repository.bind(to: "userA")
        await repository.markPreOnboardingComplete()
        await repository.markPostOnboardingComplete()
        
        var flagsA = await repository.loadFlags()
        XCTAssertTrue(flagsA.hasCompletedPreOnboarding)
        XCTAssertTrue(flagsA.hasCompletedPostOnboarding)
        
        // User B signs in (simulating account deletion + new sign-up)
        await repository.bind(to: "userB")
        var flagsB = await repository.loadFlags()
        
        // Pre-onboarding should still be complete (device-level)
        XCTAssertTrue(flagsB.hasCompletedPreOnboarding, "Pre-onboarding should be device-level and remain complete for new users")
        // Post-onboarding should be false (user-specific)
        XCTAssertFalse(flagsB.hasCompletedPostOnboarding, "Post-onboarding should be user-specific and false for new users")
        
        // User B completes post-onboarding
        await repository.markPostOnboardingComplete()
        flagsB = await repository.loadFlags()
        XCTAssertTrue(flagsB.hasCompletedPostOnboarding)
        
        // Verify User A's post-onboarding is still complete (independent of User B)
        await repository.bind(to: "userA")
        flagsA = await repository.loadFlags()
        XCTAssertTrue(flagsA.hasCompletedPostOnboarding, "User A's post-onboarding should be unaffected by User B")
    }
}
