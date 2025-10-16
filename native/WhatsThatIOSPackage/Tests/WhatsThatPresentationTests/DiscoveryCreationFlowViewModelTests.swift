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
        let analysisClient = StubAnalysisClient(
            events: [
                .status("Uploading photo…"),
                .token("=== USER RESPONSE ===\n"),
                .token("## Redwood Sentinel\n\n"),
                .token("An ancient tree stands tall along the ridge.\n\n"),
                .token("### metadata_json\n{\"title\":\"Redwood Sentinel\",\"shortDescription\":\"A centuries-old coast redwood.\"}\n"),
                .complete(discoveryId: 99, systemPromptVersion: "1", userPromptVersion: "1"),
                .end
            ]
        )
        let imageEncoder = StubImageEncoder()
        let pushService = StubPushService()
        let locationService = StubLocationService(location: sampleLocation)

        let viewModel = DiscoveryCreationFlowViewModel(
            configuration: .init(type: .upload, maxImageDimension: 2048, recentHistoryLimit: 3),
            captureService: StubCaptureService(),
            selectionService: selectionService,
            historyRepository: historyRepository,
            creditsRepository: creditsRepository,
            analysisClient: analysisClient,
            imageEncoder: imageEncoder,
            pushService: pushService,
            locationService: locationService
        )

        let createdExpectation = expectation(description: "discovery created")
        viewModel.onDiscoveryCreated = { identifier in
            XCTAssertEqual(identifier, 99)
            createdExpectation.fulfill()
        }

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

        await fulfillment(of: [createdExpectation], timeout: 1.0)
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

private final class StubAnalysisClient: DiscoveryAnalysisClient {
    private let scheduledEvents: [DiscoveryAnalysisEvent]

    init(events: [DiscoveryAnalysisEvent]) {
        self.scheduledEvents = events
    }

    func startAnalysis(
        payload _: DiscoveryAnalysisPayload,
        sessionId _: UUID,
        cancellationHandler: @escaping @Sendable () async -> Void
    ) -> AsyncThrowingStream<DiscoveryAnalysisEvent, Error> {
        let events = scheduledEvents

        return AsyncThrowingStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                    try? await Task.sleep(nanoseconds: 2_000_000)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                Task {
                    await cancellationHandler()
                }
            }
        }
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

private final class StubLocationService: DiscoveryLocationService {
    private let resolvedLocation: DiscoveryLocation?

    init(location: DiscoveryLocation?) {
        self.resolvedLocation = location
    }

    func startTrackingIfNeeded() async {}

    func stopTracking() {}

    func currentLocation() async -> DiscoveryLocation? {
        resolvedLocation
    }

    func attachLocationMetadata(from media: DiscoveryCapturedMedia) async -> DiscoveryLocation? {
        resolvedLocation ?? media.location
    }
}
