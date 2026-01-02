import SwiftUI
import UIKit
import WhatsThatShared

struct DiscoveriesHeaderView: View {
    let opacity: Double
    let metrics: DiscoveriesHeaderMetrics
    let backgroundColor: Color
    let onSignOut: () -> Void
    let onSettings: (() -> Void)?
    /// When true, the settings icon shows filled with the tab selected color (orange)
    var isSettingsSelected: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: metrics.headerStackSpacing) {
            HStack {
                Text("My Discoveries")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(headerTitleColor)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                settingsButton
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.top, metrics.headerTopPadding)

            // Replaces the hard divider with a soft shadow/gradient
            // that subtly separates the header from the grid.
            Color.clear
                .frame(height: 1)
        }
        .background(
            LinearGradient(
                colors: [
                    backgroundColor,
                    backgroundColor.opacity(0.92),
                    backgroundColor.opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            // Always-on hairline shadow that spans full width (no side gaps)
            LinearGradient(
                colors: [hairlineColor, Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: hairlineThickness)
            .allowsHitTesting(false)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HeaderHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .opacity(opacity)
    }

    @ViewBuilder
    private var settingsButton: some View {
        if let onSettings {
            Button {
                onSettings()
            } label: {
                settingsIcon
                    .accessibilityLabel("Settings")
            }
            .contextMenu {
                Button("Sign out", role: .destructive) {
                    onSignOut()
                }
            }
        } else {
            Menu {
                Button("Sign out", role: .destructive) {
                    onSignOut()
                }
            } label: {
                settingsIcon
                    .accessibilityLabel("Options")
            }
        }
    }

    /// Settings gear icon - always uses gearshape.fill, color matches tab bar (orange when selected, gray when not)
    private var settingsIcon: some View {
        let tabSelectedColor = colorScheme == .dark ? BrandColors.logo : BrandColors.Light.tabSelected
        // Gray matches the default tab bar unselected color
        let unselectedColor = Color.gray
        let iconColor = isSettingsSelected ? tabSelectedColor : unselectedColor

        return Image(systemName: "gearshape.fill")
            .font(.system(size: 22, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(iconColor)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private var headerTitleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var hairlineColor: Color {
        // Slightly stronger contrast per request
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.10)
    }

    private var hairlineThickness: CGFloat {
        let scale = UIScreen.main.scale
        // 2 device pixels for a slightly stronger separation
        return scale > 0 ? (2 / scale) : 2
    }
}
