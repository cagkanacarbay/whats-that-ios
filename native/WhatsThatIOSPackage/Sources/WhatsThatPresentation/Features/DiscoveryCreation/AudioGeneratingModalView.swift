import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// Modal shown after first discovery stream completes, explaining audio generation.
struct AudioGeneratingModalView: View {
    let flowType: DiscoveryCreationFlowType
    let onRequestNewDiscovery: (DiscoveryCreationFlowType) -> Void
    let onReadThisDiscovery: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    private var creationPalette: DiscoveryCreationPalette {
        DiscoveryCreationPalette.resolve(for: colorScheme)
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
                HStack(spacing: BrandSpacing.small) {
                    // Secondary action (left)
                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                            .font(.adaptiveSystem(size: 17, weight: .semibold, scaleFactor: 1.3))
                            .frame(maxWidth: .infinity)
                            .frame(height: DiscoveryCreationViewConstants.controlHeight)
                            .contentShape(Rectangle())
                            .foregroundStyle(creationPalette.overlayButtonForeground)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(creationPalette.secondaryAction)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(creationPalette.overlayButtonBorder, lineWidth: 1)
                    }

                    // Primary action (right)
                    Button(action: primaryAction) {
                        Text(primaryTitle)
                            .font(.adaptiveSystem(size: 17, weight: .semibold, scaleFactor: 1.3))
                            .frame(maxWidth: .infinity)
                            .frame(height: DiscoveryCreationViewConstants.controlHeight)
                            .contentShape(Rectangle())
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(creationPalette.primaryAction)
                    )
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
        .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)
        .frame(maxWidth: .infinity)
        .background(palette.background)
    }

    // MARK: - Button Configuration

    private var primaryTitle: String {
        switch flowType {
        case .camera:
            return "Take Another Photo"
        case .upload:
            return "Upload Another"
        }
    }

    private var secondaryTitle: String {
        switch flowType {
        case .camera:
            return "Upload"
        case .upload:
            return "Take a Photo"
        }
    }

    private var primaryAction: () -> Void {
        switch flowType {
        case .camera:
            return { onRequestNewDiscovery(.camera) }
        case .upload:
            return { onRequestNewDiscovery(.upload) }
        }
    }

    private var secondaryAction: () -> Void {
        switch flowType {
        case .camera:
            return { onRequestNewDiscovery(.upload) }
        case .upload:
            return { onRequestNewDiscovery(.camera) }
        }
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

#Preview("Camera Flow") {
    AudioGeneratingModalView(
        flowType: .camera,
        onRequestNewDiscovery: { _ in },
        onReadThisDiscovery: {}
    )
}

#Preview("Upload Flow") {
    AudioGeneratingModalView(
        flowType: .upload,
        onRequestNewDiscovery: { _ in },
        onReadThisDiscovery: {}
    )
}
