import Foundation
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

    func testRefreshSurfacesCancellationErrors() async {
        let repository = QueueingDiscoveryRepository()
        let sample = DiscoverySummary(
            id: 1,
            title: "Sample",
            highlight: "Highlight",
            capturedAt: Date()
        )

        await repository.enqueue(.success([sample]))
        await repository.enqueue(.failure(CancellationError()))

        let useCase = DiscoveryFeedUseCase(repository: repository)
        let viewModel = DiscoveryFeedViewModel(feedUseCase: useCase)

        await viewModel.loadInitialIfNeeded()

        XCTAssertEqual(viewModel.discoveries, [sample])
        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertNil(viewModel.errorMessage)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.discoveries, [sample])
        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertEqual(viewModel.errorMessage, DiscoveryFeedError.failedToLoad.errorDescription)
        XCTAssertFalse(viewModel.isRefreshing)
    }
}

private actor QueueingDiscoveryRepository: DiscoveryRepository {
    private var results: [Result<[DiscoverySummary], Error>] = []

    func enqueue(_ result: Result<[DiscoverySummary], Error>) {
        results.append(result)
    }

    func fetchDiscoveries(limit _: Int, before _: Int64?) async throws -> [DiscoverySummary] {
        guard results.isEmpty == false else {
            return []
        }

        let result = results.removeFirst()
        switch result {
        case .success(let discoveries):
            return discoveries
        case .failure(let error):
            throw error
        }
    }
}
