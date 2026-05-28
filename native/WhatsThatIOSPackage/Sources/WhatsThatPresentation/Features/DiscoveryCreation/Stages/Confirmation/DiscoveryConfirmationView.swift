import Foundation
import SwiftUI
import WhatsThatDomain
import WhatsThatShared
#if canImport(MapKit)
import MapKit
#endif
import UIKit

struct DiscoveryConfirmationView: View {
    let state: DiscoveryConfirmationState
    let creditBalance: Int?
    let flowType: DiscoveryCreationFlowType
    let onRetake: () -> Void
    let onContinue: () -> Void
    let onCancel: () -> Void
    let onRequestCredits: (() -> Void)?
    let onShowLocationPermissions: () -> Void
    let onShowMissingUploadLocation: () -> Void
    @Binding var generateAudioGuide: Bool
    /// When true, audio toggle is locked ON (intro mode).
    var isAudioToggleLocked: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var bottomOverlayHeight: CGFloat = 0
    @State private var isImageFullscreenPresented = false

    private var palette: DiscoveryCreationPalette {
        DiscoveryCreationPalette.resolve(for: colorScheme)
    }

    private var previewUIImage: UIImage? {
        UIImage(data: state.displayImageData)
    }

    private var previewImage: Image? {
        guard let uiImage = previewUIImage else {
            return nil
        }
        return Image(uiImage: uiImage)
    }

    private enum PreviewOrientation {
        case portrait
        case landscape
    }

    private var previewOrientation: PreviewOrientation? {
        guard let image = previewUIImage else { return nil }
        return image.size.height >= image.size.width ? .portrait : .landscape
    }

    private var creditDisplayText: String {
        let balanceText = creditBalance.map { String($0) } ?? "…"
        return "Credits: \(balanceText)"
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

    private var retakeTitle: String {
        flowType == .upload ? "Re-upload" : "Retake"
    }

    private var retakeIconName: String {
        flowType == .upload ? "arrow.triangle.2.circlepath" : "arrow.counterclockwise"
    }

    private var hasResolvedLocation: Bool { state.location != nil }

    private var shouldShowLocationPermissions: Bool { flowType == .camera && !state.isLocationPermissionGranted }

    private var shouldShowMissingLocation: Bool { flowType == .upload && state.location == nil }

    private var shouldShowResolvingLocation: Bool {
        flowType == .camera && state.isLocationPermissionGranted && state.location == nil && state.isResolvingLocation
    }

    private var shouldHideWhileMissingCameraLocation: Bool {
        flowType == .camera && state.isLocationPermissionGranted && state.location == nil && !state.isResolvingLocation
    }

    private var locationBadgeContent: DiscoveryConfirmationLocationBadge.Content? {
        if shouldShowLocationPermissions {
            return .permissions { showLocationPermissionsAlert() }
        }
        if hasResolvedLocation {
            return .resolved { openCurrentLocation() }
        }
        if shouldShowResolvingLocation {
            return .resolving
        }
        if shouldShowMissingLocation {
            return .missing { showMissingUploadLocationAlert() }
        }
        if shouldHideWhileMissingCameraLocation {
            return nil
        }
        return nil
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top - 10
            let overlayTopPadding = topInset > 0 ? BrandSpacing.small : BrandSpacing.medium
            let overlayControlHeight: CGFloat = 48
            let minimumTopPadding = topInset + overlayTopPadding
            let previewTopSpacing: CGFloat = -20
            let previewBottomSpacing: CGFloat = BrandSpacing.medium
            let previewTopPadding = max(
                topInset + overlayTopPadding + overlayControlHeight + previewTopSpacing,
                minimumTopPadding
            )
            let previewAvailableHeight = max(
                proxy.size.height - previewTopPadding - bottomOverlayHeight - previewBottomSpacing,
                0
            )

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
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(
                    DiscoveryCreationOverlayButtonStyle(
                        palette: palette,
                        shape: .circle()
                    )
                )
                .padding(.leading, BrandSpacing.large)
                .padding(.top, overlayTopPadding)
            }
            .overlay(alignment: .topTrailing) {
                if let badgeContent = locationBadgeContent {
                    DiscoveryConfirmationLocationBadge(content: badgeContent, palette: palette)
                        .zIndex(2)
                        .padding(.trailing, BrandSpacing.large)
                        .padding(.top, overlayTopPadding)
                }
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
                DiscoveryConfirmationActionsView(
                    creditDisplayText: creditDisplayText,
                    creditBalance: creditBalance,
                    retakeTitle: retakeTitle,
                    retakeIconName: retakeIconName,
                    continueTitle: continueTitle,
                    continueIconName: continueIconName,
                    continueBackground: continueBackground,
                    palette: palette,
                    onRetake: onRetake,
                    onContinue: onContinue,
                    onOutOfCredits: handleOutOfCredits,
                    onCreditsTap: {
                        if let onRequestCredits {
                            onRequestCredits()
                        }
                    },
                    generateAudioGuide: $generateAudioGuide,
                    isAudioToggleLocked: isAudioToggleLocked
                )
                .padding(.top, previewBottomSpacing)
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.small)
                .frame(maxWidth: proxy.size.width)
            }
        }
        .onPreferenceChange(BottomOverlayHeightPreferenceKey.self) { bottomOverlayHeight = $0 }
        .applyingIf(UIDevice.isIPad) { view in
            view.fullScreenCover(isPresented: $isImageFullscreenPresented) {
                if let image = previewUIImage {
                    DiscoveryDetailImageFullscreenView(
                        discoveryId: 0,
                        imageURL: nil,
                        placeholderImage: image,
                        onClose: { isImageFullscreenPresented = false }
                    )
                }
            }
        }
        .applyingIf(!UIDevice.isIPad) { view in
            view.sheet(isPresented: $isImageFullscreenPresented) {
                if let image = previewUIImage {
                    DiscoveryDetailImageFullscreenView(
                        discoveryId: 0,
                        imageURL: nil,
                        placeholderImage: image,
                        onClose: { isImageFullscreenPresented = false }
                    )
                    .presentationDetents([.fraction(0.995)])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    @ViewBuilder
    private func previewSection(size: CGSize, availableHeight: CGFloat) -> some View {
        let fallbackHeight = max(size.height * 0.62, 320)
        let containerHeight = availableHeight > 0 ? availableHeight : fallbackHeight
        let resolvedHeight = max(containerHeight, 1)
        ZStack {
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
        .contentShape(Rectangle())
        .onTapGesture {
            isImageFullscreenPresented = true
        }
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 16)
    }

    private func handleOutOfCredits() {
        // Call the credits handler if available; otherwise the ViewModel
        // will show the full-screen credits exhausted view.
        onRequestCredits?()
    }

    private func showLocationPermissionsAlert() {
        #if DEBUG
        print("[ConfirmationView] Showing location permissions alert")
        #endif
        onShowLocationPermissions()
    }

    private func showMissingUploadLocationAlert() {
        #if DEBUG
        print("[ConfirmationView] Showing missing upload location alert")
        #endif
        onShowMissingUploadLocation()
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
