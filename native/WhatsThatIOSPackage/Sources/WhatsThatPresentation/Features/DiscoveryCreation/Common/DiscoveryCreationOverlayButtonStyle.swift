import SwiftUI

struct DiscoveryCreationOverlayButtonStyle: ButtonStyle {
    enum Shape {
        case circle(diameter: CGFloat = DiscoveryCreationViewConstants.overlayButtonDiameter)
        case capsule
    }

    let palette: DiscoveryCreationPalette
    let shape: Shape

    func makeBody(configuration: Configuration) -> some View {
        switch shape {
        case let .circle(diameter):
            baseLabel(for: configuration)
                .frame(width: diameter, height: diameter)
                .background(
                    Circle()
                        .fill(backgroundColor(isPressed: configuration.isPressed))
                )
                .overlay {
                    Circle()
                        .stroke(palette.overlayButtonBorder, lineWidth: 1)
                }
        case .capsule:
            baseLabel(for: configuration)
                .padding(.horizontal, DiscoveryCreationViewConstants.overlayCapsuleHorizontalPadding)
                .padding(.vertical, DiscoveryCreationViewConstants.overlayCapsuleVerticalPadding)
                .background(
                    Capsule()
                        .fill(backgroundColor(isPressed: configuration.isPressed))
                )
                .overlay {
                    Capsule()
                        .stroke(palette.overlayButtonBorder, lineWidth: 1)
                }
        }
    }

    private func baseLabel(for configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.overlayButtonForeground)
            .contentShape(Rectangle())
            .shadow(
                color: Color.black.opacity(palette.overlayButtonShadowOpacity),
                radius: 14,
                x: 0,
                y: 8
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        palette.overlayButtonBackground.opacity(isPressed ? 0.85 : 1)
    }
}
