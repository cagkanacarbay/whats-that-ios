import XCTest
@testable import WhatsThatShared

final class AppConfigurationTests: XCTestCase {
    func testPreviewConfigurationHasEmptyKeys() {
        let config = AppConfiguration.preview
        XCTAssertEqual(config.supabaseAnonKey, "")
        XCTAssertNil(config.supabaseURL)
    }
}
