import XCTest
@testable import WhatsThatDomain
@testable import WhatsThatInfrastructure

final class NearbyPlacesCoordinatorTests: XCTestCase {
    private let coordinate = GeoCoordinate(latitude: 37.7749, longitude: -122.4194)

    func testFetchesAndCachesNearbyPlaces() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let cacheStore = NearbyPlacesCacheStore(cacheDirectory: tempDirectory)
        let fetcher = StubNearbyPlacesFetcher(places: [SampleData.place])
        let coordinator = NearbyPlacesCoordinator(
            config: .default,
            cacheStore: cacheStore,
            fetcher: fetcher
        )

        let sample = DiscoveryLocationSample(
            coordinate: coordinate,
            timestamp: Date(),
            horizontalAccuracy: 15,
            source: .live
        )

        await coordinator.register(sample: sample, preferImmediateFetch: true)
        try await Task.sleep(nanoseconds: 400_000_000)

        let selection = await coordinator.currentSelection()
        XCTAssertNotNil(selection)
        XCTAssertEqual(selection?.snapshot.places.count, 1)
        XCTAssertEqual(selection?.snapshot.places.first?.id, SampleData.place.id)
        XCTAssertEqual(await fetcher.fetchCount, 1)
        XCTAssertTrue(selection?.context.summary.contains("+/-") ?? false)
    }

    func testReusesCachedSnapshotWithinRadius() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let cacheStore = NearbyPlacesCacheStore(cacheDirectory: tempDirectory)
        let fetcher = StubNearbyPlacesFetcher(places: [SampleData.place])
        let coordinator = NearbyPlacesCoordinator(
            config: .default,
            cacheStore: cacheStore,
            fetcher: fetcher
        )

        let firstSample = DiscoveryLocationSample(
            coordinate: coordinate,
            timestamp: Date(),
            horizontalAccuracy: 20,
            source: .live
        )

        await coordinator.register(sample: firstSample, preferImmediateFetch: true)
        try await Task.sleep(nanoseconds: 400_000_000)

        let secondCoordinate = GeoCoordinate(latitude: coordinate.latitude + 0.001, longitude: coordinate.longitude)
        let secondSample = DiscoveryLocationSample(
            coordinate: secondCoordinate,
            timestamp: Date(),
            horizontalAccuracy: 25,
            source: .live
        )

        await coordinator.register(sample: secondSample)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(await fetcher.fetchCount, 1, "Second registration within radius should reuse cached snapshot.")

        let selection = await coordinator.currentSelection()
        XCTAssertNotNil(selection)
        XCTAssertEqual(selection?.snapshot.places.count, 1)
    }
}

private enum SampleData {
    static let place = NearbyPlace(
        id: "test-place",
        name: "Test Place",
        displayName: NearbyPlace.LocalizedText(text: "Test Place"),
        formattedAddress: "123 Demo Street",
        googleMapsUri: "https://maps.google.com",
        primaryType: "park",
        types: ["park"],
        location: NearbyPlace.PlaceLocation(latitude: 37.7749, longitude: -122.4194),
        subDestinations: nil
    )
}

private actor StubNearbyPlacesFetcher: NearbyPlacesFetching {
    private(set) var fetchCount: Int = 0
    private let places: [NearbyPlace]

    init(places: [NearbyPlace]) {
        self.places = places
    }

    func fetchNearbyPlaces(
        latitude _: Double,
        longitude _: Double,
        radius _: Double
    ) async throws -> [NearbyPlace] {
        fetchCount += 1
        return places
    }
}
