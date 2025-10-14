import Foundation
import WhatsThatDomain

public actor UserDefaultsOnboardingRepository: OnboardingRepository {
    private let userDefaults: UserDefaults
    private let preKey: String
    private let postKey: String

    public init(
        suiteName: String? = nil,
        keyPrefix: String = "com.whatsthat.onboarding"
    ) {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.userDefaults = defaults
        } else {
            self.userDefaults = .standard
        }

        self.preKey = "\(keyPrefix).preCompleted"
        self.postKey = "\(keyPrefix).postCompleted"
    }

    public func loadFlags() async -> OnboardingFlags {
        OnboardingFlags(
            hasCompletedPreOnboarding: userDefaults.bool(forKey: preKey),
            hasCompletedPostOnboarding: userDefaults.bool(forKey: postKey)
        )
    }

    public func markPreOnboardingComplete() async {
        userDefaults.set(true, forKey: preKey)
    }

    public func markPostOnboardingComplete() async {
        userDefaults.set(true, forKey: postKey)
    }

    public func reset() async {
        userDefaults.removeObject(forKey: preKey)
        userDefaults.removeObject(forKey: postKey)
    }
}
