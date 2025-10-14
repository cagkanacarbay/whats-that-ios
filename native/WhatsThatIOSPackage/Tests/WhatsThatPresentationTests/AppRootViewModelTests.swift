import Foundation
import XCTest
@testable import WhatsThatDomain
@testable import WhatsThatInfrastructure
@testable import WhatsThatPresentation

final class AppRootViewModelTests: XCTestCase {
    func testInitialStateIsPreOnboarding() async {
        let viewModel = await makeViewModel()
        await waitForState(in: viewModel) { state in
            state == .preOnboarding
        }
    }

    func testCompletingPreOnboardingTransitionsToAuthentication() async {
        let viewModel = await makeViewModel()

        await waitForState(in: viewModel) { $0 == .preOnboarding }
        await viewModel.completePreOnboarding()
        await waitForState(in: viewModel) { $0 == .authentication }
    }

    func testSigningUpAdvancesToPostOnboarding() async throws {
        let viewModel = await makeViewModel()

        await waitForState(in: viewModel) { $0 == .preOnboarding }
        await viewModel.completePreOnboarding()
        await waitForState(in: viewModel) { $0 == .authentication }

        try await viewModel.signUp(email: "person@example.com", password: "password123")

        await waitForState(in: viewModel) { state in
            if case let .postOnboarding(user) = state {
                XCTAssertEqual(user.email, "person@example.com")
                return true
            }
            return false
        }
    }

    // MARK: - Helpers

    @MainActor
    private func makeViewModel() -> AppRootViewModel {
        let authService = StubAuthService()
        let authUseCase = AuthUseCase(service: authService)
        let onboardingRepository = TestOnboardingRepository()
        let onboardingUseCase = OnboardingUseCase(repository: onboardingRepository)
        return AppRootViewModel(
            authUseCase: authUseCase,
            onboardingUseCase: onboardingUseCase,
            flowResolver: AppFlowResolver()
        )
    }

    private func waitForState(
        in viewModel: AppRootViewModel,
        timeout: TimeInterval = 1,
        predicate: @escaping (AppFlowState) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let current = await MainActor.run { viewModel.flowState }
            if predicate(current) {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Timed out waiting for expected state change", file: file, line: line)
    }
}

private actor TestOnboardingRepository: OnboardingRepository {
    private var flags = OnboardingFlags()

    func loadFlags() async -> OnboardingFlags {
        flags
    }

    func markPreOnboardingComplete() async {
        flags.hasCompletedPreOnboarding = true
    }

    func markPostOnboardingComplete() async {
        flags.hasCompletedPostOnboarding = true
    }

    func reset() async {
        flags = OnboardingFlags()
    }
}
