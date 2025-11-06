import Foundation

public struct NearbyPlacesConfig: Equatable, Sendable {
    public let fetchRadiusMeters: Double
    public let distanceThresholdMeters: Double
    public let fetchDebounceInterval: TimeInterval
    public let cacheTimeToLive: TimeInterval
    public let maxCacheEntries: Int
    public let locationDistanceFilterMeters: Double
    public let locationDesiredAccuracyMeters: Double
    public let sampleStaleInterval: TimeInterval
    public let confirmStageFetchTimeout: TimeInterval

    public init(
        fetchRadiusMeters: Double,
        distanceThresholdMeters: Double,
        fetchDebounceInterval: TimeInterval,
        cacheTimeToLive: TimeInterval,
        maxCacheEntries: Int,
        locationDistanceFilterMeters: Double,
        locationDesiredAccuracyMeters: Double,
        sampleStaleInterval: TimeInterval,
        confirmStageFetchTimeout: TimeInterval
    ) {
        self.fetchRadiusMeters = fetchRadiusMeters
        self.distanceThresholdMeters = distanceThresholdMeters
        self.fetchDebounceInterval = fetchDebounceInterval
        self.cacheTimeToLive = cacheTimeToLive
        self.maxCacheEntries = maxCacheEntries
        self.locationDistanceFilterMeters = locationDistanceFilterMeters
        self.locationDesiredAccuracyMeters = locationDesiredAccuracyMeters
        self.sampleStaleInterval = sampleStaleInterval
        self.confirmStageFetchTimeout = confirmStageFetchTimeout
    }
}

public extension NearbyPlacesConfig {
    static let `default` = NearbyPlacesConfig(
        fetchRadiusMeters: 500,
        distanceThresholdMeters: 250,
        fetchDebounceInterval: 30,
        cacheTimeToLive: 7 * 24 * 60 * 60,
        maxCacheEntries: 50,
        locationDistanceFilterMeters: 100,
        locationDesiredAccuracyMeters: 50,
        sampleStaleInterval: 15 * 60,
        confirmStageFetchTimeout: 15
    )
}
