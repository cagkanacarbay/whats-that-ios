import SwiftUI
import WhatsThatShared

struct OnboardingPageIndicators: View {
    let count: Int
    let currentIndex: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { idx in
                Capsule()
                    .fill(idx == currentIndex ? activeColor : inactiveColor)
                    .frame(width: idx == currentIndex ? 24 : 8, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
        }
    }

    private var activeColor: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }

    private var inactiveColor: Color {
        colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
    }
}
