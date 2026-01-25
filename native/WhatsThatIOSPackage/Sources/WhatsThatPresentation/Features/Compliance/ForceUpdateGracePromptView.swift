import SwiftUI
import WhatsThatShared

struct ForceUpdateGracePromptView: View {
    let targetVersion: String
    let daysRemaining: Int
    let message: String?
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Text("⚠️")
                .font(.system(size: 48))

            Text("Required Update")
                .font(.adaptiveSystem(size: 24, weight: .bold))
                .foregroundStyle(warningColor)

            Text("Version \(targetVersion) is required")
                .font(.adaptiveSystem(size: 16, weight: .medium))
                .foregroundStyle(bodyColor)

            Text("You have \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") to update before this becomes mandatory.")
                .font(.adaptiveSystem(size: 14))
                .foregroundStyle(bodyColor.opacity(0.8))
                .multilineTextAlignment(.center)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.adaptiveSystem(size: 14))
                    .foregroundStyle(bodyColor)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: BrandSpacing.small) {
                BrandPrimaryButton(title: "Update Now") {
                    onUpdate()
                }

                Button("Remind Me Later") {
                    onDismiss()
                }
                .font(.adaptiveSystem(size: 16, weight: .medium))
                .foregroundStyle(bodyColor.opacity(0.7))
            }
        }
        .padding(BrandSpacing.large)
        .frame(maxWidth: UIDevice.isIPad ? 400 : .infinity)
    }

    private var warningColor: Color {
        Color.orange
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }
}
