import SwiftUI
import WhatsThatShared

struct DiscoveryCaptureProgressView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(palette.primaryAction)
            Text("Preparing…")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(palette.textPrimary)
        }
    }
}
