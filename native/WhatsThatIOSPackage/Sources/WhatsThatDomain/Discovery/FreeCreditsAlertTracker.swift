import Foundation
import OSLog

private let logger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "FreeCreditsAlertTracker"
)

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
        let hasShown = self.hasShownCreditsExhaustedAlert
        logger.debug("[FreeCreditsAlertTracker] Bound to user \(userId.prefix(8))..., hasShown=\(hasShown)")
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

    // MARK: - Intro Discovery Count

    /// Number of discoveries created during intro mode (persisted per user)
    public var introDiscoveryCount: Int {
        guard currentUserId != nil else { return 0 }
        return defaults.integer(forKey: key("introDiscoveryCount"))
    }

    /// Increment before analysis starts (optimistic)
    public func incrementIntroDiscoveryCount() {
        guard currentUserId != nil, isInIntroMode else { return }
        let newCount = introDiscoveryCount + 1
        defaults.set(newCount, forKey: key("introDiscoveryCount"))
        logger.debug("[FreeCreditsAlertTracker] Intro discovery count incremented to: \(newCount)")
    }

    /// Decrement when edge function returns error (discovery not created)
    public func decrementIntroDiscoveryCount() {
        guard currentUserId != nil, isInIntroMode else { return }
        let newCount = max(0, introDiscoveryCount - 1)
        defaults.set(newCount, forKey: key("introDiscoveryCount"))
        logger.debug("[FreeCreditsAlertTracker] Intro discovery count decremented to: \(newCount)")
    }

    /// Returns true if intro mode user has hit the discovery limit
    /// Does NOT show if user has made a purchase (they've converted and exited intro)
    public func shouldShowCreditsExhaustedForIntroLimit() -> Bool {
        return isInIntroMode && introDiscoveryCount >= IntroModeConstants.discoveryLimit && !hasMadePurchase
    }
    
    // MARK: - State Mutations
    
    /// Call after showing the credits exhausted alert.
    public func markCreditsExhaustedAlertShown() {
        guard currentUserId != nil else { return }
        defaults.set(true, forKey: key("hasShownCreditsExhausted"))
        logger.debug("[FreeCreditsAlertTracker] Credits exhausted alert marked as shown")
    }
    
    /// Reset the alert flag for testing purposes (dev only).
    /// After calling this, the alert will show again next time balance hits 0.
    public func resetForTesting() {
        guard currentUserId != nil else { return }
        defaults.set(false, forKey: key("hasShownCreditsExhausted"))
        defaults.set(false, forKey: key("hasSeenAudioGeneratingModal"))
        defaults.set(false, forKey: key("hasCompletedPostPurchaseConfig"))
        defaults.set(0, forKey: key("cameraUseCount"))
        defaults.set(false, forKey: key("hasRequestedLocationPermission"))
        defaults.set(false, forKey: key("hasRequestedNotificationPermission"))
        defaults.set(false, forKey: key("hasMadePurchase"))
        defaults.set(0, forKey: key("introDiscoveryCount"))
        logger.debug("[FreeCreditsAlertTracker] Reset for testing - alerts will show again")
    }

    // MARK: - Purchase Tracking (for notification permission)

    /// True if the user has made at least one credit purchase.
    public var hasMadePurchase: Bool {
        guard currentUserId != nil else { return false }
        return defaults.bool(forKey: key("hasMadePurchase"))
    }

    /// Call after a successful credit purchase.
    /// Also marks intro as complete since purchasing means user has converted.
    public func markPurchaseMade() {
        guard currentUserId != nil else { return }
        defaults.set(true, forKey: key("hasMadePurchase"))

        // Purchasing credits means user has converted - exit intro mode
        if !hasShownCreditsExhaustedAlert {
            defaults.set(true, forKey: key("hasShownCreditsExhausted"))
            logger.debug("[FreeCreditsAlertTracker] Purchase marked + intro completed (user converted)")
        } else {
            logger.debug("[FreeCreditsAlertTracker] Purchase marked")
        }
    }

    // MARK: - Audio Generating Modal

    /// True if we've already shown the "audio generating" modal to this user.
    public var hasSeenAudioGeneratingModal: Bool {
        guard currentUserId != nil else { return true }
        return defaults.bool(forKey: key("hasSeenAudioGeneratingModal"))
    }

    /// Returns true if we should show the "audio generating" modal.
    public func shouldShowAudioGeneratingModal() -> Bool {
        return !hasSeenAudioGeneratingModal
    }

    /// Call after showing the audio generating modal.
    public func markAudioGeneratingModalShown() {
        guard currentUserId != nil else { return }
        defaults.set(true, forKey: key("hasSeenAudioGeneratingModal"))
        logger.debug("[FreeCreditsAlertTracker] Audio generating modal marked as shown")
    }

    // MARK: - Post-Purchase Configuration

    /// True if we've already shown the post-purchase configuration to this user.
    public var hasCompletedPostPurchaseConfig: Bool {
        guard currentUserId != nil else { return true }
        return defaults.bool(forKey: key("hasCompletedPostPurchaseConfig"))
    }

    /// Returns true if we should show the post-purchase configuration flow.
    public func shouldShowPostPurchaseConfig() -> Bool {
        return !hasCompletedPostPurchaseConfig
    }

    /// Call after completing the post-purchase configuration.
    public func markPostPurchaseConfigCompleted() {
        guard currentUserId != nil else { return }
        defaults.set(true, forKey: key("hasCompletedPostPurchaseConfig"))
        logger.debug("[FreeCreditsAlertTracker] Post-purchase config marked as completed")
    }

    // MARK: - Camera Use Tracking (for location permission)

    /// Number of times user has completed a camera capture flow.
    public var cameraUseCount: Int {
        guard currentUserId != nil else { return 0 }
        return defaults.integer(forKey: key("cameraUseCount"))
    }

    /// Increments the camera use count. Call after user successfully takes a photo.
    public func incrementCameraUseCount() {
        guard currentUserId != nil else { return }
        let newCount = cameraUseCount + 1
        defaults.set(newCount, forKey: key("cameraUseCount"))
        logger.debug("[FreeCreditsAlertTracker] Camera use count: \(newCount)")
    }

    // MARK: - Location Permission Tracking

    /// True if we've already requested location permission (on second camera use).
    public var hasRequestedLocationPermission: Bool {
        guard currentUserId != nil else { return true }
        return defaults.bool(forKey: key("hasRequestedLocationPermission"))
    }

    /// Call after requesting location permission.
    public func markLocationPermissionRequested() {
        guard currentUserId != nil else { return }
        defaults.set(true, forKey: key("hasRequestedLocationPermission"))
        logger.debug("[FreeCreditsAlertTracker] Location permission request marked")
    }

    // MARK: - Notification Permission Tracking

    /// True if we've already requested notification permission (after purchase).
    public var hasRequestedNotificationPermission: Bool {
        guard currentUserId != nil else { return true }
        return defaults.bool(forKey: key("hasRequestedNotificationPermission"))
    }

    /// Call after requesting notification permission.
    public func markNotificationPermissionRequested() {
        guard currentUserId != nil else { return }
        defaults.set(true, forKey: key("hasRequestedNotificationPermission"))
        logger.debug("[FreeCreditsAlertTracker] Notification permission request marked")
    }

    // MARK: - Intro State Resolution (for reinstalls / multi-device)

    /// Performs a one-time sanity check for returning users on fresh install/new device.
    /// Call this once after user binding with server-fetched data.
    ///
    /// If user has:
    /// - More credits than initial balance (>6): They bought credits, silently complete intro
    /// - More discoveries than free limit (>3): They bought credits, silently complete intro
    /// - Otherwise: Stay in intro mode, let normal alert flow handle it
    ///
    /// - Parameters:
    ///   - balance: Current credit balance from server
    ///   - discoveryCount: Number of discoveries the user has made
    /// - Returns: `true` if intro is complete (was already complete or resolved now), `false` if still in intro
    public func resolveIntroStateIfNeeded(balance: Int, discoveryCount: Int) -> Bool {
        // Already complete locally - nothing to check
        guard !hasShownCreditsExhaustedAlert else {
            logger.debug("[FreeCreditsAlertTracker] Intro already complete, skipping sanity check")
            return true
        }

        // User bought credits (more than initial balance)
        if balance > IntroModeConstants.initialCreditBalance {
            markIntroCompletedSilently(reason: "balance > \(IntroModeConstants.initialCreditBalance) (purchased credits)")
            return true
        }

        // User has more discoveries than the free limit - must have purchased
        if discoveryCount > IntroModeConstants.discoveryLimit {
            // Sync local introDiscoveryCount to match server
            let currentLocal = introDiscoveryCount
            if discoveryCount > currentLocal {
                defaults.set(discoveryCount, forKey: key("introDiscoveryCount"))
                logger.debug("[FreeCreditsAlertTracker] Synced introDiscoveryCount from server: \(discoveryCount)")
            }
            markIntroCompletedSilently(reason: "discoveryCount > \(IntroModeConstants.discoveryLimit) (purchased)")
            return true
        }

        // Sync local count even if not completing intro (for multi-device continuity)
        let currentLocal = introDiscoveryCount
        if discoveryCount > currentLocal {
            defaults.set(discoveryCount, forKey: key("introDiscoveryCount"))
            logger.debug("[FreeCreditsAlertTracker] Synced introDiscoveryCount from server: \(discoveryCount)")
        }

        logger.debug("[FreeCreditsAlertTracker] Sanity check: still in intro (balance=\(balance), discoveries=\(discoveryCount))")
        return false
    }

    /// Silently marks intro as complete without showing the exhausted alert.
    /// Used when sanity check determines user has already completed intro on another device.
    private func markIntroCompletedSilently(reason: String) {
        guard currentUserId != nil else { return }
        defaults.set(true, forKey: key("hasShownCreditsExhausted"))
        logger.debug("[FreeCreditsAlertTracker] Intro completed via sanity check: \(reason)")
    }
}
