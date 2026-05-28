import Foundation

/// Constants for intro mode business logic.
/// These define the thresholds and limits for the free trial experience.
public enum IntroModeConstants {
    /// Number of discoveries a user can create during intro mode before hitting the paywall.
    public static let discoveryLimit: Int = 3

    /// Initial credits given to new users (matches database trigger).
    /// Users get 6 credits = 3 discoveries + 3 audio guides.
    public static let initialCreditBalance: Int = 6
}
