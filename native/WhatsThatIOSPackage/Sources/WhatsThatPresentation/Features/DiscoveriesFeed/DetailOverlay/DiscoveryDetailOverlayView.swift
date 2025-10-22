import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared
#if canImport(MarkdownUI)
import MarkdownUI

struct DiscoveryDetailOverlayView: View {
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    let context: DiscoveryDetailContext
    let destinationFrame: CGRect
    let progress: CGFloat
    let contentOpacity: Double
    let isContentReady: Bool
    let isClosing: Bool
    let isInteracting: Bool
    let gestureTranslation: CGSize
    let gestureScale: CGFloat
    let gestureRotation: Double
    let gestureShadowOpacity: Double
    let gestureCornerRadius: CGFloat
    let closeStartTranslation: CGSize
    let closeStartScale: CGFloat
    let closeStartRotation: Double
    let backgroundColor: Color
    let colorScheme: ColorScheme
    let onClose: () -> Void
    let onShowOptions: (() -> Void)?
    @State private var scrollOffset: CGFloat = 0

    init(
        context: DiscoveryDetailContext,
        destinationFrame: CGRect,
        progress: CGFloat,
        contentOpacity: Double,
        isContentReady: Bool,
        isClosing: Bool,
        isInteracting: Bool,
        gestureTranslation: CGSize,
        gestureScale: CGFloat,
        gestureRotation: Double,
        gestureShadowOpacity: Double,
        gestureCornerRadius: CGFloat,
        closeStartTranslation: CGSize,
        closeStartScale: CGFloat,
        closeStartRotation: Double,
        backgroundColor: Color,
        colorScheme: ColorScheme,
        voiceoverController: VoiceoverPlaybackController,
        onClose: @escaping () -> Void,
        onShowOptions: (() -> Void)?
    ) {
        self.context = context
        self.destinationFrame = destinationFrame
        self.progress = progress
        self.contentOpacity = contentOpacity
        self.isContentReady = isContentReady
        self.isClosing = isClosing
        self.isInteracting = isInteracting
        self.gestureTranslation = gestureTranslation
        self.gestureScale = gestureScale
        self.gestureRotation = gestureRotation
        self.gestureShadowOpacity = gestureShadowOpacity
        self.gestureCornerRadius = gestureCornerRadius
        self.closeStartTranslation = closeStartTranslation
        self.closeStartScale = closeStartScale
        self.closeStartRotation = closeStartRotation
        self.backgroundColor = backgroundColor
        self.colorScheme = colorScheme
        self.onClose = onClose
        self.onShowOptions = onShowOptions
        _voiceoverController = ObservedObject(initialValue: voiceoverController)
    }

    var body: some View {
        GeometryReader { proxy in
            let safeAreaInsets = proxy.safeAreaInsets
            let containerFrameRaw = proxy.frame(in: .global)
            let containerFrame = containerFrameRaw.offsetBy(dx: 0, dy: -safeAreaInsets.top)
            let screenBounds = UIScreen.main.bounds
            let rawWidth = proxy.size.width == 0 ? screenBounds.width : proxy.size.width
            let containerWidth = min(rawWidth, screenBounds.width)
            let rawHeight = proxy.size.height == 0 ? screenBounds.height : proxy.size.height
            let containerSize = CGSize(width: containerWidth, height: rawHeight + safeAreaInsets.top)
            let geometry = DiscoveryDetailHeroGeometry(
                startFrame: context.startFrame,
                containerSize: containerSize,
                containerOrigin: CGPoint(x: 0, y: containerFrame.origin.y),
                targetAspectRatio: context.cardAspectRatio,
                progress: progress,
                targetExpandedHeightFraction: DiscoveryDetailLayout.expandedImageHeightFraction,
                enforceAspectForImage: isClosing,
                isClosing: isClosing
            )

            ZStack(alignment: .topLeading) {
                Color.black
                    .opacity(overlayOpacity(for: progress))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                let baseCornerRadius = geometry.cornerRadius
                let combinedCornerRadius = min(
                    DiscoveryDetailLayout.cardCornerRadius,
                    max(baseCornerRadius, gestureCornerRadius)
                )
                let combinedShadowOpacity = min(1, geometry.shadowOpacity + gestureShadowOpacity)
                let gestureShadowRadius: CGFloat = gestureShadowOpacity > 0 ? 20 : 0
                let combinedShadowRadius = max(geometry.shadowRadius, gestureShadowRadius)
                let combinedShadowYOffset = geometry.shadowYOffset > 0
                    ? geometry.shadowYOffset
                    : (gestureShadowOpacity > 0 ? 12 : 0)
                let finalOffsetX = geometry.offset.x + gestureTranslation.width
                let finalOffsetY = geometry.offset.y + gestureTranslation.height
                let finalScale = gestureScale
                let rotationAngle = gestureRotation
                let transformProgress = DiscoveryDetailUniformCloseTransform.transformProgress(for: progress)
                let uniformCloseScale = DiscoveryDetailUniformCloseTransform.resolvedScale(
                    transformProgress: transformProgress,
                    startFrame: destinationFrame,
                    containerFrame: containerFrame,
                    initialScale: closeStartScale
                )
                let appliedScale = isClosing ? uniformCloseScale : finalScale
                let maskCornerRadius = resolvedCornerRadius(
                    targetCornerRadius: combinedCornerRadius,
                    scale: appliedScale
                )
                let isChromeReady = isContentReady && !isClosing
                let detailOpacity = isChromeReady ? contentOpacity : 0
                let headerOpacityRaw: Double = {
                    guard !isClosing && !isInteracting else { return 0 }
                    let start: CGFloat = 0.88
                    let t = max(0, min((progress - start) / (1 - start), 1))
                    return Double(t)
                }()
                let headerOverlayOpacity: Double = isChromeReady ? (isClosing || isInteracting ? 0 : 1) : headerOpacityRaw
                let widthDrivenCardHeight = min(containerSize.height, containerSize.width * context.cardAspectRatio)
                let cardWidth: CGFloat = isClosing ? containerSize.width : geometry.size.width
                let cardHeight: CGFloat = isClosing ? widthDrivenCardHeight : geometry.size.height
                let imageHeightForView: CGFloat = isClosing ? widthDrivenCardHeight : geometry.imageHeight
                let effectivePullDown = (isClosing || !isChromeReady) ? 0 : max(scrollOffset, 0)
                let preferPlaceholder = (!isChromeReady) || isInteracting

                let _ = logDiscoveryDetailHeroGeometry(
                    phase: isClosing ? "close" : (isChromeReady ? "settled" : "open"),
                    progress: progress,
                    containerSize: containerSize,
                    startFrame: destinationFrame,
                    width: cardWidth,
                    height: cardHeight,
                    imageHeight: imageHeightForView,
                    cardAspect: context.cardAspectRatio,
                    preferPlaceholder: preferPlaceholder,
                    pullDown: effectivePullDown,
                    isChromeReady: isChromeReady,
                    isClosing: isClosing
                )

                let headerOffset = (isClosing || isInteracting) ? 0 : min(scrollOffset, 0)
                let heroHeaderHeight = isClosing ? imageHeightForView : imageHeightForView + safeAreaInsets.top

                let heroHeader = DiscoveryHeroHeaderView(
                    discovery: context.discovery,
                    imageURL: context.imageURL,
                    placeholderImage: context.placeholderImage,
                    preferPlaceholderImage: (!isChromeReady) || isInteracting,
                    height: heroHeaderHeight,
                    pullDownOffset: effectivePullDown,
                    cornerRadius: maskCornerRadius,
                    width: cardWidth,
                    namespace: nil,
                    isGeometrySource: false,
                    discoveryId: context.discovery.id,
                    palette: BrandTheme.palette(for: colorScheme),
                    gradientFalloff: 0.55,
                    maxDescriptionLines: 3,
                    overlayOpacity: headerOverlayOpacity
                )
                .offset(y: headerOffset)

                let heroCard = ZStack(alignment: .top) {
                    heroHeader

                    DiscoveryDetailContentView(
                        discovery: context.discovery,
                        imageHeight: imageHeightForView,
                        pullDownOffset: effectivePullDown,
                        backgroundColor: backgroundColor,
                        colorScheme: colorScheme,
                        voiceoverController: voiceoverController,
                        safeAreaTopInset: safeAreaInsets.top,
                        containerWidth: containerWidth,
                        contentOpacity: detailOpacity,
                        isChromeReady: isChromeReady,
                        isMarkdownReady: isChromeReady,
                        isScrollDisabled: !isChromeReady || isInteracting || isClosing,
                        scrollOffset: $scrollOffset
                    )
                }
                .frame(width: cardWidth, height: cardHeight)
                .background(isClosing ? Color.clear : backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: maskCornerRadius, style: .continuous))

                heroCard
                    .overlay(alignment: .topLeading) {
                        if isChromeReady {
                            DiscoveryDetailTopControls(
                                safeAreaInsets: safeAreaInsets,
                                onClose: onClose,
                                onShowOptions: onShowOptions
                            )
                            .opacity(detailOpacity)
                            .animation(.easeInOut(duration: 0.12), value: detailOpacity)
                            .ignoresSafeArea()
                        }
                    }
                    .shadow(
                        color: Color.black.opacity(combinedShadowOpacity),
                        radius: combinedShadowRadius,
                        x: 0,
                        y: combinedShadowYOffset
                    )
                    .modifier(
                        DiscoveryDetailUniformCloseTransform(
                            isClosing: isClosing,
                            progress: progress,
                            startFrame: destinationFrame,
                            containerFrame: containerFrame,
                            initialScale: closeStartScale,
                            initialOffset: closeStartTranslation,
                            initialRotation: closeStartRotation,
                            baseWidth: cardWidth,
                            baseHeight: cardHeight
                        )
                    )
                    .applyingIf(!isClosing) { view in
                        view
                            .scaleEffect(finalScale, anchor: .center)
                            .rotation3DEffect(.degrees(rotationAngle), axis: (x: 0, y: 1, z: 0))
                            .offset(x: finalOffsetX, y: finalOffsetY)
                    }
                    .animation(.easeInOut(duration: 0.24), value: isChromeReady)
            }
        }
        .onChange(of: isClosing) { _, closing in
            guard closing, scrollOffset != 0 else { return }
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.9, blendDuration: 0.2)) {
                scrollOffset = 0
            }
        }
    }

    private func resolvedCornerRadius(targetCornerRadius: CGFloat, scale: CGFloat) -> CGFloat {
        let safeScale = scale.isFinite ? max(scale, 0.0001) : 1
        return targetCornerRadius / safeScale
    }

    private func overlayOpacity(for progress: CGFloat) -> Double {
        let clamped = max(0, min(Double(progress), 1))
        if clamped <= 0.2 {
            return clamped / 0.2 * 0.4
        } else if clamped <= 0.5 {
            let local = (clamped - 0.2) / 0.3
            return 0.4 + local * (0.7 - 0.4)
        } else {
            let local = (clamped - 0.5) / 0.5
            return 0.7 + local * (0.9 - 0.7)
        }
    }

    private func cardChromeOpacity(for progress: CGFloat, isClosing: Bool) -> Double {
        if isClosing { return 0 }

        let clamped = max(0, min(progress, 1))
        return clamped < 0.001 ? 1 : 0
    }
}

private struct DiscoveryDetailContentView: View {
    let discovery: DiscoverySummary
    let imageHeight: CGFloat
    let pullDownOffset: CGFloat
    let backgroundColor: Color
    let colorScheme: ColorScheme
    let safeAreaTopInset: CGFloat
    let containerWidth: CGFloat
    let contentOpacity: Double
    let isChromeReady: Bool
    let isMarkdownReady: Bool
    let isScrollDisabled: Bool
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    @Binding var scrollOffset: CGFloat
    @State private var baselineOffset: CGFloat?

    init(
        discovery: DiscoverySummary,
        imageHeight: CGFloat,
        pullDownOffset: CGFloat,
        backgroundColor: Color,
        colorScheme: ColorScheme,
        voiceoverController: VoiceoverPlaybackController,
        safeAreaTopInset: CGFloat,
        containerWidth: CGFloat,
        contentOpacity: Double,
        isChromeReady: Bool,
        isMarkdownReady: Bool,
        isScrollDisabled: Bool,
        scrollOffset: Binding<CGFloat>
    ) {
        self.discovery = discovery
        self.imageHeight = imageHeight
        self.pullDownOffset = pullDownOffset
        self.backgroundColor = backgroundColor
        self.colorScheme = colorScheme
        self.safeAreaTopInset = safeAreaTopInset
        self.containerWidth = containerWidth
        self.contentOpacity = contentOpacity
        self.isChromeReady = isChromeReady
        self.isMarkdownReady = isMarkdownReady
        self.isScrollDisabled = isScrollDisabled
        _voiceoverController = ObservedObject(initialValue: voiceoverController)
        _scrollOffset = scrollOffset
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    private var headerLayoutHeight: CGFloat {
        imageHeight + safeAreaTopInset + pullDownOffset
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
                Color.clear
                    .frame(height: headerLayoutHeight)
                    .clipped()

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
                    .background(backgroundColor)
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
#endif
