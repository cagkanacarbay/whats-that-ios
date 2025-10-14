import XCTest
@testable import WhatsThatPresentation
import WhatsThatData
import WhatsThatDomain

@MainActor
final class DiscoveryFeedViewModelTests: XCTestCase {
    func testLoadTransitionsToLoadedState() async throws {
        let repository = StubDiscoveryRepository()
        let useCase = DiscoveryFeedUseCase(repository: repository)
        let viewModel = DiscoveryFeedViewModel(feedUseCase: useCase)

        await viewModel.loadInitialIfNeeded()

        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertFalse(viewModel.discoveries.isEmpty)
    }
}
