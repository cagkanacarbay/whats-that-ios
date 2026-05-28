import XCTest
@testable import WhatsThatPresentation
import WhatsThatDomain

@MainActor
final class DiscoveryCreationFlowViewModelTests: XCTestCase {
    func testBeginAnalysisStreamsAndCompletes() async throws {
        let sampleLocation = DiscoveryLocation(
            latitude: 37.795,
            longitude: -122.393,
            country: "United States",
            locality: "San Francisco",
            streetName: "Market Street",
            closestPlace: "Ferry Building"
        )

        let capturedMedia = DiscoveryCapturedMedia(
            data: Data(repeating: 0xFF, count: 16),
            contentType: "image/jpeg",
            originalFilename: "sample.jpg",
            pixelWidth: 1080,
            pixelHeight: 1920,
            createdAt: Date(),
            location: nil
        )

        let selectionService = StubSelectionService(media: capturedMedia)
        let historyRepository = StubHistoryRepository()
        let creditsRepository = StubCreditsRepository(balance: 5)
        let testSuite = UUID().uuidString
        let creditBalanceStore = CreditBalanceStore(
            repository: creditsRepository,
            suiteName: testSuite,
            ttl: 0
        )
        let imageEncoder = StubImageEncoder()
        let pushService = StubPushService()
        let locationService = StubLocationService(location: sampleLocation)

        let viewModel = DiscoveryCreationFlowViewModel(
            configuration: .init(type: .upload, maxImageDimension: 2048, recentHistoryLimit: 3),
            captureService: StubCaptureService(),
            selectionService: selectionService,
            historyRepository: historyRepository,
            creditBalanceStore: creditBalanceStore,
            imageEncoder: imageEncoder,
            pushService: pushService,
            locationService: locationService
        )

        viewModel.startFlow()

        let confirmationReady = await waitUntil({ viewModel.confirmationState != nil })
        XCTAssertTrue(confirmationReady, "Expected confirmation state to be prepared")
        guard let confirmation = viewModel.confirmationState else {
            XCTFail("Missing confirmation state")
            return
        }

        XCTAssertEqual(viewModel.creditBalance, 5)
        XCTAssertEqual(DiscoveryCreationFlowViewModel.makeLocationDescription(from: confirmation.location), "San Francisco, United States")
        XCTAssertNotNil(confirmation.customContext)

        viewModel.beginAnalysis()

        let analysisCompleted = await waitUntil({
            viewModel.analysisState?.discoveryIdentifier == 99 && viewModel.analysisState?.isStreaming == false
        })
        XCTAssertTrue(analysisCompleted, "Expected analysis to complete")

        guard let analysisState = viewModel.analysisState else {
            return XCTFail("Missing analysis state")
        }

        XCTAssertEqual(analysisState.metadataTitle, "Redwood Sentinel")
        XCTAssertEqual(analysisState.metadataShortDescription, "A centuries-old coast redwood.")
        XCTAssertTrue(analysisState.displayMarkdown.contains("## Redwood Sentinel"))
        XCTAssertFalse(analysisState.displayMarkdown.contains("metadata_json"))

        // Verify the published property was set (Phase 3: replaces onDiscoveryCreated closure)
        XCTAssertEqual(viewModel.createdDiscoveryId, 99)
    }

    func testUploadCancellationReturnsToIdleState() async {
        let historyRepository = StubHistoryRepository()
        let creditsRepository = StubCreditsRepository(balance: 5)
        let testSuite1 = UUID().uuidString
        let creditBalanceStore = CreditBalanceStore(
            repository: creditsRepository,
            suiteName: testSuite1,
            ttl: 0
        )

        let viewModel = DiscoveryCreationFlowViewModel(
            configuration: .init(type: .upload, maxImageDimension: 2048, recentHistoryLimit: 3),
            captureService: StubCaptureService(),
            selectionService: CancellingSelectionService(),
            historyRepository: historyRepository,
            creditBalanceStore: creditBalanceStore,
            imageEncoder: StubImageEncoder(),
            pushService: StubPushService(),
            locationService: StubLocationService(location: nil)
        )

        viewModel.startFlow()

        let reset = await waitUntil({ viewModel.flowState == .idle })
        XCTAssertTrue(reset, "Expected idle state after user cancels selection")
        XCTAssertEqual(viewModel.flowState, .idle)
        XCTAssertNil(viewModel.error)
    }

    func testCameraCancellationReturnsToIdleState() async {
        let capturedMedia = DiscoveryCapturedMedia(
            data: Data(repeating: 0xAA, count: 8),
            contentType: "image/jpeg",
            originalFilename: "placeholder.jpg",
            pixelWidth: 800,
            pixelHeight: 600,
            createdAt: Date(),
            location: nil
        )
        let historyRepository = StubHistoryRepository()
        let creditsRepository = StubCreditsRepository(balance: 2)
        let testSuite2 = UUID().uuidString
        let creditBalanceStore = CreditBalanceStore(
            repository: creditsRepository,
            suiteName: testSuite2,
            ttl: 0
        )

        let viewModel = DiscoveryCreationFlowViewModel(
            configuration: .init(type: .camera, maxImageDimension: 2048, recentHistoryLimit: 3),
            captureService: CancellingCaptureService(),
            selectionService: StubSelectionService(media: capturedMedia),
            historyRepository: historyRepository,
            creditBalanceStore: creditBalanceStore,
            imageEncoder: StubImageEncoder(),
            pushService: StubPushService(),
            locationService: StubLocationService(location: nil)
        )

        viewModel.startFlow()

        let reset = await waitUntil({ viewModel.flowState == .idle })
        XCTAssertTrue(reset, "Expected idle state after user cancels capture")
        XCTAssertEqual(viewModel.flowState, .idle)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - Helpers

    private func waitUntil(
        _ predicate: @escaping () -> Bool,
        timeout: TimeInterval = 1.0
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return predicate()
    }
}

// MARK: - Test Doubles

private final class StubCaptureService: DiscoveryCaptureService {
    func requestPermission(for type: DiscoveryCreationFlowType) async -> Bool {
        type == .camera
    }

    func capturePhoto() async throws -> DiscoveryCapturedMedia {
        throw NSError(domain: "StubCaptureService", code: 0)
    }
}

private final class StubSelectionService: DiscoverySelectionService {
    private let media: DiscoveryCapturedMedia
    var permissionGranted: Bool = true

    init(media: DiscoveryCapturedMedia) {
        self.media = media
    }

    func requestPermission() async -> Bool {
        permissionGranted
    }

    func selectPhoto() async throws -> DiscoveryCapturedMedia {
        media
    }
}

private struct StubHistoryRepository: DiscoveryHistoryRepository {
    func fetchRecentDiscoveries(limit: Int) async throws -> [DiscoverySummary] {
        let sample = DiscoverySummary(
            id: 1,
            title: "Golden Gate Bridge",
            highlight: "Suspension bridge with sweeping bay views.",
            shortDescription: "Suspension bridge with sweeping bay views.",
            detailDescription: "Opened in 1937, the Golden Gate Bridge spans 1.7 miles and is renowned for its International Orange colour.",
            capturedAt: Date().addingTimeInterval(-7200),
            imagePath: nil,
            shareToken: nil,
            location: DiscoveryLocation(
                latitude: 37.8199,
                longitude: -122.4783,
                country: "United States",
                locality: "San Francisco",
                streetName: "Lincoln Blvd",
                closestPlace: "Golden Gate Bridge"
            )
        )
        return Array(repeating: sample, count: min(limit, 3))
    }
}

private struct StubCreditsRepository: DiscoveryCreditsRepository {
    let balance: Int

    func fetchCreditBalance() async throws -> Int {
        balance
    }
}

private struct StubImageEncoder: DiscoveryImageEncodingService {
    func encodeImageData(_ media: DiscoveryCapturedMedia, maxDimension _: Int) async throws -> Data {
        media.data
    }

    func makeBase64Payload(from media: DiscoveryCapturedMedia, maxDimension _: Int) async throws -> String {
        media.data.base64EncodedString()
    }
}

private struct StubPushService: DiscoveryPushService {
    func requestPushAuthorizationIfNeeded() async throws -> String? {
        nil
    }
}

private final class CancellingSelectionService: DiscoverySelectionService {
    func requestPermission() async -> Bool {
        true
    }

    func selectPhoto() async throws -> DiscoveryCapturedMedia {
        throw DiscoveryFlowCancellationError.userCancelled
    }
}

private final class CancellingCaptureService: DiscoveryCaptureService {
    func requestPermission(for type: DiscoveryCreationFlowType) async -> Bool {
        type == .camera
    }

    func capturePhoto() async throws -> DiscoveryCapturedMedia {
        throw DiscoveryFlowCancellationError.userCancelled
    }
}

private final class StubLocationService: DiscoveryLocationService {
    private let resolvedLocation: DiscoveryLocation?
    var nearbySelection: NearbyPlacesSelection?

    init(location: DiscoveryLocation?) {
        self.resolvedLocation = location
    }

    func startTrackingIfNeeded() async {}

    func requestLocationAuthorization() async {}

    func stopTracking() {}

    func currentLocation() async -> DiscoveryLocation? {
        resolvedLocation
    }

    func currentLocationIfRecent(maxAge: TimeInterval, maxAccuracyMeters: Double) async -> DiscoveryLocation? {
        // Test stub: treat provided location as always recent/accurate if present
        resolvedLocation
    }

    func currentLocationStrictFreshEphemeral(timeout: TimeInterval) async -> DiscoveryLocation? {
        // Test stub: return the same stubbed location immediately
        resolvedLocation
    }

    func attachLocationMetadata(from media: DiscoveryCapturedMedia) async -> DiscoveryLocation? {
        resolvedLocation ?? media.location
    }

    func prepareNearbyPlaces(for location: DiscoveryLocation?) async -> NearbyPlacesSelection? {
        nearbySelection
    }

    func registerMediaLocation(_ location: DiscoveryLocation) async {}

    func debugLogNearbyState(current: DiscoveryLocation?) async {}
    func listNearbyCache() async -> [NearbyPlacesSnapshot] { [] }
    func clearNearbyCache() async {}
}
