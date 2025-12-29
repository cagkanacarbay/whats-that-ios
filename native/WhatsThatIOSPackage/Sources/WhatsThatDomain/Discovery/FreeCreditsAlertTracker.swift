import Foundation

/// Tracks whether the "free credits exhausted" alert has been shown to each user.
/// Keyed by user ID to support multi-account scenarios.
///
/// This replaces the voiceover-based `IntroVoiceoverTracker` with a simpler credit-based approach:
/// - Show alert when credits reach 0 (after discovery or voiceover creation)
/// - Show alert at confirm stage if user already has 0 credits
/// - Only show once per user
public actor FreeCreditsAlertTracker {
    public static let shared = FreeCreditsAlertTracker()
    
    private var currentUserId: String?
    private let defaults = UserDefaults.standard
    
    private init() {}
    
    private func key(_ suffix: String) -> String {
        guard let userId = currentUserId else { return "freeCredits.anonymous.\(suffix)" }
        return "freeCredits.\(userId).\(suffix)"
    }
    
    // MARK: - User Binding
    
    /// Call when user signs in. Binds tracker to this user's data.
    public func bind(to userId: String) {
        currentUserId = userId
        print("[FreeCreditsAlertTracker] Bound to user \(userId.prefix(8))..., hasShown=\(hasShownCreditsExhaustedAlert)")
    }
    
    /// Call when user signs out. Clears current binding (does NOT delete data).
    public func unbind() {
        currentUserId = nil
    }
    
    // MARK: - State Access
    
    /// True if we've already shown the "credits exhausted" alert to this user.
    public var hasShownCreditsExhaustedAlert: Bool {
        guard currentUserId != nil else { return true }
        return defaults.bool(forKey: key("hasShownCreditsExhausted"))
    }
    
    /// True if user is still in intro mode (toggle should be locked ON).
    /// Intro mode ends when the credits exhausted alert has been shown.
    public var isInIntroMode: Bool {
        !hasShownCreditsExhaustedAlert
    }
    
    /// Returns true if we should show the "credits exhausted" alert.
    /// - Parameter currentBalance: The user's current credit balance
    /// - Returns: True if balance is 0 and alert hasn't been shown yet
    public func shouldShowCreditsExhaustedAlert(currentBalance: Int) -> Bool {
        return currentBalance == 0 && !hasShownCreditsExhaustedAlert
    }
    
    // MARK: - State Mutations
    
    /// Call after showing the credits exhausted alert.
    public func markCreditsExhaustedAlertShown() {
        guard currentUserId != nil else { return }
        defaults.set(true, forKey: key("hasShownCreditsExhausted"))
        print("[FreeCreditsAlertTracker] Credits exhausted alert marked as shown")
    }
    
    /// Reset the alert flag for testing purposes (dev only).
    /// After calling this, the alert will show again next time balance hits 0.
    public func resetForTesting() {
        guard currentUserId != nil else { return }
        defaults.set(false, forKey: key("hasShownCreditsExhausted"))
        print("[FreeCreditsAlertTracker] Reset for testing - alert will show again")
    }
}
