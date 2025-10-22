import SwiftUI
import WhatsThatShared
import UIKit

typealias DiscoveryHeaderPlatformImage = UIImage

struct DiscoveryHeroHeaderView: View {
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

    var body: some View {
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
        .frame(maxWidth: .infinity)
        .frame(width: width, height: effectiveHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var effectiveHeight: CGFloat {
        max(height + pullDownOffset, 0)
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

private extension Image {
    init(platformImage: UIImage) {
        self = Image(uiImage: platformImage)
    }
}
