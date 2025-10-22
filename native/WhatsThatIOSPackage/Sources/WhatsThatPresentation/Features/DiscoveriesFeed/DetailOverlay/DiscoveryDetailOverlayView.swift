import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared
import MarkdownUI

struct DiscoveryDetailOverlayView: View {
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    let context: DiscoveryDetailContext
    let destinationFrame: CGRect
    let progress: CGFloat
    let dismissProgress: CGFloat
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
        dismissProgress: CGFloat,
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
        self.dismissProgress = dismissProgress
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
                let normalizedDismiss = max(0, min(dismissProgress, 1))
                let collapseThreshold: CGFloat = 0.005
                let shouldCollapse = isClosing || normalizedDismiss > collapseThreshold
                let collapseProgress: CGFloat = shouldCollapse ? 1 : 0
                let cardBackgroundOpacity = Double(max(0, min(1 - collapseProgress, 1)))
                let headerOpacityRaw: Double = {
                    guard !isClosing && !isInteracting else { return 0 }
                    let start: CGFloat = 0.88
                    let t = max(0, min((progress - start) / (1 - start), 1))
                    return Double(t)
                }()
                let headerOverlayOpacity: Double = isChromeReady ? (isClosing || isInteracting ? 0 : 1) : headerOpacityRaw
                let widthDrivenCardHeight = min(containerSize.height, containerSize.width * context.cardAspectRatio)
                let cardWidth: CGFloat = isClosing ? containerSize.width : geometry.size.width
                let imageHeightForView: CGFloat = isClosing ? widthDrivenCardHeight : geometry.imageHeight
                let expandedCardHeight = geometry.size.height
                let collapsedCardHeight = imageHeightForView
                let interactiveCardHeight = collapsedCardHeight
                    + (expandedCardHeight - collapsedCardHeight) * (1 - collapseProgress)
                let cardHeight: CGFloat = isClosing ? widthDrivenCardHeight : interactiveCardHeight
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

                let headerOffset = (isClosing || isInteracting || shouldCollapse) ? 0 : min(scrollOffset, 0)
                let heroTopInset = isClosing ? 0 : safeAreaInsets.top * (1 - collapseProgress)
                let heroHeaderHeight = imageHeightForView + heroTopInset

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
                    headerOverlayOpacity: headerOverlayOpacity,
                    preferPlaceholderImage: preferPlaceholder,
                    isChromeReady: isChromeReady,
                    isMarkdownReady: isChromeReady,
                    isScrollDisabled: !isChromeReady || isInteracting || isClosing
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
                    scrollOffset: $scrollOffset,
                    onClose: onClose,
                    onShowOptions: onShowOptions
                )
                .animation(.easeOut(duration: 0.12), value: shouldCollapse)

                heroCard
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
}
