import SwiftUI
import WhatsThatShared

/// Modal shown after first discovery stream completes, explaining audio generation.
struct AudioGeneratingModalView: View {
    let onCreateAnother: () -> Void
    let onReadThisDiscovery: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo with spinning ring
            logoWithSpinner
                .padding(.bottom, BrandSpacing.xLarge)

            // Title - allows wrapping to two lines
            Text("Your story's being voiced")
                .font(.adaptiveSystem(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.medium)

            // Body text
            Text("This takes about 30 seconds.\nPerfect time to discover something else.")
                .font(.adaptiveSystem(size: 17, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, BrandSpacing.large)

            Spacer()

            // Buttons
            VStack(spacing: BrandSpacing.small) {
                BrandPrimaryButton(title: "Discover Another") {
                    onCreateAnother()
                }

                Button {
                    onReadThisDiscovery()
                } label: {
                    Text("Read This One First")
                        .font(.adaptiveBody().weight(.medium))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.xLarge)
        }
        .background(palette.background)
    }

    @ViewBuilder
    private var logoWithSpinner: some View {
        ZStack {
            // Spinning ring
            SpinningRing()
                .frame(width: 80, height: 80)

            // App logo (smaller)
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
        }
    }
}

/// Animated spinning ring around the logo
private struct SpinningRing: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        BrandColors.spinner.opacity(0.1),
                        BrandColors.spinner
                    ]),
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                .linear(duration: 1.2)
                    .repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

#Preview {
    AudioGeneratingModalView(
        onCreateAnother: {},
        onReadThisDiscovery: {}
    )
}
