import SwiftUI
import WhatsThatShared

struct DividerWithLabel: View {
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: BrandSpacing.small) {
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(borderColor)
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)
        }
    }

    private var borderColor: Color {
        colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
    }
}

