import SwiftUI
import WhatsThatShared
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct DiscoveryCardImageView: View {
    let discoveryId: Int64
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    @State private var didCacheSnapshot = false

    var body: some View {
        DiscoveryCachedImage(
            discoveryId: discoveryId,
            remoteURL: url
        ) { phase in
            ZStack {
                placeholder

                switch phase {
                case .success(let platformImage):
                    platformImageView(for: platformImage)
                        .resizable()
                        .scaledToFill()
                        .onAppear {
                            cacheIfNeeded(image: platformImage)
                        }
                case .loading, .empty:
                    EmptyView()
                case .failure:
                    EmptyView()
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private func cacheIfNeeded(image: DiscoveryPlatformImage) {
        guard !didCacheSnapshot else { return }
        didCacheSnapshot = true
        DiscoveryDetailImageCache.shared.store(image, for: discoveryId)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#20293A"),
                    Color(hex: "#141927")
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .opacity(0.25)
        }
    }

    private func platformImageView(for image: DiscoveryPlatformImage) -> Image {
#if canImport(UIKit)
        return Image(uiImage: image)
#elseif canImport(AppKit)
        return Image(nsImage: image)
#endif
    }
}
