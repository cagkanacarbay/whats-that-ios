#if canImport(UserNotifications)
import Foundation
import UserNotifications
import WhatsThatDomain

public final class NativePushService: DiscoveryPushService {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestPushAuthorizationIfNeeded() async throws -> String? {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                return nil
            }
        case .denied:
            return nil
        case .authorized, .ephemeral, .provisional:
            break
        @unknown default:
            break
        }

        return nil
    }
}
#endif
