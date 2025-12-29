import Foundation
import WhatsThatDomain

public actor UserDefaultsOnboardingRepository: OnboardingRepository {
    private let userDefaults: UserDefaults
    private let keyPrefix: String
    private var currentUserId: String?

    public init(
        suiteName: String? = nil,
        keyPrefix: String = "com.whatsthat.onboarding"
    ) {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.userDefaults = defaults
        } else {
            self.userDefaults = .standard
        }
        self.keyPrefix = keyPrefix
    }
    
    // MARK: - User Binding
    
    /// Binds the repository to a specific user. Keys become prefixed with userId.
    public func bind(to userId: String) {
        self.currentUserId = userId
    }
    
    /// Unbinds from the current user. Does NOT delete existing data.
    public func unbind() {
        self.currentUserId = nil
    }
    
    // MARK: - User-Keyed Storage Keys
    
    private var preKey: String {
        // Pre-onboarding is ALWAYS device-level (once per app install, regardless of user)
        return "\(keyPrefix).preCompleted"
    }
    
    private var postKey: String {
        guard let userId = currentUserId else {
            return "\(keyPrefix).postCompleted"  // Fallback for pre-auth (not user-specific)
        }
        return "\(keyPrefix).\(userId).postCompleted"
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
