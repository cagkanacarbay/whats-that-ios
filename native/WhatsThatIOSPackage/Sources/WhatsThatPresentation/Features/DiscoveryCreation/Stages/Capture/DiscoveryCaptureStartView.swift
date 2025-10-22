import SwiftUI
import WhatsThatShared

struct DiscoveryCaptureStartView: View {
    let emoji: String
    let title: String
    let subtitle: String
    let action: () -> Void

    init(
        emoji: String,
        title: String,
        subtitle: String = "We’ll guide you from capture to narration in seconds.",
        action: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            Text(emoji)
                .font(.system(size: 72))
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            BrandPrimaryButton(title: "Get started", action: action)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
