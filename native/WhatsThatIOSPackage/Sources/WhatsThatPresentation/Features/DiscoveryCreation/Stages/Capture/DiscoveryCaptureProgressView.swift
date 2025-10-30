import SwiftUI
import WhatsThatShared

struct DiscoveryCaptureProgressView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        ZStack {
            VStack(spacing: BrandSpacing.medium) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .scaleEffect(1.25)
                    .tint(palette.primaryAction)
                Text("Preparing…")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
