import SwiftUI
import WhatsThatShared

/// Welcome modal overlay shown when the app opens in pre-onboarding.
/// Displays welcome copy over a lightly blurred background grid.
struct PreOnboardingWelcomeModal: View {
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var cardScale: CGFloat = 0.95
    @State private var cardOpacity: Double = 0

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        GeometryReader { proxy in
            let screenWidth = proxy.size.width

            ZStack {
                // Semi-transparent overlay - tap to dismiss
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissModal()
                    }

                // Centered card
                welcomeCard(screenWidth: screenWidth)
                    .scaleEffect(cardScale)
                    .opacity(cardOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                cardScale = 1.0
                cardOpacity = 1.0
            }
        }
    }

    private func welcomeCard(screenWidth: CGFloat) -> some View {
        let cardWidth = min(screenWidth - 48, UIDevice.isIPad ? 400 : 360)

        return VStack(spacing: BrandSpacing.large) {
            // Logo
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 72)

            // Title
            Text("Feel the Magic of What's That")
                .font(.adaptiveSystem(size: 22, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)

            // Body copy
            Text("Tap any photo. Read the story.\nListen to the guide.")
                .font(.adaptiveSystem(size: 16, weight: .regular))
                .foregroundStyle(palette.textPrimary.opacity(0.8))
                .multilineTextAlignment(.center)

            // Action button
            BrandPrimaryButton(title: "Explore") {
                dismissModal()
            }
            .padding(.top, BrandSpacing.small)
        }
        .padding(32)
        .frame(width: cardWidth)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var cardBackground: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }

    private func dismissModal() {
        withAnimation(.easeOut(duration: 0.25)) {
            cardScale = 0.95
            cardOpacity = 0
        }

        // Delay the actual dismiss to allow animation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
        }
    }
}
