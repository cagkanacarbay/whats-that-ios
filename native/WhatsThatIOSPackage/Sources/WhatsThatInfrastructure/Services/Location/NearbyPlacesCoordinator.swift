import Foundation
import os
import WhatsThatDomain

public actor NearbyPlacesCoordinator {
    private let config: NearbyPlacesConfig
    private let cacheStore: NearbyPlacesCacheStore
    private let fetcher: NearbyPlacesFetching?
    private let logger = Logger(subsystem: "WhatsThatIOS", category: "NearbyPlacesCoordinator")

    private var latestSample: DiscoveryLocationSample?
    private var latestSnapshot: NearbyPlacesSnapshot?
    private var lastFetchDate: Date?
    private var lastFetchCoordinate: GeoCoordinate?
    private var isFetching = false

    public init(
        config: NearbyPlacesConfig,
        cacheStore: NearbyPlacesCacheStore,
        fetcher: NearbyPlacesFetching?
    ) {
        self.config = config
        self.cacheStore = cacheStore
        self.fetcher = fetcher
    }

    public func register(sample: DiscoveryLocationSample, preferImmediateFetch: Bool = false) async {
        let now = Date()
        var normalizedSample = sample

        if now.timeIntervalSince(sample.timestamp) > config.sampleStaleInterval {
            normalizedSample = DiscoveryLocationSample(
                id: sample.id,
                coordinate: sample.coordinate,
                timestamp: now,
                horizontalAccuracy: sample.horizontalAccuracy,
                source: sample.source
            )
        }

        latestSample = normalizedSample

        await resolveCachedSnapshot(for: normalizedSample, now: now)
        await maybeFetch(for: normalizedSample, now: now, preferImmediateFetch: preferImmediateFetch)
    }

    public func currentSelection(now: Date = Date()) async -> NearbyPlacesSelection? {
        guard let sample = latestSample else { return nil }

        if latestSnapshot == nil {
            await resolveCachedSnapshot(for: sample, now: now)
        }

        guard let snapshot = latestSnapshot else { return nil }
        let context = makeContext(snapshot: snapshot, sample: sample)
        return NearbyPlacesSelection(snapshot: snapshot, context: context)
    }

    public func reset() {
        latestSample = nil
        latestSnapshot = nil
        lastFetchCoordinate = nil
        lastFetchDate = nil
        isFetching = false
    }

    private func resolveCachedSnapshot(for sample: DiscoveryLocationSample, now: Date) async {
        if let cached = await cacheStore.bestSnapshot(
            for: sample.coordinate,
            within: config.distanceThresholdMeters,
            ttl: config.cacheTimeToLive,
            now: now
        ) {
            latestSnapshot = cached
        } else {
            latestSnapshot = nil
        }
    }

    private func maybeFetch(
        for sample: DiscoveryLocationSample,
        now: Date,
        preferImmediateFetch: Bool
    ) async {
        guard let fetcher else { return }
        guard isFetchEligible(for: sample, now: now, preferImmediateFetch: preferImmediateFetch) else {
            return
        }

        if isFetching { return }
        isFetching = true
        lastFetchDate = now
        lastFetchCoordinate = sample.coordinate
        let fetchRadius = self.config.fetchRadiusMeters
        logger.info("Fetching nearby places lat=\(sample.coordinate.latitude, privacy: .public) lon=\(sample.coordinate.longitude, privacy: .public) radius=\(fetchRadius, privacy: .public) source=\(sample.source.rawValue, privacy: .public)")

        Task {
            let radius = self.config.fetchRadiusMeters
            let maxEntries = self.config.maxCacheEntries
            let logger = self.logger
            do {
                let places = try await fetcher.fetchNearbyPlaces(
                    latitude: sample.coordinate.latitude,
                    longitude: sample.coordinate.longitude,
                    radius: radius
                )
                let snapshot = NearbyPlacesSnapshot(
                    centroid: sample.coordinate,
                    origin: sample.coordinate,
                    radiusMeters: radius,
                    fetchedAt: Date(),
                    places: places,
                    sourceSampleId: sample.id
                )

                await cacheStore.store(
                    snapshot: snapshot,
                    maxEntries: maxEntries
                )

                await updateAfterFetch(snapshot: snapshot, sample: sample)
                logger.info("Nearby places fetched count=\(places.count, privacy: .public) snapshotId=\(snapshot.id.uuidString, privacy: .public)")
            } catch {
                logger.error("Nearby places fetch failed: \(String(describing: error), privacy: .public)")
            }
            await self.finishFetch()
        }
    }

    private func finishFetch() async {
        isFetching = false
    }

    private func updateAfterFetch(snapshot: NearbyPlacesSnapshot, sample: DiscoveryLocationSample) async {
        latestSnapshot = snapshot
        lastFetchCoordinate = sample.coordinate
        lastFetchDate = Date()
    }

    private func isFetchEligible(
        for sample: DiscoveryLocationSample,
        now: Date,
        preferImmediateFetch: Bool
    ) -> Bool {
        // If we already have a cached snapshot selected for current coordinates, reuse it.
        if latestSnapshot != nil {
            return false
        }
        if let lastDate = lastFetchDate,
           now.timeIntervalSince(lastDate) < config.fetchDebounceInterval {
            if !preferImmediateFetch { return false }
        }

        if let lastCoordinate = lastFetchCoordinate {
            let distance = lastCoordinate.distance(to: sample.coordinate)
            if distance < config.distanceThresholdMeters && !preferImmediateFetch {
                return false
            }
        }

        // latestSnapshot check handled above; no additional gating needed here.

        return true
    }

    private func makeContext(
        snapshot: NearbyPlacesSnapshot,
        sample: DiscoveryLocationSample
    ) -> NearbyPlacesContext {
        let distance = snapshot.origin.distance(to: sample.coordinate)
        let accuracy = max(sample.horizontalAccuracy, 0)
        let summary = Self.summaryText(distance: distance, accuracy: accuracy)
        return NearbyPlacesContext(
            snapshotId: snapshot.id,
            distanceMeters: distance,
            horizontalAccuracyMeters: accuracy,
            distanceUncertaintyMeters: accuracy,
            summary: summary
        )
    }

    private static func summaryText(distance: Double, accuracy: Double) -> String {
        let distanceText = formattedMetric(distance)
        let accuracyText = formattedMetric(accuracy)
        return "User is \(distanceText) away (+/- \(accuracyText) accuracy) from cached nearby places fetched earlier."
    }

    private static func formattedMetric(_ meters: Double) -> String {
        let clamped = max(meters, 0)
        if clamped >= 1000 {
            let kilometres = (clamped / 100).rounded() / 10
            return String(format: "~%.1f km", kilometres)
        } else {
            let rounded = (clamped / 10).rounded() * 10
            return String(format: "~%.0f m", rounded)
        }
    }
}
