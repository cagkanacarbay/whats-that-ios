import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct DiscoveryHeaderOverlayView: View {
    let discovery: DiscoverySummary
    let palette: BrandTheme.Palette
    var maxDescriptionLines: Int = 0

    /// Adjust how far up the gradient tint should carry. Higher values reveal more of the image.
    var gradientFalloff: CGFloat = 0.55
    var contentWidth: CGFloat? = nil
    var onShare: (() -> Void)? = nil
    var onShowMap: (() -> Void)? = nil
    private let actionRowBottomInset: CGFloat = 120 // makes sure the map and share buttons are placed above the title

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundGradient

            VStack(spacing: BrandSpacing.small) {
                Text(discovery.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(discovery.capturedAt.formatted(.dateTime.month().day().year()))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity)

                if let shortDescription = overlayShortDescription {
                    Text(shortDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .lineLimit(maxDescriptionLines == 0 ? nil : maxDescriptionLines)
                }
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.top, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.large)
            .frame(maxWidth: contentWidth ?? .infinity)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: contentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .overlay(alignment: .bottom) {
            if hasActionRow {
                actionRow
                    .padding(.horizontal, BrandSpacing.large)
                    .padding(.bottom, actionRowBottomInset)
            }
        }
    }

    private var gradientStops: [Gradient.Stop] {
        [
            .init(color: palette.background.opacity(0.95), location: 0.0),
            .init(color: palette.overlayMidtone.opacity(0.85), location: max(gradientFalloff - 0.25, 0)),
            .init(color: palette.overlayMidtone.opacity(0.35), location: max(gradientFalloff - 0.12, 0.05)),
            .init(color: Color.clear, location: min(gradientFalloff + 0.2, 1.0))
        ]
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            if let onShowMap {
                DiscoveryOverlayButton(
                    systemName: "mappin.and.ellipse",
                    action: onShowMap,
                    accessibilityLabel: "Open location in Maps"
                )
            }

            Spacer()

            if let onShare {
                DiscoveryOverlayButton(
                    systemName: "square.and.arrow.up",
                    action: onShare,
                    accessibilityLabel: "Share discovery"
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var hasActionRow: Bool {
        onShare != nil || onShowMap != nil
    }

    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(stops: gradientStops),
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private var overlayShortDescription: String? {
        if let description = normalized(discovery.shortDescription) {
            return description
        }
        return normalized(discovery.highlight)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        return normalized(value)
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
