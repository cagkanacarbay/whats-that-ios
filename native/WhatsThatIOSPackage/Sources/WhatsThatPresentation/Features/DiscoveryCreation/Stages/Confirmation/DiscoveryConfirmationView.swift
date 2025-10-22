import Foundation
import SwiftUI
import WhatsThatDomain
import WhatsThatShared
#if canImport(MapKit)
import MapKit
#endif
#if canImport(UIKit)
import UIKit
#endif
struct DiscoveryConfirmationView: View {
    private enum ActiveAlert: Identifiable {
        case outOfCredits
        case locationPermissions

        var id: String {
            switch self {
            case .outOfCredits:
                return "outOfCredits"
            case .locationPermissions:
                return "locationPermissions"
            }
        }
    }

    let state: DiscoveryConfirmationState
    let creditBalance: Int?
    let flowType: DiscoveryCreationFlowType
    let onRetake: () -> Void
    let onContinue: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeAlert: ActiveAlert?
    @State private var bottomOverlayHeight: CGFloat = 0

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    #if canImport(UIKit)
    private var previewUIImage: UIImage? {
        UIImage(data: state.displayImageData)
    }
    #endif

    private var previewImage: Image? {
        #if canImport(UIKit)
        guard let uiImage = previewUIImage else {
            return nil
        }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }

    private enum PreviewOrientation {
        case portrait
        case landscape
    }

    private var previewOrientation: PreviewOrientation? {
        #if canImport(UIKit)
        guard let image = previewUIImage else { return nil }
        if image.size.height >= image.size.width {
            return .portrait
        } else {
            return .landscape
        }
        #else
        return nil
        #endif
    }

    private var creditDisplayText: String {
        let balanceText = creditBalance.map { String($0) } ?? "…"
        return "Credits: \(balanceText)"
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

    private var continueTitle: String {
        guard let balance = creditBalance, balance == 0 else {
            return "Continue"
        }
        return "Get credits"
    }

    private var continueBackground: Color {
        guard let balance = creditBalance, balance == 0 else {
            return palette.primaryAction
        }
        return Color(hex: "#E5484D")
    }

    private var continueIconName: String {
        if let balance = creditBalance, balance == 0 {
            return "cart"
        }
        return "arrow.right"
    }

    private var isContinueDisabled: Bool {
        creditBalance == 0
    }

    private var retakeTitle: String {
        flowType == .upload ? "Re-upload" : "Retake"
    }

    private var retakeIconName: String {
        flowType == .upload ? "arrow.triangle.2.circlepath" : "arrow.counterclockwise"
    }

    private var hasResolvedLocation: Bool {
        state.location != nil
    }

    private var shouldShowLocationPermissions: Bool {
        flowType == .camera && !state.isLocationPermissionGranted
    }

    private var shouldShowMissingLocation: Bool {
        flowType == .upload && state.location == nil
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top - 10
            // Overlays already respect the safe area; only add minimal extra breathing room.
            let overlayTopPadding = topInset > 0 ? BrandSpacing.small : BrandSpacing.medium
            let overlayControlHeight: CGFloat = 48
            let minimumTopPadding = topInset + overlayTopPadding
            let previewTopSpacing: CGFloat = -20
            let previewBottomSpacing: CGFloat = BrandSpacing.medium
            let previewTopPadding = max(
                topInset + overlayTopPadding + overlayControlHeight + previewTopSpacing,
                minimumTopPadding
            )
            let previewAvailableHeight = max(proxy.size.height - previewTopPadding - bottomOverlayHeight - previewBottomSpacing, 0)

            ZStack {
                palette.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    previewSection(size: proxy.size, availableHeight: previewAvailableHeight)
                        .padding(.top, previewTopPadding)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .overlay(alignment: .topLeading) {
                overlayCircleButton(systemName: "xmark", action: onCancel)
                    .padding(.leading, BrandSpacing.large)
                    .padding(.top, overlayTopPadding)
            }
            .overlay(alignment: .topTrailing) {
                topTrailingControl
                    .padding(.trailing, BrandSpacing.large)
                    .padding(.top, overlayTopPadding)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.clear,
                        palette.background.opacity(0.25),
                        palette.background.opacity(0.65),
                        palette.background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.size.height * 0.35)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                bottomOverlay
                    .padding(.top, previewBottomSpacing)
                    .padding(.horizontal, BrandSpacing.large)
                    .padding(.bottom, BrandSpacing.small)
                    .frame(maxWidth: proxy.size.width)
            }
        }
        .onPreferenceChange(BottomOverlayHeightPreferenceKey.self) { bottomOverlayHeight = $0 }
        .alert(item: $activeAlert) { alert(for: $0) }
    }

    @ViewBuilder
    private func previewSection(size: CGSize, availableHeight: CGFloat) -> some View {
        let fallbackHeight = max(size.height * 0.62, 320)
        let containerHeight = availableHeight > 0 ? availableHeight : fallbackHeight
        let resolvedHeight = max(containerHeight, 1)
        return ZStack {
            Group {
                if let image = previewImage {
                    let orientation = previewOrientation
                    image
                        .resizable()
                        .aspectRatio(contentMode: orientation == .landscape ? .fit : .fill)
                        .frame(width: size.width, height: resolvedHeight, alignment: .center)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(palette.border.opacity(0.1))
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "photo")
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundStyle(palette.textSecondary)
                                Text("Preview unavailable")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                }
            }
        }
        .frame(width: size.width, height: resolvedHeight, alignment: .center)
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 16)
    }
    @ViewBuilder
    private var topTrailingControl: some View {
        if shouldShowLocationPermissions {
            overlayCapsuleButton(
                title: "No Location Permissions",
                systemName: "location.slash"
            ) {
                activeAlert = .locationPermissions
            }
        } else if hasResolvedLocation {
            overlayCircleButton(systemName: "mappin.and.ellipse") {
                openCurrentLocation()
            }
        } else if shouldShowMissingLocation {
            overlayCapsuleBadge(title: "No location", systemName: "mappin")
        }
    }

    private var bottomOverlay: some View {
        let chipToActionsSpacing: CGFloat = 4
        return VStack(alignment: .leading, spacing: chipToActionsSpacing) {
            Button(action: {}) {
                Text(creditDisplayText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(creditTint)
                    .padding(.horizontal, BrandSpacing.small)
                    .padding(.top, BrandSpacing.small / 2)
                    .padding(.bottom, 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(creditBalance == nil)

            HStack(spacing: BrandSpacing.small) {
                Button(action: onRetake) {
                    Label(retakeTitle, systemImage: retakeIconName)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: DiscoveryCreationFlowView.LayoutConstants.controlHeight)
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
                        activeAlert = .outOfCredits
                        return
                    }
                    onContinue()
                } label: {
                    Label(continueTitle, systemImage: continueIconName)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: DiscoveryCreationFlowView.LayoutConstants.controlHeight)
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(continueBackground)
                )
                .opacity(isContinueDisabled ? 0.45 : 1)
                .disabled(isContinueDisabled)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: BottomOverlayHeightPreferenceKey.self, value: geometry.size.height)
            }
        )
    }

    private func overlayCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
                .foregroundStyle(palette.overlayButtonForeground)
                .background(
                    Circle()
                        .fill(palette.overlayButtonBackground)
                )
                .overlay {
                    Circle()
                        .stroke(palette.overlayButtonBorder, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(palette.overlayButtonShadowOpacity), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func overlayCapsuleButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(palette.overlayButtonForeground)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(palette.overlayButtonBackground)
            )
            .overlay {
                Capsule()
                    .stroke(palette.overlayButtonBorder, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(palette.overlayButtonShadowOpacity), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func overlayCapsuleBadge(title: String, systemName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(palette.overlayButtonForeground.opacity(0.9))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(palette.overlayButtonBackground)
        )
        .overlay {
            Capsule()
                .stroke(palette.overlayButtonBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(palette.overlayButtonShadowOpacity), radius: 14, x: 0, y: 8)
        .allowsHitTesting(false)
    }

    private func alert(for alert: ActiveAlert) -> Alert {
        switch alert {
        case .outOfCredits:
            return Alert(
                title: Text("Out of credits"),
                message: Text("Each discovery costs 1 credit. Purchase more to continue."),
                dismissButton: .default(Text("OK"))
            )
        case .locationPermissions:
            return Alert(
                title: Text("Grant Location Permissions"),
                message: Text("Enable location access in Settings to improve analysis accuracy."),
                primaryButton: .default(Text("Open Settings"), action: openSettings),
                secondaryButton: .cancel()
            )
        }
    }

    private func openSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #endif
    }

    private func openCurrentLocation() {
        #if canImport(MapKit)
        guard let location = state.location else { return }
        let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = state.locationDescription ?? "Discovery location"
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
        #endif
    }
}