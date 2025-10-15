import Foundation

@MainActor
public protocol DiscoveryCaptureService: Sendable {
    func requestPermission(for type: DiscoveryCreationFlowType) async -> Bool
    func capturePhoto() async throws -> DiscoveryCapturedMedia
}

@MainActor
public protocol DiscoverySelectionService: Sendable {
    func requestPermission() async -> Bool
    func selectPhoto() async throws -> DiscoveryCapturedMedia
}

public protocol DiscoveryLocationService: Sendable {
    func startTrackingIfNeeded() async
    func stopTracking()
    func currentLocation() async -> DiscoveryLocation?
    func attachLocationMetadata(from media: DiscoveryCapturedMedia) async -> DiscoveryLocation?
}

public protocol DiscoveryCreditsRepository: Sendable {
    func fetchCreditBalance() async throws -> Int
}

public protocol DiscoveryHistoryRepository: Sendable {
    func fetchRecentDiscoveries(limit: Int) async throws -> [DiscoverySummary]
}

public protocol DiscoveryPushService: Sendable {
    func requestPushAuthorizationIfNeeded() async throws -> String?
}

public struct DiscoveryAnalysisPayload: Sendable, Equatable {
    public let base64Image: String
    public let location: DiscoveryLocation?
    public let customContext: String?
    public let pushToken: String?

    public init(
        base64Image: String,
        location: DiscoveryLocation? = nil,
        customContext: String? = nil,
        pushToken: String? = nil
    ) {
        self.base64Image = base64Image
        self.location = location
        self.customContext = customContext
        self.pushToken = pushToken
    }
}

public protocol DiscoveryAnalysisClient: Sendable {
    func startAnalysis(
        payload: DiscoveryAnalysisPayload,
        sessionId: UUID,
        cancellationHandler: @escaping @Sendable () async -> Void
    ) -> AsyncThrowingStream<DiscoveryAnalysisEvent, Error>
}
