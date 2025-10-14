import XCTest
@testable import WhatsThatInfrastructure

final class StubSupabaseTransportTests: XCTestCase {
    func testStubTransportReturnsEmptyData() async throws {
        let transport = StubSupabaseTransport()
        let data = try await transport.get(path: "/discoveries")
        XCTAssertEqual(data, Data())
    }
}
