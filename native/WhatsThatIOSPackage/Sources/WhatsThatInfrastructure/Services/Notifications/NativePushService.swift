import Foundation
@preconcurrency import UserNotifications
import WhatsThatDomain
#if canImport(UIKit)
import UIKit
#endif

public final class NativePushService: DiscoveryPushService, @unchecked Sendable {
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

        if let existing = await NativePushTokenStore.shared.currentToken() {
            return existing
        }

        await registerForRemoteNotifications()
        return await NativePushTokenStore.shared.waitForToken()
    }

    @MainActor
    private func registerForRemoteNotifications() {
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
}
