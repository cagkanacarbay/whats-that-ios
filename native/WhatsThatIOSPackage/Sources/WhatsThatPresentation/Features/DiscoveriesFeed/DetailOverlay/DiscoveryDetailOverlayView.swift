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
    let deletingDiscoveryId: Int64?
    let isDeletingDiscovery: Bool
    let onDelete: ((DiscoverySummary) -> Void)?
    let onShowOptions: (() -> Void)?
    let onOpenAudioGuide: ((DiscoverySummary) -> Void)?
    let onScrollContentOffsetChanged: (CGFloat) -> Void
    @State private var scrollOffset: CGFloat = 0
    @State private var isImageSheetPresented = false
    @State private var fullscreenContext: DiscoveryDetailContext?

    init(
        snapshot: DiscoveryDetailOverlaySnapshot,
        destinationFrame: CGRect,
        backgroundColor: Color,
        colorScheme: ColorScheme,
        voiceoverController: VoiceoverPlaybackController,
        onClose: @escaping () -> Void,
        deletingDiscoveryId: Int64?,
        isDeletingDiscovery: Bool,
        onDelete: ((DiscoverySummary) -> Void)?,
        onShowOptions: (() -> Void)?,
        onOpenAudioGuide: ((DiscoverySummary) -> Void)? = nil,
        onScrollContentOffsetChanged: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.destinationFrame = destinationFrame
        self.backgroundColor = backgroundColor
        self.colorScheme = colorScheme
        self.onClose = onClose
        self.deletingDiscoveryId = deletingDiscoveryId
        self.isDeletingDiscovery = isDeletingDiscovery
        self.onDelete = onDelete
        self.onShowOptions = onShowOptions
        self.onOpenAudioGuide = onOpenAudioGuide
        self.onScrollContentOffsetChanged = onScrollContentOffsetChanged
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
        .onChange(of: scrollOffset) { _, newValue in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                // Fallback propagation from the binding itself, in case the inner
                // content's callback path does not fire. Convert the content's
                // negative-downwards offset to positive distance-from-top.
                let distanceFromTop = max(-newValue, 0)
                // Safe to call synchronously; coordinator defers any published changes.
                onScrollContentOffsetChanged(distanceFromTop)
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
                // Remove background dimming during interactive dismiss to keep
                // the feed fully visible while dragging the card.
                let backdropOpacity: Double = {
                    if snapshot.isInteracting { return 0 }
                    if snapshot.isClosing { return 0 }
                    return overlayOpacity(for: snapshot.progress)
                }()
                backgroundColor
                    .opacity(backdropOpacity)
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
                // Pure collapse: do not fade content with collapse progress
                let detailOpacity = detailOpacityBase
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
                    isInteracting: snapshot.isInteracting,
                    progress: snapshot.progress
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
                let effectivePullDown: CGFloat = (snapshot.isClosing || !isChromeReady)
                    ? 0
                    : max(scrollOffset, 0) * (1 - collapseProgress)
                // Keep parallax header offset continuous even during close;
                // it will naturally ease to 0 with collapseProgress.
                let headerOffset: CGFloat = min(scrollOffset, 0) * (1 - collapseProgress)
                let heroTopInset = safeAreaInsets.top * (1 - collapseProgress)
                let heroHeaderHeight = imageHeightForView + heroTopInset
                // Compute hero geometry in global coordinates for ScrollView overlay pinning
                // Include headerOffset so parallax shifts are reflected.
                let heroBottomGlobalY = containerFrameRaw.origin.y + geometry.offset.y + headerOffset + heroHeaderHeight
                let fadeMultiplier = snapshot.isClosing ? max(0, 1 - collapseProgress) : 1
                let heroOverlayOpacity: Double = overlayOpacities.hero * fadeMultiplier
                let scrollOverlayOpacity: Double = overlayOpacities.scroll * fadeMultiplier

                // Show top controls with the header overlay once chrome is ready.
                let shouldShowTopControls = (!snapshot.isClosing) && isChromeReady

                let detailLayout = DiscoveryDetailView.LayoutConfiguration(
                    cardSize: CGSize(width: cardWidth, height: cardHeight),
                    heroHeight: heroHeaderHeight,
                    heroImageHeight: imageHeightForView,
                    heroVisibleHeight: heroHeaderHeight,
                    heroBottomGlobalY: heroBottomGlobalY,
                    headerOffset: headerOffset,
                    pullDownOffset: effectivePullDown,
                    cornerRadius: maskCornerRadius,
                    containerWidth: containerWidth,
                    safeAreaTopInset: heroTopInset,
                    contentOpacity: detailOpacity,
                    // Keep the body background fully opaque while visible; rely on the
                    // container's `opacity(contentOpacity)` to fade both content and its
                    // background together, avoiding double-fade artifacts.
                    backgroundOpacity: 1,
                    heroOverlayOpacity: heroOverlayOpacity,
                    scrollOverlayOpacity: scrollOverlayOpacity,
                    isChromeReady: isChromeReady,
                    isMarkdownReady: isChromeReady,
                    isScrollDisabled: snapshot.isClosing || snapshot.isInteracting || !isChromeReady,
                    isClosing: snapshot.isClosing,
                    showTopControls: shouldShowTopControls
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
                    onScrollViewContentOffsetChange: onScrollContentOffsetChanged,
                    onClose: onClose,
                    isDeleting: isDeletingDiscovery && deletingDiscoveryId == context.discovery.id,
                    onDelete: {
                        onDelete?(context.discovery)
                    },
                    onShowOptions: onShowOptions,
                    onShowImage: { presentFullscreen(for: context) },
                    onOpenAudioGuide: {
                        onOpenAudioGuide?(context.discovery)
                    }
                )
                .id(context.sessionId)

                heroCard
                    .overlay(alignment: .top) {
                        // Text/Audio mode pill - part of heroCard so it moves with gestures
                        // Get safe area from UIWindow since view context ignores safe area
                        let globalSafeAreaTop: CGFloat = UIApplication.shared
                            .connectedScenes
                            .compactMap { $0 as? UIWindowScene }
                            .flatMap { $0.windows }
                            .first(where: { $0.isKeyWindow })?
                            .safeAreaInsets.top ?? 59  // 59 is typical iPhone with notch
                        
                        if isChromeReady && !snapshot.isClosing {
                            DiscoveryDetailModePill(
                                discovery: context.discovery,
                                controller: voiceoverController,
                                onAudioSelected: {
                                    onOpenAudioGuide?(context.discovery)
                                }
                            )
                            .padding(.top, globalSafeAreaTop + 6)
                            .animation(.easeInOut(duration: 0.2), value: voiceoverController.playbackState)
                        }
                    }
                    .allowsHitTesting(!isImageSheetPresented)
                    .zIndex(5)
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
        // Global mini player remains visible in MainTabView - text will scroll behind it
        .onChange(of: snapshot.isClosing) { _, closing in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                if closing {
                    dismissFullscreen()
                }
                guard closing, scrollOffset != 0 else { return }
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.9, blendDuration: 0.2)) {
                    scrollOffset = 0
                }
            }
        }
        .onChange(of: snapshot.context?.id) { _, _ in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                dismissFullscreen()
            }
        }
        .sheet(isPresented: $isImageSheetPresented, onDismiss: {
            if !isImageSheetPresented {
                fullscreenContext = nil
            }
        }) {
            Group {
                if let fullscreenContext {
                    DiscoveryDetailImageFullscreenView(
                        discoveryId: fullscreenContext.discovery.id,
                        imageURL: fullscreenContext.imageURL,
                        placeholderImage: fullscreenContext.placeholderImage,
                        onClose: dismissFullscreen
                    )
                } else {
                    Color.clear
                }
            }
            .presentationDetents([.fraction(0.995)])
            .presentationDragIndicator(.visible)
        }
    }

    private func presentFullscreen(for context: DiscoveryDetailContext) {
        fullscreenContext = context
        guard !isImageSheetPresented else { 
            return 
        }
        isImageSheetPresented = true
    }

    private func dismissFullscreen() {
        if isImageSheetPresented {
            isImageSheetPresented = false
        } else {
            fullscreenContext = nil
        }
    }

    private func resolvedOverlayOpacities(
        detailOpacity: Double,
        baseOpacity: Double,
        isChromeReady: Bool,
        isClosing: Bool,
        isInteracting: Bool,
        progress: CGFloat
    ) -> (hero: Double, scroll: Double) {
        // L. Keep overlay during close: fade out with collapse progress
        if isClosing {
            let collapse = Double(Self.transformProgressStatic(progress))
            let fading = max(0, 1 - collapse)
            return (hero: 0, scroll: baseOpacity * fading)
        }
        // J. Show overlay from frame 0; don't gate by chrome-ready
        // Interactions: prefer baseOpacity (header ramp), not detailOpacity
        if isInteracting {
            return (hero: 0, scroll: baseOpacity)
        }
        // During open, rely solely on scroll overlay opacity
        return (hero: 0, scroll: baseOpacity)
    }

    // Helper to reuse uniform close progress mapping without creating dependency cycles
    private static func transformProgressStatic(_ progress: CGFloat) -> CGFloat { max(0, min(1, 1 - progress)) }

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
