import SwiftUI
import WhatsThatShared

struct DiscoveryConfirmationActionsView: View {
    let creditDisplayText: String
    let creditBalance: Int?
    let retakeTitle: String
    let retakeIconName: String
    let continueTitle: String
    let continueIconName: String
    let continueBackground: Color
    let palette: DiscoveryCreationPalette
    let onRetake: () -> Void
    let onContinue: () -> Void
    let onOutOfCredits: () -> Void
    let onCreditsTap: (() -> Void)?
    @Binding var generateAudioGuide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Button(action: { onCreditsTap?() }) {
                    Text(creditDisplayText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(creditTint)
                        .padding(.horizontal, BrandSpacing.small)
                        .padding(.top, BrandSpacing.small / 2)
                        .padding(.bottom, 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Allow opening Credits even if balance is loading/unknown.
                
                Spacer()
                
                AudioToggleView(isOn: $generateAudioGuide, palette: palette)
                    .padding(.trailing, 4) // Add slight trailing padding for visual balance
            }
            .padding(.bottom, 4)

            HStack(spacing: BrandSpacing.small) {
                Button(action: onRetake) {
                    Label(retakeTitle, systemImage: retakeIconName)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: DiscoveryCreationViewConstants.controlHeight)
                        .foregroundStyle(palette.overlayButtonForeground)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(palette.secondaryAction)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(palette.overlayButtonBorder, lineWidth: 1)
                }

                Button {
                    if let balance = creditBalance, balance == 0 {
                        onOutOfCredits()
                        return
                    }
                    onContinue()
                } label: {
                    Label(continueTitle, systemImage: continueIconName)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: DiscoveryCreationViewConstants.controlHeight)
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(continueBackground)
                )
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: BottomOverlayHeightPreferenceKey.self, value: geometry.size.height)
            }
        )
    }

    private var creditTint: Color {
        guard let balance = creditBalance else {
            return palette.overlayButtonForeground.opacity(0.75)
        }
        if balance == 0 {
            return Color(hex: "#E5484D")
        }
        if balance <= 10 {
            return Color(hex: "#F5A524")
        }
        return palette.overlayButtonForeground
    }
}
