#if os(iOS)
import CoreLocation
import Foundation
import UserNotifications

final class OnboardingPermissionsCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var locationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var locationManager: CLLocationManager?

    override init() {
        super.init()
        refreshLocationStatus()
        refreshNotificationStatus()
    }

    func requestLocationPermission() {
        DispatchQueue.main.async {
            let manager = CLLocationManager()
            manager.delegate = self
            self.locationManager = manager
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestNotificationPermission() {
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await Self.requestNotificationAuthorization(center: center)
            refreshNotificationStatus()
        }
    }

    func refreshNotificationStatus() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            Task { @MainActor in
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }

    func refreshLocationStatus() {
        let status = CLLocationManager().authorizationStatus
        Task { @MainActor in
            self.locationStatus = status
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.locationStatus = manager.authorizationStatus
        }
    }

    // MARK: - Helpers

    private static func requestNotificationAuthorization(center: UNUserNotificationCenter) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
#endif
