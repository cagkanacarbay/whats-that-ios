import XCTest
@testable import WhatsThatPresentation
import WhatsThatDomain

@MainActor
final class ConfirmationStateBuilderTests: XCTestCase {

    private let sampleLocation = DiscoveryLocation(
        latitude: 37.795,
        longitude: -122.393,
        country: "United States",
        locality: "San Francisco",
        streetName: "Market Street",
        closestPlace: "Ferry Building"
    )

    private let sampleMedia = DiscoveryCapturedMedia(
        data: Data(repeating: 0xAA, count: 16),
        contentType: "image/jpeg",
        originalFilename: "test.jpg",
        pixelWidth: 1080,
        pixelHeight: 1920,
        createdAt: Date(),
        location: nil
    )

    // MARK: - build()

    func testBuildWithUploadAndEXIFLocation() async {
        let mediaWithLocation = DiscoveryCapturedMedia(
            data: Data(repeating: 0xBB, count: 16),
            contentType: "image/jpeg",
            originalFilename: "upload.jpg",
            pixelWidth: 1080,
            pixelHeight: 1920,
            createdAt: Date(),
            location: sampleLocation
        )

        let builder = makeBuilder(location: sampleLocation)

        let result = await builder.build(
            media: mediaWithLocation,
            flowType: .upload,
            freshLocation: nil,
            recentHistoryLimit: 3
        )

        // Upload flow uses EXIF location from media
        XCTAssertNotNil(result.state.location)
        XCTAssertEqual(result.state.location?.latitude, sampleLocation.latitude)
        XCTAssertEqual(result.state.location?.longitude, sampleLocation.longitude)
    }

    func testBuildWithCameraAndNoPermission() async {
        let builder = makeBuilder(location: nil, permissionGranted: false)

        let result = await builder.build(
            media: sampleMedia,
            flowType: .camera,
            freshLocation: nil,
            recentHistoryLimit: 3
        )

        XCTAssertNil(result.state.location)
        XCTAssertFalse(result.state.isLocationPermissionGranted)
    }

    func testBuildWithCameraAndFreshLocation() async {
        let builder = makeBuilder(location: sampleLocation, permissionGranted: true)

        let result = await builder.build(
            media: sampleMedia,
            flowType: .camera,
            freshLocation: sampleLocation,
            recentHistoryLimit: 3
        )

        XCTAssertNotNil(result.state.location)
        XCTAssertEqual(result.state.location?.latitude, sampleLocation.latitude)
        XCTAssertTrue(result.state.isLocationPermissionGranted)
    }

    func testBuildLoadsCreditBalance() async {
        let builder = makeBuilder(location: nil, creditBalance: 10)

        let result = await builder.build(
            media: sampleMedia,
            flowType: .upload,
            freshLocation: nil,
            recentHistoryLimit: 3
        )

        XCTAssertEqual(result.creditBalance, 10)
    }

    func testBuildBuildsCustomContext() async {
        let builder = makeBuilder(location: nil, includeHistory: true)

        let result = await builder.build(
            media: sampleMedia,
            flowType: .upload,
            freshLocation: nil,
            recentHistoryLimit: 3
        )

        // History repo returns discoveries, so context should be built
        XCTAssertNotNil(result.state.customContext)
    }

    // MARK: - refreshAfterCreditsSheet()

    func testRefreshAfterCreditsSheet() async {
        let builder = makeBuilder(location: nil, creditBalance: 15)

        let result = await builder.refreshAfterCreditsSheet()

        XCTAssertEqual(result.balance, 15)
    }

    // MARK: - syncCreditBalance()

    func testSyncCreditBalance() async {
        let builder = makeBuilder(location: nil, creditBalance: 5)

        let synced = await builder.syncCreditBalance(20)

        XCTAssertEqual(synced, 20)
    }

    // MARK: - cancel()

    func testCancelClearsState() async {
        let builder = makeBuilder(location: nil)

        // Build some state first
        _ = await builder.build(
            media: sampleMedia,
            flowType: .upload,
            freshLocation: nil,
            recentHistoryLimit: 3
        )
        XCTAssertNotNil(builder.currentState)

        builder.cancel()

        XCTAssertNil(builder.currentState)
    }

    // MARK: - makeLocationDescription()

    func testMakeLocationDescriptionWithClosestPlace() {
        let location = DiscoveryLocation(
            latitude: 37.795,
            longitude: -122.393,
            country: "United States",
            locality: "San Francisco",
            streetName: nil,
            closestPlace: "Ferry Building"
        )
        XCTAssertEqual(ConfirmationStateBuilder.makeLocationDescription(from: location), "Ferry Building")
    }

    func testMakeLocationDescriptionWithLocalityAndCountry() {
        let location = DiscoveryLocation(
            latitude: 37.795,
            longitude: -122.393,
            country: "United States",
            locality: "San Francisco",
            streetName: nil,
            closestPlace: nil
        )
        XCTAssertEqual(ConfirmationStateBuilder.makeLocationDescription(from: location), "San Francisco, United States")
    }

    func testMakeLocationDescriptionWithCountryOnly() {
        let location = DiscoveryLocation(
            latitude: 37.795,
            longitude: -122.393,
            country: "United States",
            locality: nil,
            streetName: nil,
            closestPlace: nil
        )
        XCTAssertEqual(ConfirmationStateBuilder.makeLocationDescription(from: location), "United States")
    }

    func testMakeLocationDescriptionFallbackToCoordinates() {
        let location = DiscoveryLocation(
            latitude: 37.7950,
            longitude: -122.3930,
            country: nil,
            locality: nil,
            streetName: nil,
            closestPlace: nil
        )
        let description = ConfirmationStateBuilder.makeLocationDescription(from: location)
        XCTAssertNotNil(description)
        XCTAssertTrue(description!.contains("37.7950"))
    }

    func testMakeLocationDescriptionNil() {
        XCTAssertNil(ConfirmationStateBuilder.makeLocationDescription(from: nil))
    }

    // MARK: - Helpers

    private func makeBuilder(
        location: DiscoveryLocation?,
        permissionGranted: Bool = false,
        creditBalance: Int = 5,
        includeHistory: Bool = false
    ) -> ConfirmationStateBuilder {
        let locationService = TestLocationService(location: location, permissionGranted: permissionGranted)
        let creditsRepo = TestCreditsRepo(balance: creditBalance)
        let creditStore = CreditBalanceStore(
            repository: creditsRepo,
            suiteName: UUID().uuidString,
            ttl: 0
        )
        let historyRepo = TestHistoryRepo(hasDiscoveries: includeHistory)
        let pushService = TestPushService()

        return ConfirmationStateBuilder(
            locationService: locationService,
            creditBalanceStore: creditStore,
            historyRepository: historyRepo,
            pushService: pushService,
            voiceoverPreferencesStore: nil,
            ipopPreferencesStore: nil
        )
    }
}

// MARK: - Test Doubles

private final class TestLocationService: DiscoveryLocationService {
    private let resolvedLocation: DiscoveryLocation?
    private let permissionGranted: Bool

    init(location: DiscoveryLocation?, permissionGranted: Bool = false) {
        self.resolvedLocation = location
        self.permissionGranted = permissionGranted
    }

    func startTrackingIfNeeded() async {}
    func requestLocationAuthorization() async {}
    func stopTracking() {}

    func currentLocation() async -> DiscoveryLocation? { resolvedLocation }

    func currentLocationIfRecent(maxAge: TimeInterval, maxAccuracyMeters: Double) async -> DiscoveryLocation? {
        resolvedLocation
    }

    func currentLocationStrictFreshEphemeral(timeout: TimeInterval) async -> DiscoveryLocation? {
        resolvedLocation
    }

    func isPermissionGranted() async -> Bool {
        permissionGranted
    }

    func attachLocationMetadata(from media: DiscoveryCapturedMedia) async -> DiscoveryLocation? {
        resolvedLocation ?? media.location
    }

    func prepareNearbyPlaces(for location: DiscoveryLocation?) async -> NearbyPlacesSelection? {
        nil
    }

    func registerMediaLocation(_ location: DiscoveryLocation) async {}
    func debugLogNearbyState(current: DiscoveryLocation?) async {}
    func listNearbyCache() async -> [NearbyPlacesSnapshot] { [] }
    func clearNearbyCache() async {}
}

private struct TestCreditsRepo: DiscoveryCreditsRepository {
    let balance: Int
    func fetchCreditBalance() async throws -> Int { balance }
}

private struct TestHistoryRepo: DiscoveryHistoryRepository {
    let hasDiscoveries: Bool

    func fetchRecentDiscoveries(limit: Int) async throws -> [DiscoverySummary] {
        guard hasDiscoveries else { return [] }
        let sample = DiscoverySummary(
            id: 1,
            title: "Golden Gate Bridge",
            highlight: "Suspension bridge",
            shortDescription: "Suspension bridge with sweeping bay views.",
            capturedAt: Date().addingTimeInterval(-3600),
            location: DiscoveryLocation(
                latitude: 37.8199,
                longitude: -122.4783,
                country: "United States",
                locality: "San Francisco",
                streetName: nil,
                closestPlace: nil
            )
        )
        return Array(repeating: sample, count: min(limit, 3))
    }
}

private struct TestPushService: DiscoveryPushService {
    func requestPushAuthorizationIfNeeded() async throws -> String? { nil }
}
