import SwiftUI
import WhatsThatShared

struct VersionUpgradeBadge: View {
    let currentVersion: String
    let targetVersion: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: BrandSpacing.medium) {
            versionPill(version: currentVersion, label: "Current", isTarget: false)

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(arrowColor)

            versionPill(version: targetVersion, label: "Available", isTarget: true)
        }
        .padding(.horizontal, BrandSpacing.medium)
        .padding(.vertical, BrandSpacing.small)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: BrandCornerRadius.medium))
    }

    @ViewBuilder
    private func versionPill(version: String, label: String, isTarget: Bool) -> some View {
        VStack(spacing: 4) {
            Text(version)
                .font(.adaptiveSystem(size: 16, weight: .semibold))
                .foregroundStyle(isTarget ? targetVersionColor : currentVersionColor)
                .padding(.horizontal, BrandSpacing.small + 4)
                .padding(.vertical, 6)
                .background(isTarget ? targetPillBackground : currentPillBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(label)
                .font(.adaptiveSystem(size: 11, weight: .medium))
                .foregroundStyle(labelColor)
        }
    }

    private var currentVersionColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : BrandColors.Light.bodyText
    }

    private var targetVersionColor: Color {
        Color.white
    }

    private var currentPillBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }

    private var targetPillBackground: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }

    private var arrowColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.5) : BrandColors.Light.bodyText.opacity(0.5)
    }

    private var labelColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.5) : BrandColors.Light.bodyText.opacity(0.6)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
}

#Preview("Light Mode") {
    VersionUpgradeBadge(currentVersion: "1.0.3", targetVersion: "1.0.6")
        .padding()
        .background(Color.white)
}

#Preview("Dark Mode") {
    VersionUpgradeBadge(currentVersion: "1.0.3", targetVersion: "1.0.6")
        .padding()
        .background(BrandColors.Dark.background)
        .preferredColorScheme(.dark)
}
