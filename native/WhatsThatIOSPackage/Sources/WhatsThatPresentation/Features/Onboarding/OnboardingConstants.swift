import SwiftUI

/// Layout constants for the onboarding UI components.
enum OnboardingLayoutConstants {
    // MARK: - Pre-Onboarding Layout

    /// Height estimate for the bottom sheet (button + sign-in link + padding).
    static let bottomSheetHeight: CGFloat = 150

    /// Height of the mini player when visible (artwork diameter + gap).
    static let miniPlayerHeight: CGFloat = 120

    /// Height of the bottom area blocker that covers the safe area and rounded corner gap.
    static let bottomAreaBlockerOverlap: CGFloat = 40

    /// Delay before marking the detail view warmup as complete (in nanoseconds).
    /// Allows SwiftUI to pre-compile the complex view hierarchy.
    static let detailViewWarmupDelayNanoseconds: UInt64 = 400_000_000

    /// Bottom padding for mini player when in detail view (includes safe area spacing).
    static let miniPlayerDetailViewBottomPadding: CGFloat = 130
}
