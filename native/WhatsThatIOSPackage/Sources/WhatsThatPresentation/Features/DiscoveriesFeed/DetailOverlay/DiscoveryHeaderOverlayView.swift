import SwiftUI
import UIKit
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
    var isClosing: Bool = false
    var showTopControls: Bool = false
    var topControlsSafeAreaInsets: EdgeInsets = EdgeInsets()
    var onClose: (() -> Void)? = nil
    var onShowOptions: (() -> Void)? = nil
    var isOptionsEnabled: Bool = true
    private let topControlsBottomPadding: CGFloat = BrandSpacing.small
    
    // Dependencies needed for audio controls
    @Environment(\.audioServices) private var audioServices
    
    // Optional callback for creation trigger if parent wants to handle it specially,
    // though the controls can often handle it via VM.
    // For now we can keep a simple callback if we want to bubble up the "show alert" event.
    // But DiscoveryAudioControls might not expose it easily out of the box without binding.
    // Let's assume we can trigger creation directly or pass a closure.
    // The previous implementation had `onOpenAudioGuide` which was for the simple pill.
    // Let's rename/reuse `onCreateAudioGuide` if we want to handle alerts in parent.
    var onCreateAudioGuide: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundGradient

            VStack(spacing: BrandSpacing.small / 2) {
                if shouldShowActionRow {
                    actionRow
                }

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
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.top, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.large)
            .frame(maxWidth: contentWidth ?? .infinity)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: contentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .overlay(alignment: .top) {
            // Top controls (back button, options button) - at very top
            if showTopControls {
                HStack {
                    if let onClose {
                        DiscoveryOverlayButton(
                            systemName: "chevron.left",
                            action: onClose,
                            accessibilityLabel: "Back"
                        )
                        .recordOverlayInteractiveRegion()
                    }
                    
                    Spacer()
                    
                    if let onShowOptions {
                        DiscoveryOverlayButton(
                            systemName: "ellipsis",
                            action: onShowOptions,
                            rotation: .degrees(90),
                            accessibilityLabel: "More options",
                            isDisabled: !isOptionsEnabled
                        )
                        .recordOverlayInteractiveRegion()
                    }
                }
                .frame(maxWidth: contentWidth ?? .infinity)
                .padding(.horizontal, BrandSpacing.large)
                .padding(.top, resolvedTopPadding(from: topControlsSafeAreaInsets))
                .padding(.bottom, topControlsBottomPadding)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea()
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
                .recordOverlayInteractiveRegion()
            }

            Spacer()

            if let onShare {
                DiscoveryOverlayButton(
                    systemName: "square.and.arrow.up",
                    action: onShare,
                    accessibilityLabel: "Share discovery"
                )
                .recordOverlayInteractiveRegion()
            }
        }
        .frame(maxWidth: contentWidth ?? .infinity)
    }

    private var hasActionRow: Bool {
        onShare != nil || onShowMap != nil
    }

    private var shouldShowActionRow: Bool {
        hasActionRow && !isClosing
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

    private func resolvedTopPadding(from insets: EdgeInsets) -> CGFloat {
        let baseInset = insets.top
        if baseInset <= 0 {
            let globalInset = UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?
                .safeAreaInsets.top ?? 0
            return globalInset - 4
        }
        return baseInset - 4
    }
}

private extension View {
    func recordOverlayInteractiveRegion() -> some View {
        anchorPreference(
            key: DiscoveryOverlayInteractiveRegionPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [anchor]
        }
    }
}
