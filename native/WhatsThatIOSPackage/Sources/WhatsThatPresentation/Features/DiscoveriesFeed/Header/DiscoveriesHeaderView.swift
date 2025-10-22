import SwiftUI
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

            Divider()
                .background(dividerColor)
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, metrics.headerDividerBottomPadding)
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
        Image(systemName: "gearshape.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(headerTitleColor)
            .padding(10)
            .background(headerIconBackground)
            .clipShape(Circle())
    }

    private var headerTitleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var headerIconBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : BrandColors.Light.border
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : BrandColors.Light.border
    }
}
