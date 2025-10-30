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
    /// Returns app-level location permission status.
    func isPermissionGranted() async -> Bool
    /// Optionally request a fresh location fix, avoiding immediate last-known returns when true.
    func currentLocation(requireFresh: Bool) async -> DiscoveryLocation?
    func attachLocationMetadata(from media: DiscoveryCapturedMedia) async -> DiscoveryLocation?
    func prepareNearbyPlaces(for location: DiscoveryLocation?) async -> NearbyPlacesSelection?
    func registerMediaLocation(_ location: DiscoveryLocation) async
}

public extension DiscoveryLocationService {
    func isPermissionGranted() async -> Bool { false }
    func currentLocation(requireFresh: Bool) async -> DiscoveryLocation? {
        await currentLocation()
    }
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
    public let nearbyPlaces: [NearbyPlace]?
    public let nearbyPlacesContext: NearbyPlacesContext?

    public init(
        base64Image: String,
        location: DiscoveryLocation? = nil,
        customContext: String? = nil,
        pushToken: String? = nil,
        nearbyPlaces: [NearbyPlace]? = nil,
        nearbyPlacesContext: NearbyPlacesContext? = nil
    ) {
        self.base64Image = base64Image
        self.location = location
        self.customContext = customContext
        self.pushToken = pushToken
        self.nearbyPlaces = nearbyPlaces
        self.nearbyPlacesContext = nearbyPlacesContext
    }
}

public protocol DiscoveryAnalysisClient: Sendable {
    func startAnalysis(
        payload: DiscoveryAnalysisPayload,
        sessionId: UUID,
        cancellationHandler: @escaping @Sendable () async -> Void
    ) -> AsyncThrowingStream<DiscoveryAnalysisEvent, Error>
}
