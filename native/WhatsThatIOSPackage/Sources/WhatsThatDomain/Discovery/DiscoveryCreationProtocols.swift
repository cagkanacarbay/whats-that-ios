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
    /// Returns a last-known location only if it is recent and accurate per thresholds.
    func currentLocationIfRecent(maxAge: TimeInterval, maxAccuracyMeters: Double) async -> DiscoveryLocation?
    /// Returns app-level location permission status.
    func isPermissionGranted() async -> Bool
    /// Explicitly request location authorization. Call this only when design specifies
    /// permission should be requested (e.g., on 2nd camera use per design doc).
    func requestLocationAuthorization() async
    /// Optionally request a fresh location fix, avoiding immediate last-known returns when true.
    func currentLocation(requireFresh: Bool) async -> DiscoveryLocation?
    /// Requests a fresh, high-accuracy fix using a short-lived, dedicated CLLocationManager.
    /// Returns when a new sample arrives or the timeout elapses. Does not block UI flow.
    func currentLocationStrictFreshEphemeral(timeout: TimeInterval) async -> DiscoveryLocation?
    func attachLocationMetadata(from media: DiscoveryCapturedMedia) async -> DiscoveryLocation?
    func prepareNearbyPlaces(for location: DiscoveryLocation?) async -> NearbyPlacesSelection?
    func registerMediaLocation(_ location: DiscoveryLocation) async
    /// Debug logging helper to inspect cache content and current selection.
    func debugLogNearbyState(current: DiscoveryLocation?) async
    /// Returns all cached nearby places snapshots (dev/QA tooling).
    func listNearbyCache() async -> [NearbyPlacesSnapshot]
    /// Clears cached nearby places snapshots (dev/QA tooling).
    func clearNearbyCache() async
}

public extension DiscoveryLocationService {
    func isPermissionGranted() async -> Bool { false }
    func requestLocationAuthorization() async {}
    func currentLocationIfRecent(maxAge _: TimeInterval, maxAccuracyMeters _: Double) async -> DiscoveryLocation? { nil }
    func currentLocation(requireFresh: Bool) async -> DiscoveryLocation? {
        await currentLocation()
    }
    func currentLocationStrictFreshEphemeral(timeout _: TimeInterval) async -> DiscoveryLocation? { nil }
    func debugLogNearbyState(current _: DiscoveryLocation?) async {}
    func listNearbyCache() async -> [NearbyPlacesSnapshot] { [] }
    func clearNearbyCache() async {}
}

public protocol DiscoveryCreditsRepository: Sendable {
    func fetchCreditBalance() async throws -> Int
}

public protocol DiscoveryHistoryRepository: Sendable {
    func fetchRecentDiscoveries(limit: Int) async throws -> [DiscoverySummary]
}

public protocol DiscoveryPushService: Sendable {
    func requestPushAuthorizationIfNeeded() async throws -> String?
    /// Returns the push token if notifications are already authorized, without requesting permission.
    func getPushTokenIfAuthorized() async throws -> String?
}

public extension DiscoveryPushService {
    func getPushTokenIfAuthorized() async throws -> String? { nil }
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
