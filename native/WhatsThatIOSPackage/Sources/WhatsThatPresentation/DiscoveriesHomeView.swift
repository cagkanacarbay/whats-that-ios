#if canImport(UIKit)
import SwiftUI
import OSLog
import WhatsThatDomain
import WhatsThatShared
import UIKit
#if canImport(MarkdownUI)
import MarkdownUI
#endif

struct DiscoveriesHomeView: View {
    private let feedUseCase: DiscoveryFeedUseCase
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    @Binding private var pendingDiscoveryId: Int64?
    @Binding private var pendingCreatedSummary: DiscoverySummary?
    private let onSignOut: () -> Void
    private let onSettings: (() -> Void)?

    @StateObject private var viewModel: DiscoveryFeedViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollOffset: CGFloat = 0
    @State private var heroContext: DiscoveryHeroContext?
    @State private var heroProgress: CGFloat = 0
    @State private var heroContentOpacity: Double = 0
    @State private var heroIsSettled = false
    @State private var heroIsClosing = false
    @State private var heroIsInteracting = false
    @State private var heroDragTranslation: CGSize = .zero
    @State private var heroDragScale: CGFloat = 1
    @State private var heroDragRotation: Double = 0
    @State private var heroDragShadowOpacity: Double = 0
    @State private var heroDragCornerRadius: CGFloat = 0
    @State private var heroCloseStartTranslation: CGSize = .zero
    @State private var heroCloseStartScale: CGFloat = 1
    @State private var heroCloseStartRotation: Double = 0
    @State private var hiddenDiscovery: HiddenDiscovery?
    @State private var cardFrames: [Int64: CGRect] = [:]
    @State private var isCardFramesReactionScheduled: Bool = false
    @State private var safeAreaBottomInset: CGFloat = 0
    @State private var headerHeight: CGFloat = 110
    @State private var safeAreaTopInset: CGFloat = 0

    private var headerMetrics: DiscoveriesHeaderMetrics {
        DiscoveriesHeaderMetrics(
            headerHeight: headerHeight,
            safeAreaTopInset: safeAreaTopInset
        )
    }
    private let gridSpacing: CGFloat = 1
    private let gridHorizontalPadding: CGFloat = 1
    private let gridBottomPadding: CGFloat = 16
    private let heroEdgeActivationWidth: CGFloat = 30
    private let heroDismissalThreshold: CGFloat = 150
    private let heroOpenAnimationDuration: TimeInterval = 0.5
    private let heroCloseAnimationDuration: TimeInterval = 0.65

    private var heroDismissalDistance: CGFloat {
#if canImport(UIKit)
        if let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        {
            return max(window.bounds.width, 1)
        }
        #endif
        return max(UIScreen.main.bounds.width, 1)
    }

    init(
        feedUseCase: DiscoveryFeedUseCase,
        voiceoverController: VoiceoverPlaybackController,
        pendingDiscoveryId: Binding<Int64?>,
        pendingCreatedSummary: Binding<DiscoverySummary?>,
        onSignOut: @escaping () -> Void,
        onSettings: (() -> Void)? = nil
    ) {
        self.feedUseCase = feedUseCase
        self._voiceoverController = ObservedObject(initialValue: voiceoverController)
        self._pendingDiscoveryId = pendingDiscoveryId
        self._pendingCreatedSummary = pendingCreatedSummary
        self.onSignOut = onSignOut
        self.onSettings = onSettings
        _viewModel = StateObject(wrappedValue: DiscoveryFeedViewModel(feedUseCase: feedUseCase))
    }

    var body: some View {
        GeometryReader { proxy in
            let safeBottom = proxy.safeAreaInsets.bottom
            let safeTop = proxy.safeAreaInsets.top

            let _ = proxy.size // retain to keep dependency updates
            let gridAvailableWidth = proxy.size.width == 0 ? UIScreen.main.bounds.width : proxy.size.width
            let contentWidth = max(gridAvailableWidth - (gridHorizontalPadding * 2), 0)
            let metrics = headerMetrics

            ZStack(alignment: .top) {
                backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: metrics.headerSpacerHeight)

                        DiscoveriesGridView(
                            viewModel: viewModel,
                            availableWidth: contentWidth,
                            cardSpacing: gridSpacing,
                            cardFrames: $cardFrames,
                            hiddenDiscovery: hiddenDiscovery,
                            onLoadMore: { discovery in
                                await viewModel.loadMoreIfNeeded(currentItem: discovery)
                            },
                            onSelect: { discovery, imageURL, frame in
                                handleDiscoverySelection(
                                    discovery: discovery,
                                    imageURL: imageURL,
                                    startFrame: frame
                                )
                            }
                        )
                        .padding(.horizontal, gridHorizontalPadding)
                        .padding(.top, metrics.gridTopPadding)
                        .padding(.bottom, gridBottomPadding)
                    }
                }
                .coordinateSpace(name: "discoveriesScroll")
                .refreshable {
                    await viewModel.refresh()
                }
                .task {
                    await viewModel.loadInitialIfNeeded()
                    presentPendingDiscoveryIfNeeded()
                }
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { rawValue in
                    guard let rawValue else { return }
                    let adjusted = rawValue - metrics.headerSpacerHeight
                    scrollOffset = adjusted
                }
                .onChange(of: viewModel.discoveries) {
                    presentPendingDiscoveryIfNeeded()
                }
                .onChange(of: pendingDiscoveryId) {
                    presentPendingDiscoveryIfNeeded()
                }
                .onChange(of: pendingCreatedSummary) { oldValue, newValue in
                    guard let summary = newValue else { return }
                    viewModel.upsert(summary)
                    pendingCreatedSummary = nil
                }
                .onChange(of: cardFrames) {
                    // Defer reacting to card frame changes to the next runloop tick.
                    // Rationale: updating hero presentation state inside the same frame
                    // can cause a layout → preference write → layout loop, which triggers
                    // "Bound preference … tried to update multiple times per frame".
                    // Coalesce multiple rapid updates and run once off-frame.
                    guard pendingDiscoveryId != nil else { return }
                    if !isCardFramesReactionScheduled {
                        isCardFramesReactionScheduled = true
                        DispatchQueue.main.async {
                            // Reset the coalescing flag and perform the action.
                            isCardFramesReactionScheduled = false
                            presentPendingDiscoveryIfNeeded()
                        }
                    }
                }

                DiscoveriesHeaderView(
                    opacity: headerOpacity,
                    metrics: metrics,
                    backgroundColor: backgroundColor,
                    onSignOut: onSignOut,
                    onSettings: onSettings
                )
                    .onPreferenceChange(HeaderHeightPreferenceKey.self) { value in
                        guard value > 0 else { return }
                        if abs(value - headerHeight) > 0.5 {
                            headerHeight = value
                        }
                    }

                if let context = heroContext {
                    let targetCloseFrame = cardFrames[context.discovery.id] ?? context.startFrame
                    DiscoveryHeroOverlay(
                        context: context,
                        destinationFrame: targetCloseFrame,
                        progress: heroProgress,
                        contentOpacity: heroContentOpacity,
                        isContentReady: heroIsSettled,
                        isClosing: heroIsClosing,
                        isInteracting: heroIsInteracting,
                        gestureTranslation: heroDragTranslation,
                        gestureScale: heroDragScale,
                        gestureRotation: heroDragRotation,
                        gestureShadowOpacity: heroDragShadowOpacity,
                        gestureCornerRadius: heroDragCornerRadius,
                        closeStartTranslation: heroCloseStartTranslation,
                        closeStartScale: heroCloseStartScale,
                        closeStartRotation: heroCloseStartRotation,
                        backgroundColor: backgroundColor,
                        colorScheme: colorScheme,
                        voiceoverController: voiceoverController,
                        onClose: { handleDetailDismissal(fromGesture: false) },
                        onShowOptions: nil
                    )
                    .ignoresSafeArea(edges: .top)
                    .transition(.identity)
                    .simultaneousGesture(heroEdgeDragGesture, including: .gesture)
                    .zIndex(5)
                }
            }
            .onAppear {
                updateSafeAreaBottomInsetIfNeeded(safeBottom)
                updateSafeAreaTopInsetIfNeeded(safeTop)
            }
            .onChange(of: safeBottom) { _, newValue in
                updateSafeAreaBottomInsetIfNeeded(newValue)
            }
            .onChange(of: safeTop) { _, newValue in
                updateSafeAreaTopInsetIfNeeded(newValue)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: BrandSpacing.medium) {
                voiceoverPlayerOverlay

                if let errorMessage = viewModel.errorMessage,
                   !errorMessage.isEmpty,
                   !viewModel.discoveries.isEmpty
                {
                    FeedErrorToast(
                        message: errorMessage,
                        retryAction: {
                            Task { await viewModel.refresh() }
                        }
                    )
                }

                if viewModel.isPaginating {
                    HStack(spacing: BrandSpacing.small) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Loading more")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        backgroundColor.opacity(0.9)
                            .blur(radius: 20)
                    )
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.medium + max(safeAreaBottomInset - 8, 0))
        }
        .animation(.easeInOut, value: viewModel.loadState)
    }

    private func handleDiscoverySelection(discovery: DiscoverySummary, imageURL: URL?, startFrame: CGRect) {
        guard heroContext?.discovery.id != discovery.id || heroIsClosing else {
            return
        }

        let resolvedImageURL = imageURL ?? self.imageURL(for: discovery)
        let resolvedFrame: CGRect

        if startFrame.width <= 0 || startFrame.height <= 0 {
            let fallbackWidth: CGFloat = 200
            let fallbackHeight: CGFloat = fallbackWidth * 1.2
            let bounds = UIScreen.main.bounds
            resolvedFrame = CGRect(
                x: bounds.midX - (fallbackWidth / 2),
                y: bounds.midY - (fallbackHeight / 2),
                width: fallbackWidth,
                height: fallbackHeight
            )
        } else {
            resolvedFrame = startFrame
        }

        let sessionId = UUID()
        let cachedImage = DiscoveryHeroImageCache.shared.image(for: discovery.id)

        hiddenDiscovery = HiddenDiscovery(id: discovery.id, sessionId: sessionId)
        heroContext = DiscoveryHeroContext(
            sessionId: sessionId,
            discovery: discovery,
            imageURL: resolvedImageURL,
            startFrame: resolvedFrame,
            placeholderImage: cachedImage,
            cardAspectRatio: resolvedFrame.height / max(resolvedFrame.width, 1)
        )
        heroProgress = 0
        heroContentOpacity = 0
        heroIsSettled = false
        heroIsClosing = false
        heroIsInteracting = false
        resetHeroInteraction(animated: false)
        updateHeroPresentationVisibility()
        voiceoverController.ensureMetadata(for: discovery)
        voiceoverController.isDetailOverlayActive = true

        withAnimation(.timingCurve(0.33, 1.0, 0.68, 1.0, duration: heroOpenAnimationDuration)) {
            heroProgress = 1
        }
        scheduleHeroSettled(for: sessionId)
    }

    private func presentPendingDiscoveryIfNeeded() {
        guard let pendingId = pendingDiscoveryId,
              heroContext == nil
        else {
            return
        }

        guard let discovery = viewModel.discoveries.first(where: { $0.id == pendingId }) else {
            return
        }

        guard let startFrame = resolveStartFrame(for: discovery.id) else {
            return
        }

        pendingDiscoveryId = nil
        handleDiscoverySelection(
            discovery: discovery,
            imageURL: imageURL(for: discovery),
            startFrame: startFrame
        )
    }

    private func resolveStartFrame(for discoveryId: Int64) -> CGRect? {
        if let frame = cardFrames[discoveryId], frame.width > 0, frame.height > 0 {
            return frame
        }

        guard let firstId = viewModel.discoveries.first?.id,
              let frame = cardFrames[firstId],
              frame.width > 0,
              frame.height > 0
        else {
            return nil
        }

        return frame
    }

    private func resetHeroInteraction(animated: Bool) {
        let animations = {
            heroDragTranslation = .zero
            heroDragScale = 1
            heroDragRotation = 0
            heroDragShadowOpacity = 0
            heroDragCornerRadius = 0
        }

        if animated {
            withAnimation(.interpolatingSpring(mass: 1, stiffness: 100, damping: 15)) {
                animations()
            }
        } else {
            animations()
        }

        heroIsInteracting = false
    }

    private func updateHeroPresentationVisibility() {
        let shouldShow = !heroIsClosing && heroIsSettled
        let targetOpacity: Double = shouldShow ? 1 : 0
        guard heroContentOpacity != targetOpacity else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            heroContentOpacity = targetOpacity
        }
    }

    private func scheduleHeroSettled(for sessionId: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + heroOpenAnimationDuration) {
            guard heroContext?.sessionId == sessionId,
                  !heroIsClosing,
                  !heroIsInteracting
            else { return }

            if !heroIsSettled {
                heroIsSettled = true
                updateHeroPresentationVisibility()
            }
        }
    }

    private func handleHeroDragChanged(_ value: DragGesture.Value) {
        guard heroContext != nil, !heroIsClosing else { return }

        let horizontalTranslation = value.translation.width
        let verticalTranslation = value.translation.height

        if !heroIsInteracting {
            guard value.startLocation.x <= heroEdgeActivationWidth else { return }
            guard horizontalTranslation > 0 else { return }
            guard abs(horizontalTranslation) >= abs(verticalTranslation) else { return }
            heroIsInteracting = true
            if heroIsSettled {
                heroIsSettled = false
                updateHeroPresentationVisibility()
            }
        }

        guard heroIsInteracting else { return }

        let translationX = max(horizontalTranslation, 0)
        let translationY = verticalTranslation * 0.5
        let normalizedProgress = min(max(translationX / heroDismissalDistance, 0), 1)

        let clampedScaleProgress = min(normalizedProgress, 0.5) / 0.5
        let scaleReduction = 0.35 * clampedScaleProgress
        let scale = max(0.65, 1 - scaleReduction)

        let clampedRotationProgress = min(normalizedProgress, 0.5) / 0.5
        let rotation = -5 * Double(clampedRotationProgress)

        let borderRadius: CGFloat
        if normalizedProgress <= 0.1 {
            borderRadius = (normalizedProgress / 0.1) * 12
        } else {
            borderRadius = 12
        }

        let clampedShadowProgress = min(normalizedProgress, 0.3) / 0.3
        let shadowOpacity = Double(clampedShadowProgress * 0.3)

        heroDragTranslation = CGSize(width: translationX, height: translationY)
        heroDragScale = scale
        heroDragRotation = rotation
        heroDragCornerRadius = borderRadius
        heroDragShadowOpacity = shadowOpacity
    }

    private func handleHeroDragEnded(_ value: DragGesture.Value) {
        guard heroIsInteracting else { return }
        heroIsInteracting = false

        let translation = max(value.translation.width, 0)
        let predictedTranslation = max(value.predictedEndTranslation.width, translation)

        let shouldDismiss = predictedTranslation > heroDismissalThreshold || translation > heroDismissalThreshold

        if shouldDismiss {
            // Capture the current interactive transform as the starting
            // point for the uniform close animation.
            heroCloseStartTranslation = heroDragTranslation
            heroCloseStartScale = heroDragScale
            heroCloseStartRotation = heroDragRotation
            resetHeroInteraction(animated: true)
            handleDetailDismissal(fromGesture: true)
        } else {
            resetHeroInteraction(animated: true)
            if let sessionId = heroContext?.sessionId {
                scheduleHeroSettled(for: sessionId)
            }
        }
    }

    private func handleDetailDismissal(fromGesture: Bool = false) {
        guard let context = heroContext else { return }

        heroIsInteracting = false
        if !fromGesture {
            // Back button dismissal should close from the expanded state.
            heroCloseStartTranslation = .zero
            heroCloseStartScale = 1
            heroCloseStartRotation = 0
        }
        resetHeroInteraction(animated: true)
        heroIsClosing = true
        heroIsSettled = false
        updateHeroPresentationVisibility()

        withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: heroCloseAnimationDuration)) {
            heroProgress = 0
        }

        let closingSessionId = context.sessionId
        DispatchQueue.main.asyncAfter(deadline: .now() + heroCloseAnimationDuration + 0.1) {
            if heroContext?.sessionId == closingSessionId {
                heroContext = nil
                heroIsClosing = false
                heroProgress = 0
                heroContentOpacity = 0
                heroIsSettled = false
            } else if heroContext == nil {
                heroIsClosing = false
                heroProgress = 0
                heroContentOpacity = 0
                heroIsSettled = false
            }

            heroIsInteracting = false
            if hiddenDiscovery?.sessionId == closingSessionId {
                hiddenDiscovery = nil
            }
            voiceoverController.isDetailOverlayActive = false
        }
    }

    private func updateSafeAreaBottomInsetIfNeeded(_ value: CGFloat) {
        if abs(value - safeAreaBottomInset) > 0.5 {
            safeAreaBottomInset = value
        }
    }

    private func updateSafeAreaTopInsetIfNeeded(_ value: CGFloat) {
        if abs(value - safeAreaTopInset) > 0.5 {
            safeAreaTopInset = value
        }
    }

    private func imageURL(for discovery: DiscoverySummary) -> URL? {
        guard let path = discovery.imagePath else { return nil }
        return URL(string: path)
    }

    @ViewBuilder
    private var voiceoverPlayerOverlay: some View {
        if shouldShowVoiceoverPlayer,
           let discovery = voiceoverController.currentDiscovery {
            VoiceoverPlayerBar(
                controller: voiceoverController,
                discovery: discovery,
                imageURL: imageURL(for: discovery)
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var shouldShowVoiceoverPlayer: Bool {
        switch voiceoverController.playbackState {
        case .idle, .unavailable:
            return false
        default:
            return voiceoverController.currentDiscovery != nil
        }
    }

    private var heroEdgeDragGesture: AnyGesture<DragGesture.Value> {
        AnyGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged(handleHeroDragChanged)
                .onEnded(handleHeroDragEnded)
        )
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }

    private var headerOpacity: Double {
        headerMetrics.headerOpacity(for: scrollOffset)
    }
}

private struct FeedErrorToast: View {
    let message: String
    let retryAction: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(colorScheme == .dark ? 0.65 : 0.55),
                            Color.black.opacity(colorScheme == .dark ? 0.45 : 0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }

            HStack(spacing: BrandSpacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.orange)

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(toastTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Retry") {
                    retryAction()
                }
                .font(.system(size: 14, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color.orange.opacity(0.85))
                .clipShape(Capsule())
            }
            .padding(.horizontal, BrandSpacing.medium)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var toastTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.85) : Color.white.opacity(0.92)
    }

}

private struct DiscoveryHeroContext: Identifiable {
    let sessionId: UUID
    let discovery: DiscoverySummary
    let imageURL: URL?
    let startFrame: CGRect
    let placeholderImage: UIImage?
    let cardAspectRatio: CGFloat

    var id: UUID { sessionId }
}

final class DiscoveryHeroImageCache {
    static let shared = DiscoveryHeroImageCache()

    private let cache = NSCache<NSNumber, UIImage>()
    private let lock = NSLock()

    private init() {}

    func store(_ image: UIImage, for discoveryId: Int64) {
        lock.lock()
        cache.setObject(image, forKey: NSNumber(value: discoveryId))
        lock.unlock()
    }

    func image(for discoveryId: Int64) -> UIImage? {
        lock.lock()
        let image = cache.object(forKey: NSNumber(value: discoveryId))
        lock.unlock()
        return image
    }
}

private enum DiscoveryHeroLayout {
    static let expandedImageHeightFraction: CGFloat = 0.8
}

private struct DiscoveryHeroOverlay: View {
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    let context: DiscoveryHeroContext
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
        context: DiscoveryHeroContext,
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
            // Treat the visual container as if it starts at the very top of the screen
            // so the hero image can extend behind the status bar. Adjust both the
            // geometry container frame and height by the top safe-area inset.
            let containerFrame = containerFrameRaw.offsetBy(dx: 0, dy: -safeAreaInsets.top)
            let screenBounds = UIScreen.main.bounds
            let rawWidth = proxy.size.width == 0 ? screenBounds.width : proxy.size.width
            let containerWidth = min(rawWidth, screenBounds.width)
            let rawHeight = proxy.size.height == 0 ? screenBounds.height : proxy.size.height
            let containerSize = CGSize(width: containerWidth, height: rawHeight + safeAreaInsets.top)
            let geometry = HeroGeometry(
                startFrame: context.startFrame,
                containerSize: containerSize,
                containerOrigin: CGPoint(x: 0, y: containerFrame.origin.y),
                targetAspectRatio: context.cardAspectRatio,
                progress: progress,
                targetExpandedHeightFraction: DiscoveryHeroLayout.expandedImageHeightFraction,
                enforceAspectForImage: isClosing
            )
            // safeAreaInsets already captured above

            ZStack(alignment: .topLeading) {
                Color.black
                    .opacity(overlayOpacity(for: progress))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                let combinedCornerRadius = max(0, geometry.cornerRadius + gestureCornerRadius)
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
                let isChromeReady = isContentReady && !isClosing
                let detailOpacity = isChromeReady ? contentOpacity : 0
                // Header (title/date/short description) should fade in as soon as
                // the image reaches its full size, slightly before settle.
                let headerOpacityRaw: Double = {
                    guard !isClosing && !isInteracting else { return 0 }
                    // Smooth fade near end of open; tuned to avoid jumps.
                    let start: CGFloat = 0.88
                    let t = max(0, min((progress - start) / (1 - start), 1))
                    return Double(t)
                }()
                // Single header overlay on image: 0 while closing/dragging, ramps in during open,
                // and stays fully visible once settled.
                let headerOverlayOpacity: Double = isChromeReady ? (isClosing || isInteracting ? 0 : 1) : headerOpacityRaw
                // Width-driven height ensures we match the card aspect during close.
                let widthDrivenCardHeight = min(containerSize.height, containerSize.width * context.cardAspectRatio)
                // During closing we keep the base frame at expanded header size and uniformly
                // transform the whole card to the start frame to preserve crop.
                let cardWidth: CGFloat = isClosing ? containerSize.width : geometry.size.width
                // Always present the full card height during open so the background
                // below the image is visible and expands smoothly.
                let cardHeight: CGFloat = isClosing ? widthDrivenCardHeight : geometry.size.height
                let imageHeightForView: CGFloat = isClosing ? widthDrivenCardHeight : geometry.imageHeight
                let effectivePullDown = (isClosing || !isChromeReady) ? 0 : max(scrollOffset, 0)
                let preferPlaceholder = (!isChromeReady) || isInteracting

                let _ = maybeLogHeroGeometry(
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
                    isChromeReady: isChromeReady
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
                    cornerRadius: geometry.cornerRadius,
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

                    DiscoveryHeroContentView(
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
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: combinedCornerRadius, style: .continuous))

                heroCard
                    .overlay(alignment: .topLeading) {
                        if isChromeReady {
                            DiscoveryHeroTopControls(
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
                    // During closing, uniformly transform the full expanded header to the start frame
                    // using a single scale + offset derived from progress to preserve constant crop.
                    .modifier(UniformCloseTransform(
                        isClosing: isClosing,
                        progress: progress,
                        startFrame: destinationFrame,
                        containerFrame: containerFrame,
                        initialScale: closeStartScale,
                        initialOffset: closeStartTranslation,
                        initialRotation: closeStartRotation,
                        baseWidth: cardWidth,
                        baseHeight: cardHeight
                    ))
                    // Preserve interactive transforms while not closing.
                    .if(!isClosing) { view in
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

    private struct HeroGeometry {
        let size: CGSize
        let offset: CGPoint
        let cornerRadius: CGFloat
        let imageHeight: CGFloat
        let shadowOpacity: Double
        let shadowRadius: CGFloat
        let shadowYOffset: CGFloat

        init(
            startFrame: CGRect,
            containerSize: CGSize,
            containerOrigin: CGPoint,
            targetAspectRatio: CGFloat,
            progress: CGFloat,
            targetExpandedHeightFraction: CGFloat,
            enforceAspectForImage: Bool = false
        ) {
            let clamped = max(0, min(progress, 1))
            let startX = startFrame.minX - containerOrigin.x
            let startY = startFrame.minY - containerOrigin.y
            let width = HeroGeometry.lerp(startFrame.width, containerSize.width, clamped)
            let height = HeroGeometry.lerp(startFrame.height, containerSize.height, clamped)
            let x = HeroGeometry.lerp(startX, 0, clamped)
            let y = HeroGeometry.lerp(startY, 0, clamped)
            let aspectRatio = targetAspectRatio.isFinite && targetAspectRatio > 0.1
                ? targetAspectRatio
                : startFrame.height / max(startFrame.width, 1)
            // For closing, compute imageHeight from the current width to
            // maintain constant cropping relative to the card aspect ratio.
            // Clamp to container height to avoid overshooting off screen.
            let imageHeight: CGFloat
            if enforceAspectForImage {
                let ratioHeight = width * aspectRatio
                let desiredHeight = min(containerSize.height, ratioHeight)
                let resolvedHeight = max(startFrame.height, desiredHeight)
                // Interpolate between the starting card height and the
                // width-driven target to keep smoothness.
                imageHeight = HeroGeometry.lerp(startFrame.height, resolvedHeight, clamped)
            } else {
                let widthDrivenHeight = min(containerSize.height, containerSize.width * aspectRatio)
                let clampedFraction = max(0, min(targetExpandedHeightFraction, 1))
                let fractionHeight = containerSize.height * clampedFraction
                let desiredHeight = min(containerSize.height, max(widthDrivenHeight, fractionHeight))
                let resolvedHeight = max(startFrame.height, desiredHeight)
                imageHeight = HeroGeometry.lerp(startFrame.height, resolvedHeight, clamped)
            }

            self.size = CGSize(width: width, height: height)
            self.offset = CGPoint(x: x, y: y)
            self.cornerRadius = HeroGeometry.cornerRadius(for: clamped)
            self.imageHeight = imageHeight
            self.shadowOpacity = Double(clamped) * 0.3
            self.shadowRadius = shadowOpacity > 0 ? 20 : 0
            self.shadowYOffset = shadowOpacity > 0 ? 12 : 0
        }

        private static func lerp(_ from: CGFloat, _ to: CGFloat, _ fraction: CGFloat) -> CGFloat {
            from + (to - from) * fraction
        }

        private static func cornerRadius(for progress: CGFloat) -> CGFloat {
            if progress <= 0.7 {
                let local = progress / 0.7
                return lerp(12, 6, local)
            } else {
                let local = (progress - 0.7) / 0.3
                return lerp(6, 0, max(0, min(local, 1)))
            }
        }
    }
}

// MARK: - Logging

private let heroLogger = Logger(subsystem: "WhatsThatIOS", category: "HeroTransition")

private extension DiscoveryHeroOverlay {
    func maybeLogHeroGeometry(
        phase: String,
        progress: CGFloat,
        containerSize: CGSize,
        startFrame: CGRect,
        width: CGFloat,
        height: CGFloat,
        imageHeight: CGFloat,
        cardAspect: CGFloat,
        preferPlaceholder: Bool,
        pullDown: CGFloat,
        isChromeReady: Bool
    ) {
        guard isClosing else { return }

        let currentAspect = height / max(width, 1)
        let widthDrivenHeight = width * cardAspect
        let heightDelta = imageHeight - widthDrivenHeight

        heroLogger.debug(
            "[Hero] phase=\(phase, privacy: .public) progress=\(progress, privacy: .public) width=\(width, privacy: .public) height=\(height, privacy: .public) imageHeight=\(imageHeight, privacy: .public) widthDrivenHeight=\(widthDrivenHeight, privacy: .public) heightDelta=\(heightDelta, privacy: .public) currentAspect=\(currentAspect, privacy: .public) cardAspect=\(cardAspect, privacy: .public) container=\(String(describing: containerSize), privacy: .public) start=\(String(describing: startFrame), privacy: .public) placeholder=\(preferPlaceholder, privacy: .public) pullDown=\(pullDown, privacy: .public) chromeReady=\(isChromeReady, privacy: .public)"
        )
    }

    // Map integration removed; hero header no longer surfaces a location button.
}

// MARK: - Uniform close transform

private struct UniformCloseTransform: ViewModifier {
    let isClosing: Bool
    let progress: CGFloat // 1 -> 0 on close
    let startFrame: CGRect
    let containerFrame: CGRect
    let initialScale: CGFloat
    let initialOffset: CGSize
    let initialRotation: Double
    let baseWidth: CGFloat
    let baseHeight: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if isClosing {
            // Close progress from 0 (no change) to 1 (at start frame)
            let t = max(0, min(1, 1 - progress))
            // Compute the target center relative to the overlay's top-left origin.
            let targetCenterX = startFrame.midX - containerFrame.origin.x
            let targetCenterY = startFrame.midY - containerFrame.origin.y
            let containerWidth = max(containerFrame.width, 1)
            let startScale = max(startFrame.width, 1) / containerWidth
            // Interpolate from the interactive transform to the card frame.
            let clampedInitialScale = initialScale.isFinite ? max(0.5, min(initialScale, 1.2)) : 1
            let scale = clampedInitialScale + (startScale - clampedInitialScale) * t
            // Current center (before offset) is at half of the base size.
            let currentCenterX = baseWidth / 2
            let currentCenterY = baseHeight / 2
            let targetOffsetX = targetCenterX - currentCenterX
            let targetOffsetY = targetCenterY - currentCenterY
            let offsetX = initialOffset.width + (targetOffsetX - initialOffset.width) * t
            let offsetY = initialOffset.height + (targetOffsetY - initialOffset.height) * t
            let rotation = initialRotation + (0 - initialRotation) * t

            content
                .scaleEffect(scale, anchor: .center)
                .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
                .offset(x: offsetX, y: offsetY)
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

private struct DiscoveryHeroContentView: View {
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

private struct VoiceoverPlayerBar: View {
    @ObservedObject private var controller: VoiceoverPlaybackController
    let discovery: DiscoverySummary
    let imageURL: URL?

    @State private var pendingSliderValue: Double?
    @State private var isScrubbing = false

    init(
        controller: VoiceoverPlaybackController,
        discovery: DiscoverySummary,
        imageURL: URL?
    ) {
        _controller = ObservedObject(initialValue: controller)
        self.discovery = discovery
        self.imageURL = imageURL
    }

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            HStack(spacing: BrandSpacing.medium) {
                artwork

                VStack(alignment: .leading, spacing: 4) {
                    Text(discovery.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    if let subtitle = subtitleText {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(action: { controller.stop() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(8)
                        .background(Color.secondary.opacity(0.16))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: BrandSpacing.small) {
                Slider(
                    value: sliderBinding,
                    in: 0...sliderRangeUpperBound,
                    onEditingChanged: handleSliderEditingChanged(_:)
                )
                .tint(BrandColors.Dark.primaryAction)

                HStack {
                    Text(formatTime(currentSliderValue))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Text(formatTime(controller.duration ?? 0))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
            }

            HStack(spacing: BrandSpacing.medium) {
                Button(action: handlePrimaryAction) {
                    Image(systemName: primaryActionIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 56, height: 56)
                        .background(BrandColors.Dark.primaryAction)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                if case let .failed(id, message) = controller.playbackState, id == discovery.id {
                    Text(message ?? "Playback failed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
        .padding(BrandSpacing.medium)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: BrandCornerRadius.large, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        .animation(.easeInOut, value: controller.playbackState)
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.25))

            if let imageURL {
                DiscoveryCachedImage(
                    discoveryId: discovery.id,
                    remoteURL: imageURL
                ) { phase in
                    switch phase {
                    case .success(let platformImage):
                        Image(uiImage: platformImage)
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackIcon
                    case .loading, .empty:
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                fallbackIcon
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var fallbackIcon: some View {
        Image(systemName: "waveform")
            .font(.system(size: 18))
            .foregroundStyle(Color.secondary)
    }

    private var sliderRangeUpperBound: Double {
        let duration = controller.duration ?? 0
        if duration > 0 {
            return duration
        }
        return max(controller.position, 1)
    }

    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: {
                min(max(pendingSliderValue ?? controller.position, 0), sliderRangeUpperBound)
            },
            set: { newValue in
                pendingSliderValue = newValue
            }
        )
    }

    private var currentSliderValue: Double {
        pendingSliderValue ?? controller.position
    }

    private var primaryActionIcon: String {
        switch controller.playbackState {
        case let .playing(id) where id == discovery.id:
            return "pause.fill"
        case let .paused(id) where id == discovery.id:
            return "play.fill"
        default:
            return "play.fill"
        }
    }

    private var subtitleText: String? {
        switch controller.playbackState {
        case let .loading(id) where id == discovery.id:
            return "Preparing narration..."
        case let .paused(id) where id == discovery.id:
            return "Paused"
        case let .playing(id) where id == discovery.id:
            return "Playing"
        case let .failed(id, _) where id == discovery.id:
            return "Playback error"
        default:
            if let model = controller.assetStates[discovery.id]?.modelIdentifier {
                return model
            }
            return nil
        }
    }

    private func handleSliderEditingChanged(_ isEditing: Bool) {
        isScrubbing = isEditing
        if !isEditing {
            if let pendingSliderValue {
                controller.seek(to: pendingSliderValue)
            }
            pendingSliderValue = nil
        }
    }

    private func handlePrimaryAction() {
        switch controller.playbackState {
        case let .playing(id) where id == discovery.id:
            controller.pause()
        case let .paused(id) where id == discovery.id:
            controller.resume()
        default:
            controller.togglePlayback(for: discovery)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

private struct DiscoveryHeroTopControls: View {
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
#if canImport(UIKit)
        if baseInset <= 0 {
            let globalInset = UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?
                .safeAreaInsets.top ?? 0
            return globalInset + 12
        }
#endif
        return baseInset + 12
    }
}

extension View {
    @ViewBuilder
    func conditionalScrollDisabled(_ disabled: Bool) -> some View {
        if #available(iOS 16.0, *) {
            scrollDisabled(disabled)
        } else {
            self
        }
    }
}

private extension String {
    var nonEmptyOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#else
import SwiftUI
import WhatsThatDomain

struct DiscoveriesHomeView: View {
    private let feedUseCase: DiscoveryFeedUseCase
    private let onSignOut: () -> Void
    private let onSettings: (() -> Void)?

    init(
        feedUseCase: DiscoveryFeedUseCase,
        voiceoverController _: VoiceoverPlaybackController,
        pendingDiscoveryId _: Binding<Int64?>,
        pendingCreatedSummary _: Binding<DiscoverySummary?>,
        onSignOut: @escaping () -> Void,
        onSettings: (() -> Void)? = nil
    ) {
        self.feedUseCase = feedUseCase
        self.onSignOut = onSignOut
        self.onSettings = onSettings
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Discoveries are available on iOS only.")
                .font(.headline)
            Button("Sign out", action: onSignOut)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#endif
