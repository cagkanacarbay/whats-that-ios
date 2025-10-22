import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared
import MarkdownUI

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
        let heroOverlayOpacity: Double
        let scrollOverlayOpacity: Double
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
    let overlayNamespace: Namespace.ID
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
        overlayNamespace: Namespace.ID,
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
        self.overlayNamespace = overlayNamespace
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
                imageURL: imageURL,
                placeholderImage: placeholderImage,
                preferPlaceholderImage: layout.preferPlaceholderImage,
                height: layout.heroHeight,
                pullDownOffset: layout.pullDownOffset,
                cornerRadius: layout.cornerRadius,
                width: layout.cardSize.width,
                namespace: nil,
                isGeometrySource: false,
                discoveryId: discovery.id
            )
            .overlay(alignment: .bottom) {
                DiscoveryHeaderOverlayView(
                    discovery: discovery,
                    palette: palette,
                    maxDescriptionLines: 3,
                    gradientFalloff: 0.55,
                    contentWidth: layout.cardSize.width
                )
                .frame(height: layout.heroHeight)
                .opacity(layout.heroOverlayOpacity)
                .matchedGeometryEffect(
                    id: overlayGeometryId,
                    in: overlayNamespace,
                    properties: .frame,
                    anchor: .bottom,
                    isSource: !layout.isChromeReady
                )
            }
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
                scrollOverlayOpacity: layout.scrollOverlayOpacity,
                overlayNamespace: overlayNamespace,
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

private extension DiscoveryDetailView {
    var overlayGeometryId: String {
        "discovery-detail-overlay-\(discovery.id)"
    }
}

private struct DiscoveryDetailContentView: View {
    let discovery: DiscoverySummary
    let imageHeight: CGFloat
    let pullDownOffset: CGFloat
    let backgroundColor: Color
    let backgroundOpacity: Double
    let colorScheme: ColorScheme
    let safeAreaTopInset: CGFloat
    let containerWidth: CGFloat
    let contentOpacity: Double
    let isChromeReady: Bool
    let isMarkdownReady: Bool
    let isScrollDisabled: Bool
    let scrollOverlayOpacity: Double
    let overlayNamespace: Namespace.ID
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    @Binding var scrollOffset: CGFloat
    @State private var baselineOffset: CGFloat?

    init(
        discovery: DiscoverySummary,
        imageHeight: CGFloat,
        pullDownOffset: CGFloat,
        backgroundColor: Color,
        backgroundOpacity: Double,
        colorScheme: ColorScheme,
        voiceoverController: VoiceoverPlaybackController,
        safeAreaTopInset: CGFloat,
        containerWidth: CGFloat,
        contentOpacity: Double,
        isChromeReady: Bool,
        isMarkdownReady: Bool,
        isScrollDisabled: Bool,
        scrollOverlayOpacity: Double,
        overlayNamespace: Namespace.ID,
        scrollOffset: Binding<CGFloat>
    ) {
        self.discovery = discovery
        self.imageHeight = imageHeight
        self.pullDownOffset = pullDownOffset
        self.backgroundColor = backgroundColor
        self.backgroundOpacity = backgroundOpacity
        self.colorScheme = colorScheme
        self.safeAreaTopInset = safeAreaTopInset
        self.containerWidth = containerWidth
        self.contentOpacity = contentOpacity
        self.isChromeReady = isChromeReady
        self.isMarkdownReady = isMarkdownReady
        self.isScrollDisabled = isScrollDisabled
        self.scrollOverlayOpacity = scrollOverlayOpacity
        self.overlayNamespace = overlayNamespace
        _voiceoverController = ObservedObject(initialValue: voiceoverController)
        _scrollOffset = scrollOffset
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    private var headerLayoutHeight: CGFloat {
        imageHeight + safeAreaTopInset + pullDownOffset
    }

    private var headerOverlayHeight: CGFloat {
        imageHeight + safeAreaTopInset
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: HeroScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named("hero-scroll")).minY
                    )
            }
            .frame(height: 0)

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Color.clear
                        .frame(height: headerLayoutHeight)
                        .clipped()

                    DiscoveryHeaderOverlayView(
                        discovery: discovery,
                        palette: palette,
                        maxDescriptionLines: 3,
                        gradientFalloff: 0.55,
                        contentWidth: containerWidth
                    )
                    .frame(height: headerOverlayHeight)
                    .opacity(scrollOverlayOpacity)
                    .matchedGeometryEffect(
                        id: overlayGeometryId,
                        in: overlayNamespace,
                        properties: .frame,
                        anchor: .bottom,
                        isSource: isChromeReady
                    )
                    .allowsHitTesting(false)
                }

                if isChromeReady {
                    VStack(alignment: .leading, spacing: BrandSpacing.large) {
                        VoiceoverDetailButton(
                            discovery: discovery,
                            controller: voiceoverController,
                            palette: palette
                        )

                        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
                            Text(discovery.title)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(textColor)

                            detailDescriptionView(isReady: isMarkdownReady)
                        }
                    }
                    .padding(.top, BrandSpacing.large)
                    .padding(.horizontal, BrandSpacing.large)
                    .padding(
                        .bottom,
                        BrandSpacing.xLarge * 2 + additionalBottomPadding
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(backgroundColor.opacity(backgroundOpacity))
                    .opacity(contentOpacity)
                }
            }
        }
        .id(discovery.id)
        .coordinateSpace(name: "hero-scroll")
        .frame(width: containerWidth)
        .contentMargins(.all, 0, for: .scrollContent)
        .conditionalScrollDisabled(isScrollDisabled)
        .onPreferenceChange(HeroScrollOffsetPreferenceKey.self) { value in
            if baselineOffset == nil {
                baselineOffset = value
            }
            let adjusted = value - (baselineOffset ?? 0)
            scrollOffset = adjusted
        }
        .onAppear {
            voiceoverController.ensureMetadata(for: discovery)
        }
        .onChange(of: discovery.id) { _, _ in
            scrollOffset = 0
            baselineOffset = nil
        }
    }

    private var textColor: Color {
        palette.textPrimary
    }

    private var additionalBottomPadding: CGFloat {
        switch voiceoverController.playbackState {
        case .idle, .unavailable:
            return 0
        default:
            return 132
        }
    }

    @ViewBuilder
    private func detailDescriptionView(isReady: Bool) -> some View {
        if let description = discovery.detailDescription, !description.isEmpty {
            if isReady {
                #if canImport(MarkdownUI)
                Markdown(description)
                    .markdownTheme(BrandMarkdownThemeFactory.discoveryDetailTheme(for: palette))
                    .textSelection(.enabled)
                #else
                Text(description)
                    .font(.system(size: 16))
                    .foregroundStyle(palette.textSecondary)
                #endif
            }
        } else {
            Text(discovery.highlight)
                .font(.system(size: 16))
                .foregroundStyle(palette.textSecondary)
        }
    }
}

private struct DiscoveryDetailTopControls: View {
    let safeAreaInsets: EdgeInsets
    let onClose: () -> Void
    let onShowOptions: (() -> Void)?

    var body: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(14)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)

            Spacer()

            if let onShowOptions {
                Button(action: onShowOptions) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(Color.white)
                        .padding(14)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, BrandSpacing.large)
        .padding(.top, resolvedTopPadding(from: safeAreaInsets))
        .padding(.bottom, BrandSpacing.small)
        .zIndex(2)
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
            return globalInset + 12
        }
        return baseInset + 12
    }
}

private extension DiscoveryDetailContentView {
    var overlayGeometryId: String {
        "discovery-detail-overlay-\(discovery.id)"
    }
}
