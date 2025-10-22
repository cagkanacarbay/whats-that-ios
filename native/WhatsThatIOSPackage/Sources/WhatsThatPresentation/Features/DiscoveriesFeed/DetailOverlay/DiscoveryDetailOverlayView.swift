import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared
import MarkdownUI

struct DiscoveryDetailOverlayView: View {
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    @Namespace private var overlayNamespace
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
    @State private var closeBaselineImageHeight: CGFloat?

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
            let containerOrigin = CGPoint(x: 0, y: containerFrame.origin.y)
            let geometry = DiscoveryDetailHeroGeometry(
                startFrame: context.startFrame,
                containerSize: containerSize,
                containerOrigin: containerOrigin,
                targetAspectRatio: context.cardAspectRatio,
                progress: progress,
                targetExpandedHeightFraction: DiscoveryDetailLayout.expandedImageHeightFraction,
                enforceAspectForImage: isClosing,
                isClosing: isClosing
            )
            let openHeroImageHeight: CGFloat = {
                guard isClosing else { return geometry.imageHeight }
                let openGeometry = DiscoveryDetailHeroGeometry(
                    startFrame: context.startFrame,
                    containerSize: containerSize,
                    containerOrigin: containerOrigin,
                    targetAspectRatio: context.cardAspectRatio,
                    progress: progress,
                    targetExpandedHeightFraction: DiscoveryDetailLayout.expandedImageHeightFraction,
                    enforceAspectForImage: false,
                    isClosing: false
                )
                return openGeometry.imageHeight
            }()
            let baselineOpenImageHeight = resolvedCloseBaselineHeight(
                current: openHeroImageHeight,
                isClosing: isClosing
            )
            let transformProgress = DiscoveryDetailUniformCloseTransform.transformProgress(for: progress)
            let closeTransformProgress: CGFloat = isClosing ? transformProgress : 0

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
                let gestureCollapseProgress: CGFloat = normalizedDismiss > collapseThreshold ? 1 : 0
                let collapseProgress = isClosing ? closeTransformProgress : gestureCollapseProgress
                let isCollapseActive = collapseProgress > 0.0001
                let cardBackgroundOpacity = Double(max(0, min(1 - collapseProgress, 1)))
                let headerOpacityRaw: Double = {
                    guard !isClosing && !isInteracting else { return 0 }
                    let start: CGFloat = 0.88
                    let t = max(0, min((progress - start) / (1 - start), 1))
                    return Double(t)
                }()
                let headerOverlayBaseOpacity: Double = {
                    if isChromeReady {
                        return (isClosing || isInteracting) ? 0 : 1
                    }
                    return headerOpacityRaw
                }()
                let overlayOpacities = resolvedOverlayOpacities(
                    detailOpacity: detailOpacity,
                    baseOpacity: headerOverlayBaseOpacity,
                    isChromeReady: isChromeReady,
                    isClosing: isClosing,
                    isInteracting: isInteracting
                )
                let heroOverlayOpacity = overlayOpacities.hero
                let scrollOverlayOpacity = overlayOpacities.scroll
                let cardWidth: CGFloat = isClosing ? containerSize.width : geometry.size.width
                let targetImageHeight = geometry.imageHeight
                let imageHeightForView: CGFloat = {
                    guard isClosing else { return targetImageHeight }
                    let startingScale = DiscoveryDetailUniformCloseTransform.resolvedScale(
                        transformProgress: 0,
                        startFrame: destinationFrame,
                        containerFrame: containerFrame,
                        initialScale: closeStartScale
                    )
                    let startVisualHeight = baselineOpenImageHeight * startingScale
                    let finalVisualHeight = destinationFrame.height
                    let visualHeight = startVisualHeight
                        + (finalVisualHeight - startVisualHeight) * closeTransformProgress
                    let safeScale = max(uniformCloseScale, 0.0001)
                    return visualHeight / safeScale
                }()
                let expandedCardHeight = geometry.size.height
                let collapsedCardHeight = imageHeightForView
                let cardHeight = collapsedCardHeight
                    + (expandedCardHeight - collapsedCardHeight) * (1 - collapseProgress)
                let effectivePullDown = (isClosing || !isChromeReady) ? 0 : max(scrollOffset, 0)
                let preferPlaceholder = (!isChromeReady) || isInteracting

                let headerOffset = (isClosing || isInteracting || isCollapseActive) ? 0 : min(scrollOffset, 0)
                let heroTopInset = safeAreaInsets.top * (1 - collapseProgress)
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
                    heroOverlayOpacity: heroOverlayOpacity,
                    scrollOverlayOpacity: scrollOverlayOpacity,
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
                    overlayNamespace: overlayNamespace,
                    scrollOffset: $scrollOffset,
                    onClose: onClose,
                    onShowOptions: onShowOptions
                )
                .animation(.easeOut(duration: 0.12), value: isCollapseActive)

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

    private func resolvedCloseBaselineHeight(current: CGFloat, isClosing: Bool) -> CGFloat {
        if isClosing {
            if let baseline = closeBaselineImageHeight {
                return baseline
            } else {
                scheduleBaselineUpdate(to: current)
                return current
            }
        } else {
            scheduleBaselineUpdate(to: current)
            return current
        }
    }

    private func scheduleBaselineUpdate(to value: CGFloat) {
        let threshold: CGFloat = 0.5
        if let existing = closeBaselineImageHeight, abs(existing - value) < threshold {
            return
        }
        DispatchQueue.main.async {
            self.closeBaselineImageHeight = value
        }
    }

    private func resolvedOverlayOpacities(
        detailOpacity: Double,
        baseOpacity: Double,
        isChromeReady: Bool,
        isClosing: Bool,
        isInteracting: Bool
    ) -> (hero: Double, scroll: Double) {
        if isClosing || isInteracting {
            return (hero: baseOpacity, scroll: 0)
        }
        guard isChromeReady else {
            return (hero: baseOpacity, scroll: 0)
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
