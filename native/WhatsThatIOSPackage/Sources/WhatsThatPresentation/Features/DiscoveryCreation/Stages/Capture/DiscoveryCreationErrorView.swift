import SwiftUI
import WhatsThatShared

struct DiscoveryCreationErrorView: View {
    let emoji: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    init(
        emoji: String = "⚠️",
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            Text(emoji)
                .font(.system(size: 64))
            VStack(spacing: BrandSpacing.small) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                Text(message)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            BrandPrimaryButton(title: actionTitle, action: action)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
