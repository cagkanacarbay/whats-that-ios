import XCTest
@testable import WhatsThatDomain
import WhatsThatData

final class DiscoveryFeedUseCaseTests: XCTestCase {
    func testLoadPageReturnsStubData() async throws {
        let repository = StubDiscoveryRepository()
        let useCase = DiscoveryFeedUseCase(repository: repository)

        let discoveries = try await useCase.loadPage(limit: 2)
        XCTAssertEqual(discoveries.count, 2)
        XCTAssertEqual(discoveries.first?.title, "Golden Gate Bridge")
    }

    func testLoadPageWithCursorReturnsOlderEntries() async throws {
        let repository = StubDiscoveryRepository()
        let useCase = DiscoveryFeedUseCase(repository: repository)

        let firstPage = try await useCase.loadPage(limit: 2)
        let cursor = firstPage.last?.id

        let secondPage = try await useCase.loadPage(limit: 2, before: cursor)
        XCTAssertEqual(secondPage.count, 2)
        XCTAssertTrue(secondPage.allSatisfy { $0.id < cursor ?? Int64.max })
    }
}
