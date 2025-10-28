import SwiftUI
import UIKit
import WhatsThatShared

struct DiscoveriesHeaderView: View {
    let opacity: Double
    let metrics: DiscoveriesHeaderMetrics
    let backgroundColor: Color
    let onSignOut: () -> Void
    let onSettings: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: metrics.headerStackSpacing) {
            HStack {
                Text("My Discoveries")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(headerTitleColor)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                settingsMenu
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
    private var settingsMenu: some View {
        if let onSettings {
            Menu {
                Button("Sign out", role: .destructive) {
                    onSignOut()
                }
            } label: {
                menuIcon
                    .accessibilityLabel("Settings")
            } primaryAction: {
                onSettings()
            }
        } else {
            Menu {
                Button("Sign out", role: .destructive) {
                    onSignOut()
                }
            } label: {
                menuIcon
                    .accessibilityLabel("Options")
            }
        }
    }

    private var menuIcon: some View {
        let palette = BrandTheme.palette(for: colorScheme)

        return Image(systemName: "gearshape.fill")
            .font(.system(size: 18, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(headerTitleColor)
            .frame(width: 34, height: 34)
            .background(.thinMaterial, in: Circle())
            .overlay(
                Circle()
                    .stroke(headerIconBorderColor(palette: palette), lineWidth: 0.75)
            )
            .shadow(color: headerIconShadowColor, radius: 2, y: 1)
            .padding(4) // ensures a ~44pt hit target
    }

    private var headerTitleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private func headerIconBorderColor(palette: BrandTheme.Palette) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : palette.border.opacity(0.6)
    }

    private var headerIconShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.08)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.6) : Color.black.opacity(0.12)
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
