import XCTest
@testable import WhatsThatData

final class StubDiscoveryRepositoryTests: XCTestCase {
    func testStubRepositoryReturnsSampleDiscoveries() async throws {
        let repository = StubDiscoveryRepository()
        let discoveries = try await repository.fetchDiscoveries(limit: 5, before: nil)
        XCTAssertFalse(discoveries.isEmpty)
    }
}
