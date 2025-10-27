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
        let heroVisibleHeight: CGFloat
        let heroBottomGlobalY: CGFloat
        let headerOffset: CGFloat
        let pullDownOffset: CGFloat
        let cornerRadius: CGFloat
        let containerWidth: CGFloat
        let safeAreaTopInset: CGFloat
        let contentOpacity: Double
        let backgroundOpacity: Double
        let heroOverlayOpacity: Double
        let scrollOverlayOpacity: Double
        let isChromeReady: Bool
        let isMarkdownReady: Bool
        let isScrollDisabled: Bool
        let isClosing: Bool
        let showTopControls: Bool
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
    let isDeleting: Bool
    let onDelete: (() -> Void)?
    let onShowOptions: (() -> Void)?
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    @Binding private var scrollOffset: CGFloat
    @State private var isOptionsPresented = false
    @State private var shareSheetPayload: DiscoveryDetailSharePayload?

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
        isDeleting: Bool,
        onDelete: (() -> Void)?,
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
        self.isDeleting = isDeleting
        self.onDelete = onDelete
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
                height: layout.heroHeight,
                pullDownOffset: layout.pullDownOffset,
                cornerRadius: layout.cornerRadius,
                width: layout.cardSize.width,
                namespace: nil,
                isGeometrySource: false,
                discoveryId: discovery.id
            )
            .offset(y: layout.headerOffset)

            DiscoveryDetailContentView(
                discovery: discovery,
                imageHeight: layout.heroImageHeight,
                headerOffset: layout.headerOffset,
                heroVisibleHeight: layout.heroVisibleHeight,
                heroBottomGlobalY: layout.heroBottomGlobalY,
                pullDownOffset: layout.pullDownOffset,
                backgroundColor: backgroundColor,
                backgroundOpacity: layout.backgroundOpacity,
                colorScheme: colorScheme,
                voiceoverController: voiceoverController,
                safeAreaInsets: safeAreaInsets,
                safeAreaTopInset: layout.safeAreaTopInset,
                containerWidth: layout.containerWidth,
                contentOpacity: layout.contentOpacity,
                isChromeReady: layout.isChromeReady,
                isMarkdownReady: layout.isMarkdownReady,
                isScrollDisabled: layout.isScrollDisabled,
                scrollOverlayOpacity: layout.scrollOverlayOpacity,
                overlayNamespace: overlayNamespace,
                isClosing: layout.isClosing,
                showTopControls: layout.showTopControls,
                onClose: onClose,
                onShowOptions: handleOptionsTapped,
                isOptionsEnabled: !isDeleting,
                scrollOffset: $scrollOffset,
                onShare: { presentShareSheet() },
                onShowMap: discovery.location != nil ? { openLocationIfAvailable() } : nil
            )
        }
        .frame(width: layout.cardSize.width, height: layout.cardSize.height)
        .background(backgroundColor.opacity(layout.backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
        .sheet(item: $shareSheetPayload) { payload in
            DiscoveryShareSheet(activityItems: payload.items)
        }
        .overlay {
            if isOptionsPresented {
                DiscoveryDetailOptionsSheet(
                    isPresented: $isOptionsPresented,
                    isDeleting: isDeleting,
                    onDelete: handleDeleteSelection
                )
            }
        }
        .onChange(of: isDeleting) { _, newValue in
            if newValue {
                isOptionsPresented = false
            }
        }
    }
}

private extension DiscoveryDetailView {
    var overlayGeometryId: String {
        "discovery-detail-overlay-\(discovery.id)"
    }

    func handleOptionsTapped() {
        guard !isDeleting else { return }
        isOptionsPresented = true
        onShowOptions?()
    }

    func handleDeleteSelection() {
        guard !isDeleting else { return }
        isOptionsPresented = false
        onDelete?()
    }

    func presentShareSheet() {
        Task {
            let handler = DiscoveryDetailShareHandler()
            let context = DiscoveryDetailShareContext(
                discovery: discovery,
                placeholderImage: placeholderImage,
                imageURL: imageURL
            )

            guard let payload = await handler.makeSharePayload(for: context) else { return }
            await MainActor.run {
                shareSheetPayload = payload
            }
        }
    }

    func openLocationIfAvailable() {
        DiscoveryDetailShareHandler().openLocationIfAvailable(from: discovery)
    }
}

private struct DiscoveryDetailContentView: View {
    let discovery: DiscoverySummary
    let imageHeight: CGFloat
    let headerOffset: CGFloat
    let heroVisibleHeight: CGFloat
    let heroBottomGlobalY: CGFloat
    let pullDownOffset: CGFloat
    let backgroundColor: Color
    let backgroundOpacity: Double
    let colorScheme: ColorScheme
    let safeAreaInsets: EdgeInsets
    let safeAreaTopInset: CGFloat
    let containerWidth: CGFloat
    let contentOpacity: Double
    let isChromeReady: Bool
    let isMarkdownReady: Bool
    let isScrollDisabled: Bool
    let scrollOverlayOpacity: Double
    let overlayNamespace: Namespace.ID
    let isClosing: Bool
    let showTopControls: Bool
    let onClose: (() -> Void)?
    let onShowOptions: (() -> Void)?
    let isOptionsEnabled: Bool
    let onShare: (() -> Void)?
    let onShowMap: (() -> Void)?
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    // Player inset store is not required when using a bottom safeAreaInset.
    @Binding var scrollOffset: CGFloat
    @State private var baselineOffset: CGFloat?
    // no external measurement needed

    init(
        discovery: DiscoverySummary,
        imageHeight: CGFloat,
        headerOffset: CGFloat,
        heroVisibleHeight: CGFloat,
        heroBottomGlobalY: CGFloat,
        pullDownOffset: CGFloat,
        backgroundColor: Color,
        backgroundOpacity: Double,
        colorScheme: ColorScheme,
        voiceoverController: VoiceoverPlaybackController,
        safeAreaInsets: EdgeInsets,
        safeAreaTopInset: CGFloat,
        containerWidth: CGFloat,
        contentOpacity: Double,
        isChromeReady: Bool,
        isMarkdownReady: Bool,
        isScrollDisabled: Bool,
        scrollOverlayOpacity: Double,
        overlayNamespace: Namespace.ID,
        isClosing: Bool,
        showTopControls: Bool,
        onClose: (() -> Void)? = nil,
        onShowOptions: (() -> Void)? = nil,
        isOptionsEnabled: Bool = true,
        scrollOffset: Binding<CGFloat>,
        onShare: (() -> Void)? = nil,
        onShowMap: (() -> Void)? = nil
    ) {
        self.discovery = discovery
        self.imageHeight = imageHeight
        self.headerOffset = headerOffset
        self.heroVisibleHeight = heroVisibleHeight
        self.heroBottomGlobalY = heroBottomGlobalY
        self.pullDownOffset = pullDownOffset
        self.backgroundColor = backgroundColor
        self.backgroundOpacity = backgroundOpacity
        self.colorScheme = colorScheme
        self.safeAreaInsets = safeAreaInsets
        self.safeAreaTopInset = safeAreaTopInset
        self.containerWidth = containerWidth
        self.contentOpacity = contentOpacity
        self.isChromeReady = isChromeReady
        self.isMarkdownReady = isMarkdownReady
        self.isScrollDisabled = isScrollDisabled
        self.scrollOverlayOpacity = scrollOverlayOpacity
        self.overlayNamespace = overlayNamespace
        self.isClosing = isClosing
        self.showTopControls = showTopControls
        self.onClose = onClose
        self.onShowOptions = onShowOptions
        self.isOptionsEnabled = isOptionsEnabled
        self.onShare = onShare
        self.onShowMap = onShowMap
        _voiceoverController = ObservedObject(initialValue: voiceoverController)
        _scrollOffset = scrollOffset
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    private var headerLayoutHeight: CGFloat {
        imageHeight + safeAreaTopInset + pullDownOffset
    }

    private var headerOverlayHeight: CGFloat { imageHeight + safeAreaTopInset }

    // Overlay Y offset derived analytically from hero geometry:
    // offset = headerOffset - pullDownOffset, keeping the overlay pinned.
    private var overlayYOffset: CGFloat { headerOffset - pullDownOffset }

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
                        contentWidth: containerWidth,
                        onShare: onShare,
                        onShowMap: onShowMap,
                        isClosing: isClosing,
                        showTopControls: showTopControls,
                        topControlsSafeAreaInsets: safeAreaInsets,
                        onClose: onClose,
                        onShowOptions: onShowOptions,
                        isOptionsEnabled: isOptionsEnabled
                    )
                    .frame(height: heroVisibleHeight)
                    .offset(y: overlayYOffset)
                    // Prevent any position-based animations: only fade
                    .animation(nil, value: overlayYOffset)
                    .animation(nil, value: heroVisibleHeight)
                    .transaction { $0.animation = nil }
                    .opacity(scrollOverlayOpacity)
                    .allowsHitTesting(isChromeReady)
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

    private var additionalBottomPadding: CGFloat { 0 }

    @ViewBuilder
    private func detailDescriptionView(isReady: Bool) -> some View {
        if let description = discovery.detailDescription, !description.isEmpty {
            if isReady {
                #if canImport(MarkdownUI)
                Markdown(description)
                    .markdownTheme(BrandMarkdownThemeFactory.discoveryDetailTheme(for: palette))
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
private extension DiscoveryDetailContentView {
    var overlayGeometryId: String {
        "discovery-detail-overlay-\(discovery.id)"
    }
}
