import SwiftUI
import UIKit
import WhatsThatShared

struct OnboardingPermissionsSection: View {
    @ObservedObject var permissions: OnboardingPermissionsCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            Text("Quick Permissions")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(titleColor)

            VStack(alignment: .leading, spacing: BrandSpacing.small) {
                PermissionRow(
                    title: "Location",
                    description: "Enable richer, nearby context in your discoveries.",
                    status: locationStatusText,
                    actionTitle: locationActionTitle,
                    action: locationAction()
                )

                PermissionRow(
                    title: "Notifications",
                    description: "Get a heads up when new stories are ready.",
                    status: notificationStatusText,
                    actionTitle: notificationActionTitle,
                    action: notificationAction()
                )
            }
            .padding()
            .background(cardBackground)
            .cornerRadius(BrandCornerRadius.medium)
            .overlay {
                RoundedRectangle(cornerRadius: BrandCornerRadius.medium)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var borderColor: Color {
        colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
    }

    private var cardBackground: Color {
        colorScheme == .dark ? BrandColors.Dark.secondaryAction.opacity(0.5) : BrandColors.Light.secondaryAction.opacity(0.6)
    }

    private var locationStatusText: String {
        switch permissions.locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Enabled"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    private var notificationStatusText: String {
        switch permissions.notificationStatus {
        case .authorized, .provisional:
            return "Enabled"
        case .denied:
            return "Denied"
        case .ephemeral:
            return "Temporarily enabled"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    private var locationActionTitle: String? {
        switch permissions.locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return nil
        case .denied:
            return "Open Settings"
        default:
            return "Enable Location"
        }
    }

    private func locationAction() -> (() -> Void)? {
        switch permissions.locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return nil
        case .denied:
            return { openAppSettings() }
        default:
            return { permissions.requestLocationPermission() }
        }
    }

    private var notificationActionTitle: String? {
        switch permissions.notificationStatus {
        case .authorized, .provisional:
            return nil
        case .denied:
            return "Open Settings"
        default:
            return "Enable Notifications"
        }
    }

    private func notificationAction() -> (() -> Void)? {
        switch permissions.notificationStatus {
        case .authorized, .provisional:
            return nil
        case .denied:
            return { openAppSettings() }
        default:
            return { permissions.requestNotificationPermission() }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private struct PermissionRow: View {
        let title: String
        let description: String
        let status: String
        let actionTitle: String?
        let action: (() -> Void)?

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(status)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(bodyColor)

                if let actionTitle, let action {
                    BrandSecondaryButton(title: actionTitle, action: action)
                }
            }
        }

        private var bodyColor: Color {
            colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
        }

        private var statusColor: Color {
            colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
        }
    }
}

