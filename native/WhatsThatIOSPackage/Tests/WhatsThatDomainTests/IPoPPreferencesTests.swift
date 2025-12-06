import XCTest
@testable import WhatsThatDomain

final class IPoPPreferencesTests: XCTestCase {
    func testStoreSaveLoadReset() async {
        let suite = "ipop.preferences.tests.save"
        let store = IPoPPreferencesStore(suiteName: suite)
        await store.reset()

        let nilCheck1 = await store.load()
        XCTAssertNil(nilCheck1)

        let expected = IPoPPreferences(ordered: [.ideas, .people, .objects, .physical])
        XCTAssertNotNil(expected)
        await store.save(expected!)

        let loaded = await store.load()
        XCTAssertEqual(loaded, expected)

        await store.reset()
        let nilCheck2 = await store.load()
        XCTAssertNil(nilCheck2)
    }

    func testStoreReturnsNilForInvalidData() async {
        let suite = "ipop.preferences.tests.invalid"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(["Ideas", "Ideas", "People"], forKey: "ipop.preferences")

        let store = IPoPPreferencesStore(suiteName: suite)
        let loaded = await store.load()
        XCTAssertNil(loaded)
    }

    func testDiscoveryContextIncludesPreferencesWhenNoHistory() throws {
        let builder = DiscoveryContextBuilder()
        let preferences = IPoPPreferences(ordered: [.ideas, .people, .objects, .physical])!

        let context = builder.buildContext(from: [], ipopPreferences: preferences)
        let data = try XCTUnwrap(context?.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let prefs = json["ipopPreferences"] as? [String: Any]
        XCTAssertEqual(prefs?["ordered"] as? [String], ["Ideas", "People", "Objects", "Physical"])

        XCTAssertEqual(json["recentFullDiscoveries"] as? String, "")
        XCTAssertEqual(json["aggregatedHistory"] as? String, "")
    }

    func testDiscoveryContextNilWhenNoHistoryAndNoPreferences() {
        let builder = DiscoveryContextBuilder()
        let context = builder.buildContext(from: [])
        XCTAssertNil(context)
    }
}
