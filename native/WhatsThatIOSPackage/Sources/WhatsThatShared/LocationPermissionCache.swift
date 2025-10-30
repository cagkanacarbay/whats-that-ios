import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

@MainActor
public final class LocationPermissionCache: ObservableObject {
    public static let shared = LocationPermissionCache()

    // nil means not yet refreshed for this app session
    @Published public private(set) var isGranted: Bool? = nil

    public var current: Bool? { isGranted }

    public func set(_ value: Bool) {
        isGranted = value
    }

    public func clear() {
        isGranted = nil
    }

    #if canImport(CoreLocation)
    public func refreshFromSystem() {
        let status = CLLocationManager().authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            isGranted = true
        default:
            isGranted = false
        }
        #if DEBUG
        print("[PermissionCache] Refreshed location permission: \(isGranted == true ? "granted" : "not granted")")
        #endif
    }
    #endif
}

