#if canImport(CoreLocation)
@preconcurrency import CoreLocation
import Foundation
import WhatsThatDomain

public final class CoreLocationDiscoveryLocationService: NSObject, DiscoveryLocationService, @unchecked Sendable {
    private let locationManager: CLLocationManager
    private let geocoder: CLGeocoder
    private let queue = DispatchQueue(label: "com.whatsthat.discovery.location", qos: .userInitiated)
    private var lastLocation: CLLocation?
    private var isUpdating = false
    private var pendingContinuations: [UUID: CheckedContinuation<DiscoveryLocation?, Never>] = [:]

    private let config: NearbyPlacesConfig
    private let cacheStore: NearbyPlacesCacheStore
    private let coordinator: NearbyPlacesCoordinator

    public init(
        configuration: NearbyPlacesConfig = .default,
        cacheDirectory: URL? = nil,
        nearbyPlacesFetcher: NearbyPlacesFetching? = nil
    ) {
        self.config = configuration

        let manager = CLLocationManager()
        self.locationManager = manager
        self.geocoder = CLGeocoder()

        let cachesDirectory = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        self.cacheStore = NearbyPlacesCacheStore(cacheDirectory: cachesDirectory)
        self.coordinator = NearbyPlacesCoordinator(
            config: configuration,
            cacheStore: cacheStore,
            fetcher: nearbyPlacesFetcher
        )

        super.init()

        manager.delegate = self
        manager.desiredAccuracy = configuration.locationDesiredAccuracyMeters
        manager.distanceFilter = configuration.locationDistanceFilterMeters
        manager.pausesLocationUpdatesAutomatically = true

        log("Init: desiredAccuracy=\(configuration.locationDesiredAccuracyMeters), distanceFilter=\(configuration.locationDistanceFilterMeters)")
    }

    public func startTrackingIfNeeded() async {
        log("startTrackingIfNeeded() invoked")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                Task { @MainActor in
                    self.log("Requesting authorization if needed")
                    await self.requestAuthorizationIfNeeded()
                    let auth = self.locationManager.authorizationStatus
                    self.log("Authorization status after request: \(Self.describeAuthorization(auth)))")
                    self.locationManager.desiredAccuracy = self.config.locationDesiredAccuracyMeters
                    self.locationManager.distanceFilter = self.config.locationDistanceFilterMeters
                    continuation.resume()
                }
            }
        }

        queue.async { [weak self] in
            guard let self, !self.isUpdating else { return }
            self.isUpdating = true
            Task { @MainActor in
                self.log("Starting continuous location updates (startUpdatingLocation)")
                self.locationManager.startUpdatingLocation()
            }
        }
    }

    public func stopTracking() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isUpdating = false
            Task { @MainActor in
                self.log("Stopping continuous location updates (stopUpdatingLocation)")
                self.locationManager.stopUpdatingLocation()
            }
        }
    }

    public func currentLocation() async -> DiscoveryLocation? {
        log("currentLocation() called")
        return await withCheckedContinuation { (continuation: CheckedContinuation<DiscoveryLocation?, Never>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                if let lastLocation = self.lastLocation {
                    self.log("Returning last known location immediately: (\(lastLocation.coordinate.latitude), \(lastLocation.coordinate.longitude))")
                    let discoveryLocation = self.makeImmediateDiscoveryLocation(from: lastLocation)
                    continuation.resume(returning: discoveryLocation)
                } else {
                    self.log("No last location; requesting one-shot location update")
                    let id = UUID()
                    self.pendingContinuations[id] = continuation
                    Task { @MainActor in
                        await self.requestAuthorizationIfNeeded()
                        self.log("Requesting one-shot location (requestLocation)")
                        self.locationManager.requestLocation()
                    }
                }
            }
        }
    }

    public func isPermissionGranted() async -> Bool {
        await MainActor.run {
            let enabled = CLLocationManager.locationServicesEnabled()
            self.log("isPermissionGranted? locationServicesEnabled=\(enabled)")
            switch locationManager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.log("Permission granted")
                return true
            default:
                self.log("Permission not granted (status=\(Self.describeAuthorization(locationManager.authorizationStatus)))")
                return false
            }
        }
    }

    public func currentLocation(requireFresh: Bool) async -> DiscoveryLocation? {
        if !requireFresh {
            return await currentLocation()
        }
        log("currentLocation(requireFresh: true) called")
        return await withCheckedContinuation { (continuation: CheckedContinuation<DiscoveryLocation?, Never>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                // If we have a very recent last location (<= 15s), use it immediately to avoid spinner hangs
                if let last = self.lastLocation, Date().timeIntervalSince(last.timestamp) < 15 {
                    self.log("Fresh required but last fix is recent (<5s); returning last-known")
                    let discovery = self.makeImmediateDiscoveryLocation(from: last)
                    continuation.resume(returning: discovery)
                    return
                }

                let id = UUID()
                self.pendingContinuations[id] = continuation
                // Kick off a request for a fresh one-shot location
                Task { @MainActor in
                    await self.requestAuthorizationIfNeeded()
                    self.log("Requesting fresh location (requestLocation)")
                    self.locationManager.requestLocation()
                }
                // Add a timeout fallback to prevent indefinite hangs
                let timeoutSeconds: TimeInterval = 2.0
                Task.detached { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    guard let self else { return }
                    self.queue.async { [weak self] in
                        guard let self else { return }
                        if let pending = self.pendingContinuations.removeValue(forKey: id) {
                            if let last = self.lastLocation {
                                self.log("Fresh fix timeout (\(timeoutSeconds)s); returning last-known")
                                let discovery = self.makeImmediateDiscoveryLocation(from: last)
                                pending.resume(returning: discovery)
                            } else {
                                self.log("Fresh fix timeout (\(timeoutSeconds)s); no last-known available")
                                pending.resume(returning: nil)
                            }
                        }
                    }
                }
            }
        }
    }

    public func attachLocationMetadata(from media: DiscoveryCapturedMedia) async -> DiscoveryLocation? {
        if let location = media.location {
            await registerMediaLocation(location)
            return location
        }

        guard let location = await currentLocation() else {
            return nil
        }
        await registerMediaLocation(location)
        return location
    }

    public func prepareNearbyPlaces(for location: DiscoveryLocation?) async -> NearbyPlacesSelection? {
        if let location {
            await registerMediaLocation(location)
            if let selection = await coordinator.currentSelection() {
                return selection
            }
        } else if let lastLocation = readLastLocation() {
            let sample = makeSample(from: lastLocation, source: .live)
            await coordinator.register(sample: sample)
        }

        if let selection = await coordinator.currentSelection() {
            return selection
        }

        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let selection = await coordinator.currentSelection() {
                return selection
            }
        }

        return nil
    }

    public func registerMediaLocation(_ location: DiscoveryLocation) async {
        let sample = DiscoveryLocationSample(
            coordinate: GeoCoordinate(
                latitude: location.latitude,
                longitude: location.longitude
            ),
            timestamp: Date(),
            horizontalAccuracy: config.locationDesiredAccuracyMeters,
            source: .exif
        )
        await coordinator.register(sample: sample, preferImmediateFetch: true)
    }

    @MainActor
    private func requestAuthorizationIfNeeded() async {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            log("Authorization not determined; requesting when-in-use")
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            log("Authorization restricted/denied; not requesting")
            break
        case .authorizedAlways, .authorizedWhenInUse:
            log("Authorization already granted")
            break
        @unknown default:
            break
        }
    }

    private func makeImmediateDiscoveryLocation(from location: CLLocation) -> DiscoveryLocation {
        DiscoveryLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            country: nil,
            locality: nil,
            streetName: nil,
            closestPlace: nil
        )
    }

    private func makeSample(from location: CLLocation, source: LocationSampleSource) -> DiscoveryLocationSample {
        DiscoveryLocationSample(
            coordinate: GeoCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ),
            timestamp: location.timestamp,
            horizontalAccuracy: max(location.horizontalAccuracy, 0),
            source: source
        )
    }

    private func readLastLocation() -> CLLocation? {
        queue.sync { lastLocation }
    }

    private func makeDiscoveryLocation(from location: CLLocation) async -> DiscoveryLocation {
        let placemark = try? await geocoder.reverseGeocodeLocation(location).first
        return DiscoveryLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            country: placemark?.country,
            locality: placemark?.locality,
            streetName: placemark?.thoroughfare,
            closestPlace: placemark?.name
        )
    }
}

extension CoreLocationDiscoveryLocationService: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.lastLocation = latest
            let sample = self.makeSample(from: latest, source: .live)
            Task {
                await self.coordinator.register(sample: sample)
            }
            // Resume any pending continuations immediately with coordinate-only info.
            let discoveryLocation = self.makeImmediateDiscoveryLocation(from: latest)
            self.log("didUpdateLocations: count=\(locations.count), latest=(\(latest.coordinate.latitude), \(latest.coordinate.longitude)), pending=\(self.pendingContinuations.count)")
            let continuations = self.pendingContinuations
            self.pendingContinuations.removeAll()
            for (_, cont) in continuations {
                cont.resume(returning: discoveryLocation)
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log("didFailWithError: \(error.localizedDescription)")
        // Swallow errors; currentLocation will handle fallback.
    }
}
#endif

// MARK: - Logging
#if canImport(CoreLocation)
extension CoreLocationDiscoveryLocationService {
    private static func describeAuthorization(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default: return "unknown"
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[LocationService] \(message)")
        #endif
    }
}
#endif
