import SwiftUI
import WhatsThatShared

/// A slim fixed-height bottom action bar for the pre-onboarding flow.
/// Shows "Create Your Own" button and "Do you have an account? Sign in" link.
struct PreOnboardingBottomSheetView: View {
    let onContinue: () -> Void
    let onSignIn: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: BrandSpacing.medium) {
                    // Primary action
                    BrandPrimaryButton(title: "Create Your Own", action: onContinue)

                    // Sign in link - entire line tappable
                    Button(action: onSignIn) {
                        Text("Do you have an account? Sign in")
                            .font(.adaptiveSystem(size: 14, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, BrandSpacing.large)
                .padding(.top, BrandSpacing.large)
                .padding(.bottom, max(bottomInset + BrandSpacing.small, BrandSpacing.large))
                .frame(maxWidth: .infinity)
                .background(barBackground)

                // Solid fill for safe area below the rounded sheet
                // This ensures nothing shows through the home indicator area
                safeAreaFillColor
                    .frame(height: bottomInset)
            }
            .edgesIgnoringSafeArea(.bottom)
        }
    }

    /// The fill color for the safe area below the bottom sheet
    private var safeAreaFillColor: Color {
        colorScheme == .dark ? Color(hex: "#141927") : .white
    }

    /// The gradient colors for the bar background
    private var barGradientColors: [Color] {
        if colorScheme == .dark {
            return [Color(hex: "#1a1f2e"), Color(hex: "#141927")]
        } else {
            return [.white, .white]
        }
    }

    private var barBackground: some View {
        ZStack {
            // Background gradient for contrast
            LinearGradient(
                colors: barGradientColors,
                startPoint: .top,
                endPoint: .bottom
            )

            // Subtle top border glow (only visible in dark mode)
            if colorScheme == .dark {
                VStack {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.1),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 1)

                    Spacer()
                }
            }
        }
        .clipShape(RoundedCorner(radius: 28, corners: [.topLeft, .topRight]))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 30, x: 0, y: -10)
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }
}

/// Helper shape for rounded corners on specific corners
private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
