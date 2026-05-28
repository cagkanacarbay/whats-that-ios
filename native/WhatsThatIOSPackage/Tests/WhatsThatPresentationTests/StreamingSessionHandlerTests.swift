import XCTest
import Combine
@testable import WhatsThatPresentation
import WhatsThatDomain

@MainActor
final class StreamingSessionHandlerTests: XCTestCase {

    private var handler: StreamingSessionHandler!
    private var mockDelegate: MockStreamingDelegate!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        let historyRepo = StubHistoryRepo()
        let creditsRepo = StubCreditsRepo(balance: 5)
        let creditStore = CreditBalanceStore(
            repository: creditsRepo,
            suiteName: UUID().uuidString,
            ttl: 0
        )
        handler = StreamingSessionHandler(
            historyRepository: historyRepo,
            creditBalanceStore: creditStore,
            photoSavePreferencesStore: nil,
            photoLibrarySaveService: nil
        )
        mockDelegate = MockStreamingDelegate()
        handler.delegate = mockDelegate
    }

    override func tearDown() {
        cancellables.removeAll()
        handler = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Event Handling via DiscoverySessionSubscriber

    func testTokenEventUpdatesStreamedText() {
        // Seed initial state
        handler.handleSessionEvent(.status("Starting..."))
        handler.handleSessionEvent(.token("Hello "))
        handler.handleSessionEvent(.token("World"))

        XCTAssertEqual(handler.analysisState?.streamedText, "Hello World")
        XCTAssertTrue(handler.analysisState?.isStreaming == true)
    }

    func testStatusEventUpdatesStatusMessage() {
        handler.handleSessionEvent(.status("Analyzing your photo..."))

        XCTAssertEqual(handler.analysisState?.statusMessage, "Analyzing your photo...")
    }

    func testMetadataEventUpdatesTitle() {
        handler.handleSessionEvent(.metadata(title: "Golden Gate Bridge", shortDescription: "Iconic suspension bridge"))

        XCTAssertEqual(handler.analysisState?.metadataTitle, "Golden Gate Bridge")
        XCTAssertEqual(handler.analysisState?.metadataShortDescription, "Iconic suspension bridge")
    }

    func testCompleteEventCallsDelegate() {
        handler.handleSessionEvent(.token("Some content"))
        handler.handleSessionEvent(.complete(discoveryId: 42, systemPromptVersion: "1.0", userPromptVersion: "1.0", creditBalance: 4))

        XCTAssertEqual(handler.analysisState?.discoveryIdentifier, 42)
        XCTAssertFalse(handler.analysisState?.isStreaming ?? true)
        XCTAssertEqual(mockDelegate.createdDiscoveryId, 42)
    }

    func testErrorWithCreditsMessageCallsReturnToConfirmation() {
        handler.handleSessionEvent(.error(message: "Insufficient credits", status: 402))

        XCTAssertTrue(mockDelegate.shouldReturnToConfirmationCalled)
        XCTAssertNil(mockDelegate.lastError)
    }

    func testErrorWithGenericMessageCallsFail() {
        handler.handleSessionEvent(.error(message: "Server error", status: 500))

        XCTAssertNotNil(mockDelegate.lastError)
        XCTAssertFalse(mockDelegate.shouldReturnToConfirmationCalled)
        XCTAssertNotNil(mockDelegate.lastFlowState)
    }

    // MARK: - sessionDidFail (DiscoverySessionSubscriber)

    func testSessionDidFailWithStreamInterruptedStartsPolling() {
        // Pre-seed some state
        handler.handleSessionEvent(.token("Partial content..."))

        handler.sessionDidFail(error: DiscoveryAnalysisError.streamInterrupted)

        XCTAssertTrue(handler.analysisState?.isPolling == true)
        XCTAssertFalse(handler.analysisState?.isStreaming ?? true)
    }

    func testSessionDidFailWithCreditsErrorCallsReturnToConfirmation() {
        handler.sessionDidFail(error: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Insufficient credits remaining"]))

        XCTAssertTrue(mockDelegate.shouldReturnToConfirmationCalled)
    }

    func testSessionDidFailWithGenericErrorCallsDelegate() {
        handler.sessionDidFail(error: NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network timeout"]))

        XCTAssertNotNil(mockDelegate.lastError)
    }

    // MARK: - sessionDidComplete (DiscoverySessionSubscriber)

    func testSessionDidCompleteWithSummaryCallsDelegate() {
        let summary = DiscoverySummary(
            id: 99,
            title: "Test Discovery",
            highlight: "A test.",
            capturedAt: Date()
        )

        handler.sessionDidComplete(discoveryId: 99, summary: summary)

        XCTAssertEqual(mockDelegate.completedDiscovery?.id, 99)
        XCTAssertEqual(handler.analysisState?.discoverySummary?.id, 99)
    }

    // MARK: - cancel()

    func testCancelClearsAllState() {
        handler.handleSessionEvent(.token("Some text"))

        handler.cancel()

        XCTAssertNil(handler.analysisState)
        XCTAssertNil(handler.pendingMedia)
        XCTAssertNil(handler.currentSessionId)
    }

    // MARK: - Static Helpers

    func testMessageIndicatesInsufficientCredits() {
        XCTAssertTrue(StreamingSessionHandler.messageIndicatesInsufficientCredits("Insufficient credits"))
        XCTAssertTrue(StreamingSessionHandler.messageIndicatesInsufficientCredits("No credits remaining"))
        XCTAssertTrue(StreamingSessionHandler.messageIndicatesInsufficientCredits("Your credit balance is zero"))
        XCTAssertFalse(StreamingSessionHandler.messageIndicatesInsufficientCredits("Server error"))
        XCTAssertFalse(StreamingSessionHandler.messageIndicatesInsufficientCredits("Network timeout"))
    }

    func testEndEventPublishesFlowState() {
        handler.handleSessionEvent(.token("Content"))
        handler.handleSessionEvent(.end)

        XCTAssertNotNil(mockDelegate.lastFlowState)
        if case .analyzing = mockDelegate.lastFlowState {
            // Expected
        } else {
            XCTFail("Expected .analyzing flow state, got \(String(describing: mockDelegate.lastFlowState))")
        }
    }
}

// MARK: - Test Doubles

@MainActor
private final class MockStreamingDelegate: StreamingSessionDelegate {
    var createdDiscoveryId: Int64?
    var completedDiscovery: DiscoverySummary?
    var lastError: DiscoveryCreationFlowViewModel.FlowError?
    var lastCreditBalance: Int?
    var lastFlowState: DiscoveryCreationFlowState?
    var showAudioModalCalled = false
    var showPollingFailedAlertCalled = false
    var shouldReturnToConfirmationCalled = false

    func streamingDidCreateDiscovery(_ discoveryId: Int64) {
        createdDiscoveryId = discoveryId
    }

    func streamingDidCompleteDiscovery(_ summary: DiscoverySummary) {
        completedDiscovery = summary
    }

    func streamingDidFail(_ error: DiscoveryCreationFlowViewModel.FlowError) {
        lastError = error
    }

    func streamingDidUpdateCreditBalance(_ balance: Int?) {
        lastCreditBalance = balance
    }

    func streamingDidChangeFlowState(_ state: DiscoveryCreationFlowState) {
        lastFlowState = state
    }

    func streamingShouldShowAudioModal() {
        showAudioModalCalled = true
    }

    func streamingShouldShowPollingFailedAlert() {
        showPollingFailedAlertCalled = true
    }

    func streamingShouldReturnToConfirmation() {
        shouldReturnToConfirmationCalled = true
    }
}

private struct StubHistoryRepo: DiscoveryHistoryRepository {
    func fetchRecentDiscoveries(limit: Int) async throws -> [DiscoverySummary] {
        []
    }
}

private struct StubCreditsRepo: DiscoveryCreditsRepository {
    let balance: Int
    func fetchCreditBalance() async throws -> Int {
        balance
    }
}
