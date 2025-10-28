@testable import WhatsThatShared
import XCTest

final class DiscoveryAssetCacheTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
    }

    func testSignedURLCacheStoresAndRetrieves() async throws {
        let cache = DiscoveryAssetCache(cachesDirectory: rootURL)
        let discoveryId: Int64 = 42
        let storagePath = "objects/foo.jpg"
        let signedURL = URL(string: "https://example.com/signed-url")!
        let expiration = Date().addingTimeInterval(3600)

        await cache.storeSignedURL(
            signedURL,
            expiresAt: expiration,
            discoveryId: discoveryId,
            storagePath: storagePath
        )

        let cached = await cache.cachedSignedURL(
            for: discoveryId,
            storagePath: storagePath
        )

        XCTAssertEqual(cached, signedURL)
    }

    func testStoreImageDataPersistsToDisk() async throws {
        let cache = DiscoveryAssetCache(cachesDirectory: rootURL)
        let discoveryId: Int64 = 7
        let storagePath = "objects/bar.jpg"
        let signedURL = URL(string: "https://example.com/image")!
        let expiration = Date().addingTimeInterval(3600)

        await cache.storeSignedURL(
            signedURL,
            expiresAt: expiration,
            discoveryId: discoveryId,
            storagePath: storagePath
        )

        let imageData = Data([0x01, 0x02, 0x03])
        let storedURL = await cache.storeImageData(
            imageData,
            discoveryId: discoveryId
        )

        XCTAssertNotNil(storedURL)
        if let storedURL {
            let storedData = try Data(contentsOf: storedURL)
            XCTAssertEqual(storedData, imageData)
        }
    }

    func testPurgeExpiredEntriesRemovesCachedData() async throws {
        let cache = DiscoveryAssetCache(cachesDirectory: rootURL)
        let discoveryId: Int64 = 99
        let storagePath = "objects/baz.jpg"
        let signedURL = URL(string: "https://example.com/old")!
        let expiration = Date().addingTimeInterval(-60)

        await cache.storeSignedURL(
            signedURL,
            expiresAt: expiration,
            discoveryId: discoveryId,
            storagePath: storagePath
        )

        await cache.purgeExpiredEntries()

        let cached = await cache.cachedSignedURL(
            for: discoveryId,
            storagePath: storagePath
        )

        XCTAssertNil(cached)
    }
}
