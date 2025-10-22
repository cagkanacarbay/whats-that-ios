import Foundation

public enum AppFlowState: Equatable, Sendable {
    case loading
    case preOnboarding
    case authentication
    case postOnboarding(AuthenticatedUser)
    case main(AuthenticatedUser)
}

public struct AppFlowResolver: Sendable {
    public init() {}

    public func stage(for flags: OnboardingFlags) -> OnboardingStage {
        if !flags.hasCompletedPreOnboarding {
            return .pre
        } else if !flags.hasCompletedPostOnboarding {
            return .post
        } else {
            return .complete
        }
    }

    public func resolve(session: AuthSession, flags: OnboardingFlags) -> AppFlowState {
        if !flags.hasCompletedPreOnboarding {
            return .preOnboarding
        }

        switch session {
        case .signedOut:
            return .authentication
        case let .authenticated(user):
            if !flags.hasCompletedPostOnboarding {
                return .postOnboarding(user)
            } else {
                return .main(user)
            }
        }
    }
}
