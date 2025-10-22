import SwiftUI

struct DiscoveryConfirmationLocationBadge: View {
    enum Content {
        case resolved(action: () -> Void)
        case missing
        case permissions(action: () -> Void)
    }

    let content: Content
    let palette: DiscoveryCreationPalette

    var body: some View {
        switch content {
        case let .resolved(action):
            Button(action: action) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(
                DiscoveryCreationOverlayButtonStyle(
                    palette: palette,
                    shape: .circle()
                )
            )
            .accessibilityLabel("Open discovery location in Maps")
        case .missing:
            HStack(spacing: 8) {
                Image(systemName: "mappin")
                    .font(.system(size: 16, weight: .semibold))
                Text("No location")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(palette.overlayButtonForeground.opacity(0.9))
            .padding(.horizontal, DiscoveryCreationViewConstants.overlayCapsuleHorizontalPadding)
            .padding(.vertical, DiscoveryCreationViewConstants.overlayCapsuleVerticalPadding)
            .background(
                Capsule()
                    .fill(palette.overlayButtonBackground)
            )
            .overlay {
                Capsule()
                    .stroke(palette.overlayButtonBorder, lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(palette.overlayButtonShadowOpacity),
                radius: 14,
                x: 0,
                y: 8
            )
            .allowsHitTesting(false)
        case let .permissions(action):
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 16, weight: .semibold))
                    Text("No Location Permissions")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .buttonStyle(
                DiscoveryCreationOverlayButtonStyle(
                    palette: palette,
                    shape: .capsule
                )
            )
            .accessibilityLabel("Open Settings to grant location permissions")
        }
    }
}
