import SwiftUI
import WhatsThatShared

struct ForceUpdateBlockingView: View {
    let targetVersion: String
    let message: String?
    let isGraceExpired: Bool
    let onOpenAppStore: () -> Void
    let onCheckAgain: () async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isChecking = false
    @State private var lastCheckTime: Date?
    private let checkCooldown: TimeInterval = 60

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Spacer()

            Text("🔒")
                .font(.system(size: 64))

            Text("Update Required")
                .font(.adaptiveSystem(size: 28, weight: .bold))
                .foregroundStyle(titleColor)

            Text("A required update must be installed to continue using What's That?")
                .font(.adaptiveSystem(size: 16))
                .foregroundStyle(bodyColor)
                .multilineTextAlignment(.center)

            Text("Version \(targetVersion)")
                .font(.adaptiveSystem(size: 14, weight: .medium))
                .foregroundStyle(bodyColor.opacity(0.7))

            if let message, !message.isEmpty {
                Text(message)
                    .font(.adaptiveSystem(size: 14))
                    .foregroundStyle(bodyColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(BrandSpacing.medium)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer()

            VStack(spacing: BrandSpacing.medium) {
                BrandPrimaryButton(title: "Update Now") {
                    onOpenAppStore()
                }

                BrandSecondaryButton(
                    title: isChecking ? "Checking..." : "Check Again",
                    isLoading: isChecking
                ) {
                    Task { await handleCheckAgain() }
                }
                .disabled(isChecking)
            }

            Spacer()
        }
        .padding(.horizontal, BrandSpacing.large)
        .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)
    }

    private func handleCheckAgain() async {
        await MainActor.run { isChecking = true }

        let now = Date()
        let canCheck = lastCheckTime == nil || now.timeIntervalSince(lastCheckTime!) >= checkCooldown

        if canCheck {
            await MainActor.run { lastCheckTime = now }
            await onCheckAgain()
        } else {
            // Rate limited - show spinner briefly for UX
            try? await Task.sleep(for: .seconds(1))
        }

        await MainActor.run { isChecking = false }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
}
