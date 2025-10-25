import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared
import MarkdownUI

struct DiscoveryDetailOverlayView: View {
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    @Namespace private var overlayNamespace
    let snapshot: DiscoveryDetailOverlaySnapshot
    let destinationFrame: CGRect
    let backgroundColor: Color
    let colorScheme: ColorScheme
    let onClose: () -> Void
    let onShowOptions: (() -> Void)?
    @State private var scrollOffset: CGFloat = 0

    init(
        snapshot: DiscoveryDetailOverlaySnapshot,
        destinationFrame: CGRect,
        backgroundColor: Color,
        colorScheme: ColorScheme,
        voiceoverController: VoiceoverPlaybackController,
        onClose: @escaping () -> Void,
        onShowOptions: (() -> Void)?
    ) {
        self.snapshot = snapshot
        self.destinationFrame = destinationFrame
        self.backgroundColor = backgroundColor
        self.colorScheme = colorScheme
        self.onClose = onClose
        self.onShowOptions = onShowOptions
        _voiceoverController = ObservedObject(initialValue: voiceoverController)
    }

    var body: some View {
        Group {
            if let context = snapshot.context {
                overlayContent(context: context)
            } else {
                EmptyView()
            }
        }
    }

    private func overlayContent(context: DiscoveryDetailContext) -> some View {
        GeometryReader { proxy in
            let safeAreaInsets = proxy.safeAreaInsets
            let containerFrameRaw = proxy.frame(in: .global)
            let containerFrame = containerFrameRaw.offsetBy(dx: 0, dy: -safeAreaInsets.top)
            let screenBounds = UIScreen.main.bounds
            let rawWidth = proxy.size.width == 0 ? screenBounds.width : proxy.size.width
            let containerWidth = min(rawWidth, screenBounds.width)
            let rawHeight = proxy.size.height == 0 ? screenBounds.height : proxy.size.height
            let containerSize = CGSize(width: containerWidth, height: rawHeight + safeAreaInsets.top)
            let containerOrigin = CGPoint(x: 0, y: containerFrame.origin.y)
            let geometry = DiscoveryDetailHeroGeometry(
                startFrame: context.startFrame,
                containerSize: containerSize,
                containerOrigin: containerOrigin,
                targetAspectRatio: context.cardAspectRatio,
                progress: snapshot.progress,
                targetExpandedHeightFraction: DiscoveryDetailLayout.expandedImageHeightFraction,
                enforceAspectForImage: snapshot.isClosing,
                isClosing: snapshot.isClosing
            )
            let transformProgress = DiscoveryDetailUniformCloseTransform.transformProgress(for: snapshot.progress)

            ZStack(alignment: .topLeading) {
                Color.black
                    .opacity(overlayOpacity(for: snapshot.progress))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                let baseCornerRadius = geometry.cornerRadius
                let combinedCornerRadius = min(
                    DiscoveryDetailLayout.cardCornerRadius,
                    max(baseCornerRadius, snapshot.gestureCornerRadius)
                )
                let combinedShadowOpacity = min(1, geometry.shadowOpacity + snapshot.gestureShadowOpacity)
                let gestureShadowRadius: CGFloat = snapshot.gestureShadowOpacity > 0 ? 20 : 0
                let combinedShadowRadius = max(geometry.shadowRadius, gestureShadowRadius)
                let combinedShadowYOffset = geometry.shadowYOffset > 0
                    ? geometry.shadowYOffset
                    : (snapshot.gestureShadowOpacity > 0 ? 12 : 0)
                let finalOffsetX = geometry.offset.x + snapshot.gestureTranslation.width
                let finalOffsetY = geometry.offset.y + snapshot.gestureTranslation.height
                let finalScale = snapshot.gestureScale
                let rotationAngle = snapshot.gestureRotation
                let uniformCloseScale = DiscoveryDetailUniformCloseTransform.resolvedScale(
                    transformProgress: transformProgress,
                    startFrame: destinationFrame,
                    containerFrame: containerFrame,
                    initialScale: snapshot.closeStartScale
                )
                let appliedScale = snapshot.isClosing ? uniformCloseScale : finalScale
                let maskCornerRadius = resolvedCornerRadius(
                    targetCornerRadius: combinedCornerRadius,
                    scale: appliedScale
                )
                let collapseProgress = snapshot.isClosing ? transformProgress : 0
                let isChromeReady = snapshot.isContentReady
                let detailOpacityBase = isChromeReady ? snapshot.contentOpacity : 0
                let detailOpacity = detailOpacityBase * (snapshot.isClosing ? max(0, 1 - collapseProgress) : 1)
                let headerOpacityRaw: Double = {
                    guard !snapshot.isClosing && !snapshot.isInteracting else { return 0 }
                    let start: CGFloat = 0.88
                    let t = max(0, min((snapshot.progress - start) / (1 - start), 1))
                    return Double(t)
                }()
                let headerOverlayBaseOpacity: Double = {
                    if isChromeReady {
                        return 1
                    }
                    return headerOpacityRaw
                }()
                let overlayOpacities = resolvedOverlayOpacities(
                    detailOpacity: detailOpacity,
                    baseOpacity: headerOverlayBaseOpacity,
                    isChromeReady: isChromeReady,
                    isClosing: snapshot.isClosing,
                    isInteracting: snapshot.isInteracting
                )
                let cardWidth: CGFloat = snapshot.isClosing ? containerSize.width : geometry.size.width
                let targetImageHeight = geometry.imageHeight
                let closingImageHeight: CGFloat = {
                    let aspectHeight = cardWidth * context.cardAspectRatio
                    let minimumHeight = destinationFrame.height
                    let maximumHeight = containerSize.height
                    return min(max(aspectHeight, minimumHeight), maximumHeight)
                }()
                let imageHeightForView = snapshot.isClosing
                    ? targetImageHeight + (closingImageHeight - targetImageHeight) * collapseProgress
                    : targetImageHeight
                let expandedCardHeight = geometry.size.height
                let collapsedCardHeight = imageHeightForView
                let cardHeight = expandedCardHeight + (collapsedCardHeight - expandedCardHeight) * collapseProgress
                let cardBackgroundOpacity = Double(max(0, min(1 - collapseProgress, 1)))
                let effectivePullDown: CGFloat = (snapshot.isClosing || !isChromeReady)
                    ? 0
                    : max(scrollOffset, 0) * (1 - collapseProgress)
                let headerOffset: CGFloat = (snapshot.isClosing || snapshot.isInteracting)
                    ? 0
                    : min(scrollOffset, 0) * (1 - collapseProgress)
                let heroTopInset = safeAreaInsets.top * (1 - collapseProgress)
                let heroHeaderHeight = imageHeightForView + heroTopInset
                let fadeMultiplier = snapshot.isClosing ? max(0, 1 - collapseProgress) : 1
                let heroOverlayOpacity: Double = overlayOpacities.hero * fadeMultiplier
                let scrollOverlayOpacity: Double = overlayOpacities.scroll * fadeMultiplier

                let detailLayout = DiscoveryDetailView.LayoutConfiguration(
                    cardSize: CGSize(width: cardWidth, height: cardHeight),
                    heroHeight: heroHeaderHeight,
                    heroImageHeight: imageHeightForView,
                    headerOffset: headerOffset,
                    pullDownOffset: effectivePullDown,
                    cornerRadius: maskCornerRadius,
                    containerWidth: containerWidth,
                    safeAreaTopInset: heroTopInset,
                    contentOpacity: detailOpacity,
                    backgroundOpacity: cardBackgroundOpacity,
                    heroOverlayOpacity: heroOverlayOpacity,
                    scrollOverlayOpacity: scrollOverlayOpacity,
                    isChromeReady: isChromeReady,
                    isMarkdownReady: isChromeReady,
                    isScrollDisabled: snapshot.isClosing || snapshot.isInteracting || !isChromeReady
                )

                let heroCard = DiscoveryDetailView(
                    discovery: context.discovery,
                    imageURL: context.imageURL,
                    placeholderImage: context.placeholderImage,
                    backgroundColor: backgroundColor,
                    colorScheme: colorScheme,
                    layout: detailLayout,
                    safeAreaInsets: safeAreaInsets,
                    voiceoverController: voiceoverController,
                    overlayNamespace: overlayNamespace,
                    scrollOffset: $scrollOffset,
                    onClose: onClose,
                    onShowOptions: onShowOptions
                )

                heroCard
                    .shadow(
                        color: Color.black.opacity(combinedShadowOpacity),
                        radius: combinedShadowRadius,
                        x: 0,
                        y: combinedShadowYOffset
                    )
                    .modifier(
                        DiscoveryDetailUniformCloseTransform(
                            isClosing: snapshot.isClosing,
                            progress: snapshot.progress,
                            startFrame: destinationFrame,
                            containerFrame: containerFrame,
                            initialScale: snapshot.closeStartScale,
                            initialOffset: snapshot.closeStartTranslation,
                            initialRotation: snapshot.closeStartRotation,
                            baseWidth: cardWidth,
                            baseHeight: cardHeight
                        )
                    )
                    .applyingIf(!snapshot.isClosing) { view in
                        view
                            .scaleEffect(finalScale, anchor: .center)
                            .rotation3DEffect(.degrees(rotationAngle), axis: (x: 0, y: 1, z: 0))
                            .offset(x: finalOffsetX, y: finalOffsetY)
                    }
                    .animation(.easeInOut(duration: 0.24), value: isChromeReady)
            }
        }
        .onChange(of: snapshot.isClosing) { _, closing in
            guard closing, scrollOffset != 0 else { return }
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.9, blendDuration: 0.2)) {
                scrollOffset = 0
            }
        }
    }

    private func resolvedOverlayOpacities(
        detailOpacity: Double,
        baseOpacity: Double,
        isChromeReady: Bool,
        isClosing: Bool,
        isInteracting: Bool
    ) -> (hero: Double, scroll: Double) {
        if isClosing {
            return (hero: baseOpacity, scroll: 0)
        }
        guard isChromeReady else {
            return (hero: baseOpacity, scroll: 0)
        }
        if isInteracting {
            return (hero: baseOpacity, scroll: detailOpacity)
        }
        return (hero: 0, scroll: detailOpacity)
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
}
