import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared

struct DiscoveryDetailView: View {
    struct LayoutConfiguration {
        let cardSize: CGSize
        let heroHeight: CGFloat
        let heroImageHeight: CGFloat
        let headerOffset: CGFloat
        let pullDownOffset: CGFloat
        let cornerRadius: CGFloat
        let containerWidth: CGFloat
        let safeAreaTopInset: CGFloat
        let contentOpacity: Double
        let backgroundOpacity: Double
        let headerOverlayOpacity: Double
        let preferPlaceholderImage: Bool
        let isChromeReady: Bool
        let isMarkdownReady: Bool
        let isScrollDisabled: Bool
    }

    let discovery: DiscoverySummary
    let imageURL: URL?
    let placeholderImage: UIImage?
    let backgroundColor: Color
    let colorScheme: ColorScheme
    let layout: LayoutConfiguration
    let safeAreaInsets: EdgeInsets
    let onClose: () -> Void
    let onShowOptions: (() -> Void)?
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    @Binding private var scrollOffset: CGFloat

    init(
        discovery: DiscoverySummary,
        imageURL: URL?,
        placeholderImage: UIImage?,
        backgroundColor: Color,
        colorScheme: ColorScheme,
        layout: LayoutConfiguration,
        safeAreaInsets: EdgeInsets,
        voiceoverController: VoiceoverPlaybackController,
        scrollOffset: Binding<CGFloat>,
        onClose: @escaping () -> Void,
        onShowOptions: (() -> Void)?
    ) {
        self.discovery = discovery
        self.imageURL = imageURL
        self.placeholderImage = placeholderImage
        self.backgroundColor = backgroundColor
        self.colorScheme = colorScheme
        self.layout = layout
        self.safeAreaInsets = safeAreaInsets
        self.onClose = onClose
        self.onShowOptions = onShowOptions
        _voiceoverController = ObservedObject(initialValue: voiceoverController)
        _scrollOffset = scrollOffset
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DiscoveryHeroHeaderView(
                discovery: discovery,
                imageURL: imageURL,
                placeholderImage: placeholderImage,
                preferPlaceholderImage: layout.preferPlaceholderImage,
                height: layout.heroHeight,
                pullDownOffset: layout.pullDownOffset,
                cornerRadius: layout.cornerRadius,
                width: layout.cardSize.width,
                namespace: nil,
                isGeometrySource: false,
                discoveryId: discovery.id,
                palette: palette,
                gradientFalloff: 0.55,
                maxDescriptionLines: 3,
                overlayOpacity: layout.headerOverlayOpacity
            )
            .offset(y: layout.headerOffset)

            DiscoveryDetailContentView(
                discovery: discovery,
                imageHeight: layout.heroImageHeight,
                pullDownOffset: layout.pullDownOffset,
                backgroundColor: backgroundColor,
                backgroundOpacity: layout.backgroundOpacity,
                colorScheme: colorScheme,
                voiceoverController: voiceoverController,
                safeAreaTopInset: layout.safeAreaTopInset,
                containerWidth: layout.containerWidth,
                contentOpacity: layout.contentOpacity,
                isChromeReady: layout.isChromeReady,
                isMarkdownReady: layout.isMarkdownReady,
                isScrollDisabled: layout.isScrollDisabled,
                scrollOffset: $scrollOffset
            )
        }
        .frame(width: layout.cardSize.width, height: layout.cardSize.height)
        .background(backgroundColor.opacity(layout.backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
        .overlay(alignment: .topLeading) {
            if layout.isChromeReady {
                DiscoveryDetailTopControls(
                    safeAreaInsets: safeAreaInsets,
                    onClose: onClose,
                    onShowOptions: onShowOptions
                )
                .opacity(layout.contentOpacity)
                .animation(.easeInOut(duration: 0.12), value: layout.contentOpacity)
                .ignoresSafeArea()
            }
        }
    }
}
