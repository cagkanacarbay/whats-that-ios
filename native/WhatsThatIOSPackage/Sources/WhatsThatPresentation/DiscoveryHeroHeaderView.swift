import SwiftUI
import WhatsThatDomain
import WhatsThatShared

#if canImport(UIKit)
import UIKit
typealias DiscoveryHeaderPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias DiscoveryHeaderPlatformImage = NSImage
#endif

struct DiscoveryHeroHeaderView: View {
    let discovery: DiscoverySummary
    let imageURL: URL?
    let placeholderImage: DiscoveryHeaderPlatformImage?
    let preferPlaceholderImage: Bool
    let height: CGFloat
    let pullDownOffset: CGFloat
    let cornerRadius: CGFloat
    var width: CGFloat? = nil
    let namespace: Namespace.ID?
    let isGeometrySource: Bool
    let discoveryId: Int64
    let palette: BrandTheme.Palette
    let onShare: (() -> Void)?
    let onLocation: (() -> Void)?
    var gradientFalloff: CGFloat = 0.55
    var maxDescriptionLines: Int = 3
    var overlayOpacity: Double = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            DiscoveryHeroHeaderImageView(
                discoveryId: discoveryId,
                imageURL: imageURL,
                placeholderImage: placeholderImage,
                preferPlaceholder: preferPlaceholderImage,
                height: effectiveHeight,
                cornerRadius: cornerRadius,
                namespace: namespace,
                isGeometrySource: isGeometrySource
            )

            DiscoveryHeaderOverlayView(
                discovery: discovery,
                palette: palette,
                maxDescriptionLines: maxDescriptionLines,
                gradientFalloff: gradientFalloff,
                contentWidth: width
            )
            .frame(height: height)
            .opacity(overlayOpacity)
            .allowsHitTesting(false)

            headerButtons
                .opacity(overlayOpacity)
        }
        .frame(maxWidth: .infinity)
        .frame(width: width, height: effectiveHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var effectiveHeight: CGFloat {
        max(height + pullDownOffset, 0)
    }

    private var headerButtons: some View {
        HStack {
            if let onLocation {
                headerButton(systemName: "mappin.and.ellipse", action: onLocation)
            }

            Spacer()

            if let onShare {
                headerButton(systemName: "square.and.arrow.up", action: onShare)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BrandSpacing.large)
        .padding(.bottom, 28)
    }

    private func headerButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.overlayButtonForeground)
                .padding(16)
                .background(palette.overlayButtonBackground)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(palette.overlayButtonBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .shadow(
            color: Color.black.opacity(palette.overlayButtonShadowOpacity),
            radius: 8,
            x: 0,
            y: 4
        )
    }
}

private struct DiscoveryHeroHeaderImageView: View {
    let discoveryId: Int64
    let imageURL: URL?
    let placeholderImage: DiscoveryHeaderPlatformImage?
    let preferPlaceholder: Bool
    let height: CGFloat
    let cornerRadius: CGFloat
    let namespace: Namespace.ID?
    let isGeometrySource: Bool

    var body: some View {
        DiscoveryCachedImage(
            discoveryId: discoveryId,
            remoteURL: imageURL
        ) { phase in
            Group {
                switch phase {
                case .success(let platformImage):
                    resolvedImage(for: platformImage)
                case .failure:
                    placeholderContent
                case .loading, .empty:
                    if let placeholderImage {
                        Image(platformImage: placeholderImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholderGradient
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .matchedGeometryIfNeeded(
            id: geometryId,
            namespace: namespace,
            isSource: isGeometrySource
        )
    }

    private func resolvedImage(for platformImage: DiscoveryHeaderPlatformImage) -> some View {
        Group {
            if preferPlaceholder, let placeholderImage {
                Image(platformImage: placeholderImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(platformImage: platformImage)
                    .resizable()
                    .scaledToFill()
            }
        }
    }

    @ViewBuilder
    private var placeholderContent: some View {
        if let placeholderImage {
            Image(platformImage: placeholderImage)
                .resizable()
                .scaledToFill()
        } else {
            placeholderGradient
        }
    }

    private var placeholderGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(hex: "#20293A"),
                Color(hex: "#141927")
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var geometryId: String {
        "discovery-image-\(discoveryId)"
    }
}

private extension View {
    @ViewBuilder
    func matchedGeometryIfNeeded(
        id: String,
        namespace: Namespace.ID?,
        isSource: Bool
    ) -> some View {
        if let namespace {
            self.matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: isSource
            )
        } else {
            self
        }
    }
}

#if canImport(UIKit)
private extension Image {
    init(platformImage: UIImage) {
        self = Image(uiImage: platformImage)
    }
}
#elseif canImport(AppKit)
private extension Image {
    init(platformImage: NSImage) {
        self = Image(nsImage: platformImage)
    }
}
#endif
