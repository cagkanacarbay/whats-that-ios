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
    @State private var detailContext: DiscoveryDetailContext?
    @State private var detailProgress: CGFloat = 0
    @State private var detailContentOpacity: Double = 0
    @State private var detailIsSettled = false
    @State private var detailIsClosing = false
    @State private var detailIsInteracting = false
    @State private var detailDragTranslation: CGSize = .zero
    @State private var detailDragScale: CGFloat = 1
    @State private var detailDragRotation: Double = 0
    @State private var detailDragShadowOpacity: Double = 0
    @State private var detailDragCornerRadius: CGFloat = 0
    @State private var detailCloseStartTranslation: CGSize = .zero
    @State private var detailCloseStartScale: CGFloat = 1
    @State private var detailCloseStartRotation: Double = 0
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
    private let detailEdgeActivationWidth: CGFloat = 30
    private let detailDismissalThreshold: CGFloat = 150
    private let heroAnimator = DiscoveryDetailHeroAnimator()

    private var detailDismissalDistance: CGFloat {
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

    private var dismissInteractor: DiscoveryDetailDismissInteractor {
        DiscoveryDetailDismissInteractor(
            edgeActivationWidth: detailEdgeActivationWidth,
            dismissalDistance: detailDismissalDistance,
            dismissalThreshold: detailDismissalThreshold
        )
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
                    // Rationale: updating detail overlay presentation state inside the same frame
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

                if let context = detailContext {
                    let targetCloseFrame = cardFrames[context.discovery.id] ?? context.startFrame
                    DiscoveryDetailOverlayView(
                        context: context,
                        destinationFrame: targetCloseFrame,
                        progress: detailProgress,
                        contentOpacity: detailContentOpacity,
                        isContentReady: detailIsSettled,
                        isClosing: detailIsClosing,
                        isInteracting: detailIsInteracting,
                        gestureTranslation: detailDragTranslation,
                        gestureScale: detailDragScale,
                        gestureRotation: detailDragRotation,
                        gestureShadowOpacity: detailDragShadowOpacity,
                        gestureCornerRadius: detailDragCornerRadius,
                        closeStartTranslation: detailCloseStartTranslation,
                        closeStartScale: detailCloseStartScale,
                        closeStartRotation: detailCloseStartRotation,
                        backgroundColor: backgroundColor,
                        colorScheme: colorScheme,
                        voiceoverController: voiceoverController,
                        onClose: { handleDetailDismissal(fromGesture: false) },
                        onShowOptions: nil
                    )
                    .ignoresSafeArea(edges: .top)
                    .transition(.identity)
                    .simultaneousGesture(detailEdgeDragGesture, including: .gesture)
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
                    DiscoveriesErrorToastView(
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
        guard detailContext?.discovery.id != discovery.id || detailIsClosing else {
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
        let cachedImage = DiscoveryDetailImageCache.shared.image(for: discovery.id)

        hiddenDiscovery = HiddenDiscovery(id: discovery.id, sessionId: sessionId)
        detailContext = DiscoveryDetailContext(
            sessionId: sessionId,
            discovery: discovery,
            imageURL: resolvedImageURL,
            startFrame: resolvedFrame,
            placeholderImage: cachedImage,
            cardAspectRatio: resolvedFrame.height / max(resolvedFrame.width, 1)
        )
        detailProgress = 0
        detailContentOpacity = 0
        detailIsSettled = false
        detailIsClosing = false
        detailIsInteracting = false
        resetDetailInteraction(animated: false)
        updateDetailPresentationVisibility()
        voiceoverController.ensureMetadata(for: discovery)
        voiceoverController.isDetailOverlayActive = true

        withAnimation(heroAnimator.openAnimation()) {
            detailProgress = 1
        }
        scheduleDetailSettled(for: sessionId)
    }

    private func presentPendingDiscoveryIfNeeded() {
        guard let pendingId = pendingDiscoveryId,
              detailContext == nil
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

    private func resetDetailInteraction(animated: Bool) {
        let animations = {
            detailDragTranslation = .zero
            detailDragScale = 1
            detailDragRotation = 0
            detailDragShadowOpacity = 0
            detailDragCornerRadius = 0
        }

        if animated {
            withAnimation(.interpolatingSpring(mass: 1, stiffness: 100, damping: 15)) {
                animations()
            }
        } else {
            animations()
        }

        detailIsInteracting = false
    }

    private func updateDetailPresentationVisibility() {
        let shouldShow = !detailIsClosing && detailIsSettled
        let targetOpacity: Double = shouldShow ? 1 : 0
        guard detailContentOpacity != targetOpacity else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            detailContentOpacity = targetOpacity
        }
    }

    private func scheduleDetailSettled(for sessionId: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + heroAnimator.openDuration) {
            guard detailContext?.sessionId == sessionId,
                  !detailIsClosing,
                  !detailIsInteracting
            else { return }

            if !detailIsSettled {
                detailIsSettled = true
                updateDetailPresentationVisibility()
            }
        }
    }

    private func handleDetailDragChanged(_ value: DragGesture.Value) {
        guard detailContext != nil, !detailIsClosing else { return }

        if !detailIsInteracting {
            guard dismissInteractor.canBeginInteraction(startLocation: value.startLocation, translation: value.translation) else {
                return
            }
            detailIsInteracting = true
            if detailIsSettled {
                detailIsSettled = false
                updateDetailPresentationVisibility()
            }
        }

        guard detailIsInteracting else { return }

        let metrics = dismissInteractor.metrics(for: value.translation)
        detailDragTranslation = metrics.translation
        detailDragScale = metrics.scale
        detailDragRotation = metrics.rotation
        detailDragCornerRadius = metrics.cornerRadius
        detailDragShadowOpacity = metrics.shadowOpacity
    }

    private func handleDetailDragEnded(_ value: DragGesture.Value) {
        guard detailIsInteracting else { return }
        detailIsInteracting = false

        let shouldDismiss = dismissInteractor.shouldDismiss(
            translation: value.translation,
            predictedTranslation: value.predictedEndTranslation
        )

        if shouldDismiss {
            detailCloseStartTranslation = detailDragTranslation
            detailCloseStartScale = detailDragScale
            detailCloseStartRotation = detailDragRotation
            resetDetailInteraction(animated: true)
            handleDetailDismissal(fromGesture: true)
        } else {
            resetDetailInteraction(animated: true)
            if let sessionId = detailContext?.sessionId {
                scheduleDetailSettled(for: sessionId)
            }
        }
    }

    private func handleDetailDismissal(fromGesture: Bool = false) {
        guard let context = detailContext else { return }

        detailIsInteracting = false
        if !fromGesture {
            // Back button dismissal should close from the expanded state.
            detailCloseStartTranslation = .zero
            detailCloseStartScale = 1
            detailCloseStartRotation = 0
        }
        resetDetailInteraction(animated: true)
        detailIsClosing = true
        detailIsSettled = false
        updateDetailPresentationVisibility()

        withAnimation(heroAnimator.closeAnimation()) {
            detailProgress = 0
        }

        let closingSessionId = context.sessionId
        DispatchQueue.main.asyncAfter(deadline: .now() + heroAnimator.closeDuration + 0.1) {
            if detailContext?.sessionId == closingSessionId {
                detailContext = nil
                detailIsClosing = false
                detailProgress = 0
                detailContentOpacity = 0
                detailIsSettled = false
            } else if detailContext == nil {
                detailIsClosing = false
                detailProgress = 0
                detailContentOpacity = 0
                detailIsSettled = false
            }

            detailIsInteracting = false
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

    private var detailEdgeDragGesture: AnyGesture<DragGesture.Value> {
        AnyGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged(handleDetailDragChanged)
                .onEnded(handleDetailDragEnded)
        )
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }

    private var headerOpacity: Double {
        headerMetrics.headerOpacity(for: scrollOffset)
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
