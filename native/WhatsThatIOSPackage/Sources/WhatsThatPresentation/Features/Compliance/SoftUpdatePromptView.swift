import SwiftUI
import WhatsThatShared

struct SoftUpdatePromptView: View {
    let targetVersion: String
    let message: String?
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Text("🎉")
                .font(.system(size: 48))

            Text("New Version Available!")
                .font(.adaptiveSystem(size: 24, weight: .bold))
                .foregroundStyle(titleColor)

            Text("Version \(targetVersion)")
                .font(.adaptiveSystem(size: 16, weight: .medium))
                .foregroundStyle(bodyColor.opacity(0.7))

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

                Button("Maybe Later") {
                    onDismiss()
                }
                .font(.adaptiveSystem(size: 16, weight: .medium))
                .foregroundStyle(bodyColor.opacity(0.7))
            }
        }
        .padding(BrandSpacing.large)
        .frame(maxWidth: UIDevice.isIPad ? 400 : .infinity)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }
}
