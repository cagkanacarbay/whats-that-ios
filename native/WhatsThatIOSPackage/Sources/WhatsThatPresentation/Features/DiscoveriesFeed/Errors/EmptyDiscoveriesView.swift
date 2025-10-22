import SwiftUI
import WhatsThatShared

struct EmptyDiscoveriesView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)

            Text("Start making discoveries")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(titleColor)

            Text("Snap a photo or upload from your library to unlock stories about the world around you.")
                .font(.system(size: 16, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(bodyColor)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(.horizontal, BrandSpacing.large)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : BrandColors.Light.bodyText
    }
}
