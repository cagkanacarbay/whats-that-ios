#if canImport(CoreLocation)
@preconcurrency import CoreLocation
import Foundation
import WhatsThatDomain

public final class CoreLocationDiscoveryLocationService: NSObject, DiscoveryLocationService, @unchecked Sendable {
    private let locationManager: CLLocationManager
    private let geocoder: CLGeocoder
    private var lastLocation: CLLocation?
    private var isUpdating = false
    private let queue = DispatchQueue(label: "com.whatsthat.discovery.location")

    public override init() {
        self.locationManager = CLLocationManager()
        self.geocoder = CLGeocoder()
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public func startTrackingIfNeeded() async {
        await withCheckedContinuation { continuation in
            queue.async {
                Task { @MainActor in
                    await self.requestAuthorizationIfNeeded()
                    continuation.resume()
                }
            }
        }

        queue.async { [weak self] in
            guard let self else { return }
            if self.isUpdating { return }
            self.isUpdating = true
            Task { @MainActor in
                self.locationManager.startUpdatingLocation()
            }
        }
    }

    public func stopTracking() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isUpdating = false
            Task { @MainActor in
                self.locationManager.stopUpdatingLocation()
            }
        }
    }

    public func currentLocation() async -> DiscoveryLocation? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                if let lastLocation = self.lastLocation {
                    Task {
                        let discoveryLocation = await self.makeDiscoveryLocation(from: lastLocation)
                        continuation.resume(returning: discoveryLocation)
                    }
                } else {
                    Task { @MainActor in
                        await self.requestAuthorizationIfNeeded()
                        self.locationManager.requestLocation()
                    }

                    queue.asyncAfter(deadline: .now() + 3) { [weak self] in
                        guard let self else {
                            continuation.resume(returning: nil)
                            return
                        }
                        if let lastLocation = self.lastLocation {
                            Task {
                                let discoveryLocation = await self.makeDiscoveryLocation(from: lastLocation)
                                continuation.resume(returning: discoveryLocation)
                            }
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }

    public func attachLocationMetadata(from media: DiscoveryCapturedMedia) async -> DiscoveryLocation? {
        // When media already embeds a location (from photo EXIF), prefer that.
        if let location = media.location {
            return location
        }
        return await currentLocation()
    }

    @MainActor
    private func requestAuthorizationIfNeeded() async {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            break
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            break
        }
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
            self?.lastLocation = latest
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Swallow errors; currentLocation will handle fallback.
    }
}
#endif
