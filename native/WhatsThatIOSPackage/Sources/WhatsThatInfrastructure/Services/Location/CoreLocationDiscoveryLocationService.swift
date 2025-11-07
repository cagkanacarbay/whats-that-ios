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
    private var ephemeralFetchers: [UUID: EphemeralFetcher] = [:]

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

        // Minimal diagnostics to avoid heavy Core Location property reads on main thread
        #if DEBUG
        self.log("init(mainThread=\(Thread.isMainThread)) desired=\(manager.desiredAccuracy) distanceFilter=\(manager.distanceFilter) pauses=\(manager.pausesLocationUpdatesAutomatically)")
        #endif

    }

    public func startTrackingIfNeeded() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                Task { @MainActor in
                    await self.requestAuthorizationIfNeeded()
                    self.locationManager.desiredAccuracy = self.config.locationDesiredAccuracyMeters
                    self.locationManager.distanceFilter = self.config.locationDistanceFilterMeters
                    #if DEBUG
                    self.log("startTrackingIfNeeded(configured) desired=\(self.locationManager.desiredAccuracy) distanceFilter=\(self.locationManager.distanceFilter) pauses=\(self.locationManager.pausesLocationUpdatesAutomatically)")
                    #endif
                    continuation.resume()
                }
            }
        }

        queue.async { [weak self] in
            guard let self, !self.isUpdating else { return }
            self.isUpdating = true
            #if DEBUG
            self.log("startUpdatingLocation() isUpdating=true")
            #endif
            Task { @MainActor in self.locationManager.startUpdatingLocation() }
        }
    }

    public func stopTracking() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isUpdating = false
            #if DEBUG
            self.log("stopUpdatingLocation() isUpdating=false")
            #endif
            Task { @MainActor in self.locationManager.stopUpdatingLocation() }
        }
    }

    public func currentLocation() async -> DiscoveryLocation? {
        return await withCheckedContinuation { (continuation: CheckedContinuation<DiscoveryLocation?, Never>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                if let lastLocation = self.lastLocation {
                    let discoveryLocation = self.makeImmediateDiscoveryLocation(from: lastLocation)
                    continuation.resume(returning: discoveryLocation)
                } else {
                    let id = UUID()
                    #if DEBUG
                    self.log("currentLocation(requireFresh=false) queueing continuation id=\(id.uuidString) pending_before=\(self.pendingContinuations.count)")
                    #endif
                    self.pendingContinuations[id] = continuation
                    Task { @MainActor in
                        await self.requestAuthorizationIfNeeded()
                        self.log("[FF_EVENT] REQUEST id=\(id.uuidString) action=requestLocation() pending=\(self.pendingContinuations.count)")
                        self.locationManager.requestLocation()
                    }
                }
            }
        }
    }

    public func currentLocationIfRecent(maxAge: TimeInterval, maxAccuracyMeters: Double) async -> DiscoveryLocation? {
        return queue.sync { [weak self] in
            guard let self, let last = self.lastLocation else { return nil }
            let age = Date().timeIntervalSince(last.timestamp)
            let accuracy = max(last.horizontalAccuracy, 0)
            if age <= maxAge, accuracy <= maxAccuracyMeters {
                return self.makeImmediateDiscoveryLocation(from: last)
            }
            return nil
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
        return await withCheckedContinuation { (continuation: CheckedContinuation<DiscoveryLocation?, Never>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                // If we have a very recent last location, use it immediately to avoid spinner hangs
                let recentThreshold: TimeInterval = 15.0
                if let last = self.lastLocation, Date().timeIntervalSince(last.timestamp) < recentThreshold {
                    let thresholdStr = Int(recentThreshold)
                    self.log("Fresh required but last fix is recent (<\(thresholdStr)s); returning last-known")
                    let discovery = self.makeImmediateDiscoveryLocation(from: last)
                    continuation.resume(returning: discovery)
                    return
                }

                let id = UUID()
                #if DEBUG
                self.log("currentLocation(requireFresh=true) queueing continuation id=\(id.uuidString) pending_before=\(self.pendingContinuations.count) isUpdating=\(self.isUpdating)")
                #endif
                self.pendingContinuations[id] = continuation
                // Kick off a request for a fresh one-shot location
                Task { @MainActor in
                    await self.requestAuthorizationIfNeeded()
                    self.log("[FF_EVENT] REQUEST id=\(id.uuidString) action=requestLocation() pending=\(self.pendingContinuations.count)")
                    self.locationManager.requestLocation()
                }
                // Add a timeout fallback to prevent indefinite hangs
                let timeoutSeconds: TimeInterval = 15.0
                Task.detached { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    guard let self else { return }
                    #if DEBUG
                    self.log("[FF_EVENT] TIMEOUT_CHECK id=\(id.uuidString) pending_now=\(self.pendingContinuations[id] != nil) total_pending=\(self.pendingContinuations.count)")
                    #endif
                    self.queue.async { [weak self] in
                        guard let self else { return }
                        if let pending = self.pendingContinuations.removeValue(forKey: id) {
                            if let last = self.lastLocation {
                                self.log("[FF_EVENT] TIMEOUT_FALLBACK id=\(id.uuidString) timeout=\(timeoutSeconds)s used=last_known lat=\(last.coordinate.latitude) lon=\(last.coordinate.longitude)")
                                let discovery = self.makeImmediateDiscoveryLocation(from: last)
                                pending.resume(returning: discovery)
                            } else {
                                self.log("[FF_EVENT] TIMEOUT_NO_LAST id=\(id.uuidString) timeout=\(timeoutSeconds)s used=nil")
                                pending.resume(returning: nil)
                            }
                        }
                    }
                }
            }
        }
    }

    public func currentLocationStrictFreshEphemeral(timeout: TimeInterval = 30.0) async -> DiscoveryLocation? {
        await withCheckedContinuation { (continuation: CheckedContinuation<DiscoveryLocation?, Never>) in
            Task { @MainActor in
                let id = UUID()
                let fetcher = EphemeralFetcher(id: id, timeout: timeout) { [weak self] result in
                    guard let self else { return }
                    self.queue.async { [weak self] in
                        guard let self else { return }
                        _ = self.ephemeralFetchers.removeValue(forKey: id)
                    }
                    switch result {
                    case .success(let location):
                        continuation.resume(returning: self.makeImmediateDiscoveryLocation(from: location))
                    case .failure:
                        continuation.resume(returning: nil)
                    }
                }
                fetcher.start()
                self.queue.async { [weak self] in
                    self?.ephemeralFetchers[id] = fetcher
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
        // Build a confirm-stage sample (prefer immediate fetch) and wait up to configured timeout.
        let confirmTimeout = config.confirmStageFetchTimeout
        let deadline = Date().addingTimeInterval(confirmTimeout)

        var confirmSample: DiscoveryLocationSample?
        if let location {
            print("[Confirm][Nearby] Coordinates available at confirm stage (EXIF): lat=\(location.latitude), lon=\(location.longitude)")
            confirmSample = DiscoveryLocationSample(
                coordinate: GeoCoordinate(latitude: location.latitude, longitude: location.longitude),
                timestamp: Date(),
                horizontalAccuracy: config.locationDesiredAccuracyMeters,
                source: .exif
            )
        } else if let last = readLastLocation() {
            print("[Confirm][Nearby] Using last-known coordinates at confirm stage: lat=\(last.coordinate.latitude), lon=\(last.coordinate.longitude)")
            confirmSample = makeSample(from: last, source: .live)
        }

        if let sample = confirmSample {
            print("[Confirm][Nearby] Checking cache for lat=\(sample.coordinate.latitude), lon=\(sample.coordinate.longitude), reuseDistance=\(config.distanceThresholdMeters)m")
            await coordinator.register(sample: sample, preferImmediateFetch: true)
        }

        if let selection = await coordinator.currentSelection() { return selection }

        // Poll for nearby selection; if a fetch fails, re-trigger register with preferImmediateFetch
        // periodically (no empty snapshot caching, bounded by confirmTimeout).
        var lastRefetch = Date.distantPast
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let selection = await coordinator.currentSelection() { return selection }
            if let sample = confirmSample, Date().timeIntervalSince(lastRefetch) >= 1.0 {
                await coordinator.register(sample: sample, preferImmediateFetch: true)
                lastRefetch = Date()
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

    public func debugLogNearbyState(current: DiscoveryLocation?) async {
        // verbose confirm-nearby logging removed
    }

    public func listNearbyCache() async -> [NearbyPlacesSnapshot] {
        await cacheStore.allSnapshots()
    }

    public func clearNearbyCache() async {
        await cacheStore.clearAll()
    }

    @MainActor
    private func requestAuthorizationIfNeeded() async {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
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
            if !self.pendingContinuations.isEmpty {
                self.log("[FF_EVENT] DELIVERED_BEFORE_TIMEOUT pending_count=\(self.pendingContinuations.count) lat=\(latest.coordinate.latitude) lon=\(latest.coordinate.longitude)")
            }
            let continuations = self.pendingContinuations
            self.pendingContinuations.removeAll()
            for (_, cont) in continuations {
                cont.resume(returning: discoveryLocation)
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Log error details for diagnostics; currentLocation handles fallback/timeout.
        let nsError = error as NSError
        var codeDescription = "code=\(nsError.code)"
        if nsError.domain == (kCLErrorDomain as String) {
            if let clCode = CLError.Code(rawValue: nsError.code) {
                codeDescription = "code=\(clCode.rawValue) (\(clCode))"
            }
        }
        self.log("[FF_EVENT] REQUEST_FAILED domain=\(nsError.domain) \(codeDescription) localized=\(nsError.localizedDescription)")
        // Intentionally do not retry here; we're only increasing visibility to understand why fresh fixes fail
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

#if canImport(CoreLocation)
private final class EphemeralFetcher: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let id: UUID
    private let timeout: TimeInterval
    private let completion: (Result<CLLocation, Error>) -> Void
    private let manager: CLLocationManager
    private var finished = false

    init(id: UUID, timeout: TimeInterval, completion: @escaping (Result<CLLocation, Error>) -> Void) {
        self.id = id
        self.timeout = timeout
        self.completion = completion
        self.manager = CLLocationManager()
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        if #available(iOS 11.0, *) {
            manager.showsBackgroundLocationIndicator = false
        }
    }

    func start() {
        // If permission undetermined, request it; otherwise request a one-shot fix
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            manager.requestLocation()
        }

        // Timeout guard
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
            self.finish(nil)
        }
    }

    private func finish(_ location: CLLocation?) {
        guard !finished else { return }
        finished = true
        if let location {
            completion(.success(location))
        } else {
            completion(.failure(NSError(domain: "EphemeralFetcher", code: -1)))
        }
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let last = locations.last {
            finish(last)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Do not finish immediately on unknown errors; allow timeout to give the system a chance.
        let nsError = error as NSError
        if nsError.domain == kCLErrorDomain as String, nsError.code == CLError.locationUnknown.rawValue {
            return
        }
        finish(nil)
    }
}
#endif
