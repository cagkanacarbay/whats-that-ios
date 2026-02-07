import SwiftUI
import WhatsThatShared

/// Thank you slide shown after first successful credit purchase.
struct ThankYouSlideView: View {
    let creditAmount: Int
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Branded heart icon
            brandedIcon
                .padding(.bottom, BrandSpacing.large)

            // Title
            Text("Thank you")
                .font(.adaptiveSystem(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.medium)

            // Personal message
            VStack(alignment: .leading, spacing: BrandSpacing.medium) {
                Text("Hey, I'm Cha, the person building What's That.")
                    .font(.adaptiveSystem(size: 17, weight: .medium))
                    .foregroundStyle(palette.textPrimary)

                Text("You're one of the very first people to purchase. That means a lot to me. Seriously.")
                    .font(.adaptiveSystem(size: 16, weight: .regular))
                    .foregroundStyle(palette.textSecondary)

                Text("You have \(creditAmount) credits. That's \(creditAmount / 2) discoveries with audio guides, or \(creditAmount) discoveries without.")
                    .font(.adaptiveSystem(size: 16, weight: .regular))
                    .foregroundStyle(palette.textSecondary)

                Text("As one of my earliest supporters, your feedback is super important to me. I'm building this for people like you and I can't wait to hear what you think.")
                    .font(.adaptiveSystem(size: 16, weight: .regular))
                    .foregroundStyle(palette.textSecondary)

                Text("PS: I know it's very annoying that audio guides cost extra credits. They are very costly to generate right now. Know that I'm working on making them free and fast to generate!")
                    .font(.adaptiveSystem(size: 12, weight: .regular))
                    .foregroundStyle(palette.textSecondary)

            }
            .padding(.horizontal, BrandSpacing.xLarge)

            Spacer()

            // Continue button
            BrandPrimaryButton(title: "Continue") {
                onContinue()
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.xLarge)
        }
        .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)
        .frame(maxWidth: .infinity)
        .background(palette.background)
    }

    // MARK: - Subviews

    /// Branded icon with orange accent
    @ViewBuilder
    private var brandedIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(BrandColors.Light.tabSelected.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(BrandColors.Light.tabSelected.opacity(0.3), lineWidth: 2)
                )
                .frame(width: 88, height: 88)

            Image(systemName: "heart.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(BrandColors.Light.tabSelected)
        }
    }
}

#Preview {
    ThankYouSlideView(
        creditAmount: 10,
        onContinue: {}
    )
}
