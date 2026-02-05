import SwiftUI
import WhatsThatShared
import UIKit

struct DiscoveryCardImageView: View {
    let discoveryId: Int64
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    @State private var didCacheSnapshot = false
    @State private var animateShimmer = false

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

            // Shimmer overlay
            LinearGradient(
                colors: [
                    Color.gray.opacity(0.1),
                    Color.gray.opacity(0.3),
                    Color.gray.opacity(0.1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .mask {
                Rectangle()
                    .fill(Color.white.opacity(animateShimmer ? 1 : 0))
                    .blur(radius: 40)
                    .offset(x: animateShimmer ? width : -width)
            }
            .animation(
                .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: false),
                value: animateShimmer
            )

            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .opacity(0.25)
        }
        .onAppear {
            animateShimmer = true
        }
    }

    private func platformImageView(for image: DiscoveryPlatformImage) -> Image {
        Image(uiImage: image)
    }
}
