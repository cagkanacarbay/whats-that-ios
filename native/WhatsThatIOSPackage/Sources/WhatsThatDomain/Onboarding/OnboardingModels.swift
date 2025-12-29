import Foundation

public struct OnboardingFlags: Equatable, Sendable {
    public var hasCompletedPreOnboarding: Bool
    public var hasCompletedPostOnboarding: Bool

    public init(
        hasCompletedPreOnboarding: Bool = false,
        hasCompletedPostOnboarding: Bool = false
    ) {
        self.hasCompletedPreOnboarding = hasCompletedPreOnboarding
        self.hasCompletedPostOnboarding = hasCompletedPostOnboarding
    }
}

public enum OnboardingStage: Equatable, Sendable {
    case pre
    case post
    case complete
}

public protocol OnboardingRepository: Sendable {
    func loadFlags() async -> OnboardingFlags
    func markPreOnboardingComplete() async
    func markPostOnboardingComplete() async
    func reset() async
    
    /// Binds the repository to a specific user. Keys become prefixed with userId.
    func bind(to userId: String) async
    
    /// Unbinds from the current user. Does NOT delete existing data.
    func unbind() async
}

public extension OnboardingRepository {
    func reset() async {
        // Optional to implement.
    }
    
    func bind(to userId: String) async {
        // Optional to implement.
    }
    
    func unbind() async {
        // Optional to implement.
    }
}

public actor OnboardingUseCase: Sendable {
    private let repository: OnboardingRepository

    public init(repository: OnboardingRepository) {
        self.repository = repository
    }

    public func flags() async -> OnboardingFlags {
        await repository.loadFlags()
    }

    public func markPreOnboardingComplete() async {
        await repository.markPreOnboardingComplete()
    }

    public func markPostOnboardingComplete() async {
        await repository.markPostOnboardingComplete()
    }

    public func reset() async {
        await repository.reset()
    }
    
    public func bind(to userId: String) async {
        await repository.bind(to: userId)
    }
    
    public func unbind() async {
        await repository.unbind()
    }
}
