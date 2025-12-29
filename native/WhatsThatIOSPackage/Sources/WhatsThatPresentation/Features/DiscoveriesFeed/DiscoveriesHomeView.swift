import SwiftUI
import WhatsThatDomain
import WhatsThatShared
import UIKit
#if canImport(MarkdownUI)
import MarkdownUI
#endif
import OSLog

private let discoveriesHomeLogger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "DiscoveriesHomeView"
)

struct DiscoveriesHomeView: View {
    @ObservedObject private var storeObserver: DiscoveryStoreObserver
    private let deletionUseCase: DiscoveryDeletionUseCase
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    @Binding private var pendingDiscoveryId: Int64?
    @Binding private var openFirstDetailFromAudioGuides: Bool
    @Binding private var audioGuidesTargetDiscoveryId: Int64?
    @Binding private var audioGuidesTargetDiscoverySummary: DiscoverySummary?
    private let onSignOut: () -> Void
    private let onSettings: (() -> Void)?
    private let onQuickCamera: (() -> Void)?
    private let onQuickUpload: (() -> Void)?
    private let onOpenAudioGuide: ((DiscoverySummary) -> Void)?

    @StateObject private var detailCoordinator: DiscoveryDetailTransitionCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollOffset: CGFloat = 0
    @State private var cardFrames: [Int64: CGRect] = [:]
    @State private var isCardFramesReactionScheduled: Bool = false
    @State private var safeAreaBottomInset: CGFloat = 0
    @State private var headerHeight: CGFloat = 110
    @State private var safeAreaTopInset: CGFloat = 0
    @State private var refreshErrorMessage: String?
    @State private var deletingDiscoveryId: Int64?
    @State private var isDeletionInProgress = false
    @State private var deletionErrorMessage: String?
    @State private var isDetailFromAudioGuides = false

    private var headerMetrics: DiscoveriesHeaderMetrics {
        DiscoveriesHeaderMetrics(
            headerHeight: headerHeight,
            safeAreaTopInset: safeAreaTopInset
        )
    }
    private let gridSpacing: CGFloat = 1
    private let gridHorizontalPadding: CGFloat = 1
    private let gridBottomPadding: CGFloat = 16
    private let refreshIndicatorRevealThreshold: CGFloat = 12

    init(
        storeObserver: DiscoveryStoreObserver,
        deletionUseCase: DiscoveryDeletionUseCase,
        voiceoverController: VoiceoverPlaybackController,
        pendingDiscoveryId: Binding<Int64?>,
        openFirstDetailFromAudioGuides: Binding<Bool>,
        audioGuidesTargetDiscoveryId: Binding<Int64?>,
        audioGuidesTargetDiscoverySummary: Binding<DiscoverySummary?>,
        onSignOut: @escaping () -> Void,
        onSettings: (() -> Void)? = nil,
        onQuickCamera: (() -> Void)? = nil,
        onQuickUpload: (() -> Void)? = nil,
        onOpenAudioGuide: ((DiscoverySummary) -> Void)? = nil
    ) {
        self._storeObserver = ObservedObject(wrappedValue: storeObserver)
        self.deletionUseCase = deletionUseCase
        self._voiceoverController = ObservedObject(initialValue: voiceoverController)
        self._pendingDiscoveryId = pendingDiscoveryId
        self._openFirstDetailFromAudioGuides = openFirstDetailFromAudioGuides
        self._audioGuidesTargetDiscoveryId = audioGuidesTargetDiscoveryId
        self._audioGuidesTargetDiscoverySummary = audioGuidesTargetDiscoverySummary
        self.onSignOut = onSignOut
        self.onSettings = onSettings
        self.onQuickCamera = onQuickCamera
        self.onQuickUpload = onQuickUpload
        self.onOpenAudioGuide = onOpenAudioGuide
        _detailCoordinator = StateObject(
            wrappedValue: DiscoveryDetailTransitionCoordinator(voiceoverController: voiceoverController)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let safeBottom = proxy.safeAreaInsets.bottom
            let safeTop = proxy.safeAreaInsets.top

            let _ = proxy.size // retain to keep dependency updates
            let gridAvailableWidth = proxy.size.width == 0 ? UIScreen.main.bounds.width : proxy.size.width
            let contentWidth = max(gridAvailableWidth - (gridHorizontalPadding * 2), 0)
            let metrics = headerMetrics
            // Height available for grid content below the header & its padding
            let contentHeight = max(
                proxy.size.height - metrics.headerSpacerHeight - metrics.gridTopPadding - gridBottomPadding,
                0
            )

            ZStack(alignment: .top) {
                backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        refreshHeaderView(metrics: metrics)

                        DiscoveriesGridView(
                            storeObserver: storeObserver,
                            availableWidth: contentWidth,
                            availableHeight: contentHeight,
                            cardSpacing: gridSpacing,
                            cardFrames: $cardFrames,
                            activeDiscoveryId: detailCoordinator.snapshot.activeDiscoveryId,
                            onLoadMore: { discovery in
                                await storeObserver.loadMoreIfNeeded(currentItem: discovery)
                            },
                            onSelect: { discovery, imageURL, frame in
                                handleDiscoverySelection(
                                    discovery: discovery,
                                    imageURL: imageURL,
                                    startFrame: frame
                                )
                            },
                            onTapCamera: onQuickCamera,
                            onTapUpload: onQuickUpload
                        )
                        .padding(.horizontal, gridHorizontalPadding)
                        .padding(.bottom, gridBottomPadding)
                    }
                }
                .coordinateSpace(name: "discoveriesScroll")
                .miniPlayerScrollInset()
                .refreshable {
                    await storeObserver.refresh()
                }
                .task {
                    await storeObserver.loadInitialIfNeeded()
                    presentPendingDiscoveryIfNeeded()
                    resolveOpenFromAudioGuidesIfNeeded()
                }
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { rawValue in
                    guard let rawValue else { return }
                    let adjusted = rawValue - metrics.headerSpacerHeight
                    scrollOffset = adjusted
                }
                .onChange(of: storeObserver.discoveries) {
                    // Defer to next runloop to prevent "update multiple times per frame" error
                    DispatchQueue.main.async {
                        presentPendingDiscoveryIfNeeded()
                        resolveOpenFromAudioGuidesIfNeeded()
                    }
                }
                .onChange(of: pendingDiscoveryId) {
                    // Defer to next runloop to prevent "update multiple times per frame" error
                    DispatchQueue.main.async {
                        presentPendingDiscoveryIfNeeded()
                    }
                }
                .onChange(of: openFirstDetailFromAudioGuides) { _, newValue in
                    print("[DEBUG DiscoveriesHomeView] >>> onChange openFirstDetailFromAudioGuides fired: newValue=\(newValue)")
                    // Defer to next runloop to prevent "update multiple times per frame" error
                    DispatchQueue.main.async {
                        if newValue {
                            discoveriesHomeLogger.info("openFirstDetailFromAudioGuides flag set; attempting to resolve")
                            resolveOpenFromAudioGuidesIfNeeded()
                        }
                    }
                }
                .onChange(of: storeObserver.isRefreshing) { _, newValue in
                    discoveriesHomeLogger.info("isRefreshing changed: \(newValue, privacy: .public)")
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
                .onChange(of: storeObserver.errorMessage) { _, newValue in
                    if let message = newValue?.nonEmptyOrNil, !storeObserver.discoveries.isEmpty {
                        refreshErrorMessage = message
                    } else if newValue == nil {
                        refreshErrorMessage = nil
                    }
                }

                let headerOpacityStretched = headerOpacityFollowingFirstRow(availableWidth: contentWidth)

                DiscoveriesHeaderView(
                    opacity: headerOpacityStretched,
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

                let detailSnapshot = detailCoordinator.snapshot
                if detailSnapshot.hasActiveOverlay, let context = detailSnapshot.context {
                    let targetCloseFrame = cardFrames[context.discovery.id] 
                        ?? offScreenCloseFrame(for: context.discovery.id)
                    DiscoveryDetailOverlayView(
                        snapshot: detailSnapshot,
                        destinationFrame: targetCloseFrame,
                        backgroundColor: backgroundColor,
                        colorScheme: colorScheme,
                        voiceoverController: voiceoverController,
                        onClose: { detailCoordinator.dismiss(reason: .backButton) },
                        deletingDiscoveryId: deletingDiscoveryId,
                        isDeletingDiscovery: isDeletionInProgress,
                        onDelete: { handleDeleteRequest(for: $0) },
                        onShowOptions: nil,
                        onOpenAudioGuide: onOpenAudioGuide,
                        onScrollContentOffsetChanged: { detailCoordinator.updateContentScrollOffset($0) }
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
                voiceoverController.setDiscoveryQueueProvider { storeObserver.discoveries }
            }
            .onChange(of: safeBottom) { _, newValue in
                updateSafeAreaBottomInsetIfNeeded(newValue)
            }
            .onChange(of: safeTop) { _, newValue in
                updateSafeAreaTopInsetIfNeeded(newValue)
            }
            .onChange(of: storeObserver.discoveries) { _, _ in
                voiceoverController.setDiscoveryQueueProvider { storeObserver.discoveries }
            }
        }
        .overlay(alignment: .bottom) {
            Group {
                if storeObserver.isPaginating {
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
                    .padding(.horizontal, BrandSpacing.large)
                    .padding(.bottom, BrandSpacing.medium)
                }
            }
        }
        .animation(.easeInOut, value: storeObserver.loadState)
        .alert(
            "An error occurred",
            isPresented: Binding(
                get: { refreshErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        refreshErrorMessage = nil
                        storeObserver.clearError()
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    refreshErrorMessage = nil
                    storeObserver.clearError()
                }
            },
            message: {
                Text(refreshErrorMessage ?? "Please try again later.")
            }
        )
        .overlay {
            Color.clear
                .alert(
                    "Delete failed",
                    isPresented: Binding(
                        get: { deletionErrorMessage != nil },
                        set: { isPresented in
                            if !isPresented {
                                deletionErrorMessage = nil
                            }
                        }
                    ),
                    actions: {
                        Button("OK", role: .cancel) {
                            deletionErrorMessage = nil
                        }
                    },
                    message: {
                        Text(deletionErrorMessage ?? "Please try again later.")
                    }
                )
        }
    }

    private func handleDiscoverySelection(
        discovery: DiscoverySummary,
        imageURL: URL?,
        startFrame: CGRect,
        animated: Bool = true,
        fromAudioGuides: Bool = false
    ) {
        isDetailFromAudioGuides = fromAudioGuides
        discoveriesHomeLogger.info("Presenting discovery detail id=\(discovery.id, privacy: .public) animated=\(animated, privacy: .public)")
        let resolvedImageURL = imageURL ?? self.imageURL(for: discovery)
        detailCoordinator.present(
            discovery: discovery,
            cardFrame: startFrame,
            imageURL: resolvedImageURL,
            animated: animated
        )
    }

    private func presentPendingDiscoveryIfNeeded() {
        print("[DEBUG DiscoveriesHomeView] presentPendingDiscoveryIfNeeded called, pendingDiscoveryId=\(String(describing: pendingDiscoveryId))")
        guard let pendingId = pendingDiscoveryId,
              !detailCoordinator.snapshot.phase.isActive
        else {
            print("[DEBUG DiscoveriesHomeView] presentPendingDiscoveryIfNeeded: early exit (no pending or overlay active)")
            return
        }

        print("[DEBUG DiscoveriesHomeView] Looking for discovery \(pendingId) in \(storeObserver.discoveries.count) discoveries")
        guard let discovery = storeObserver.discoveries.first(where: { $0.id == pendingId }) else {
            print("[DEBUG DiscoveriesHomeView] presentPendingDiscoveryIfNeeded: discovery \(pendingId) NOT FOUND in feed")
            return
        }

        let startFrame = resolveStartFrame(for: discovery.id) ?? fallbackStartFrame()

        pendingDiscoveryId = nil
        let animated = true
        print("[DEBUG DiscoveriesHomeView] Presenting discovery \(discovery.id)")
        discoveriesHomeLogger.info("Pending discovery resolved id=\(discovery.id, privacy: .public) animated=\(animated, privacy: .public)")
        handleDiscoverySelection(
            discovery: discovery,
            imageURL: imageURL(for: discovery),
            startFrame: startFrame,
            animated: animated,
            fromAudioGuides: false
        )
    }

    private func resolveStartFrame(for discoveryId: Int64) -> CGRect? {
        if let frame = cardFrames[discoveryId], frame.width > 0, frame.height > 0 {
            return frame
        }

        guard let firstId = storeObserver.discoveries.first?.id,
              let frame = cardFrames[firstId],
              frame.width > 0,
              frame.height > 0
        else {
            return nil
        }

        return frame
    }

    private func fallbackStartFrame() -> CGRect {
        let screen = UIScreen.main.bounds
        let width = min(screen.width * 0.9, 360)
        let height = width * 1.2
        let origin = CGPoint(
            x: (screen.width - width) / 2,
            y: (screen.height - height) / 3
        )
        discoveriesHomeLogger.info("Using fallback start frame for discovery detail")
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    /// Returns a frame for an imaginary card positioned at the screen edge with just 1 pixel visible.
    /// - If above: card is positioned so only its bottom pixel is at the top of the screen (y = -cardHeight + 1)
    /// - If below: card is positioned so only its top pixel is at the bottom of the screen (y = screenHeight - 1)
    /// This produces the same animation as closing to a card that's 99% off-screen.
    private func offScreenCloseFrame(for discoveryId: Int64) -> CGRect {
        let screen = UIScreen.main.bounds
        
        // Get card dimensions from an actual visible card, or calculate if none available
        let cardSize: CGSize
        if let referenceFrame = cardFrames.values.first {
            cardSize = referenceFrame.size
        } else {
            let cardWidth = max((screen.width - gridHorizontalPadding * 2 - gridSpacing) / 2, 120)
            cardSize = CGSize(width: cardWidth, height: cardWidth * 1.2)
        }
        
        // Find the discovery's position in the list
        let discoveryIndex = storeObserver.discoveries.firstIndex { $0.id == discoveryId }
        
        // Find visible card indices
        let visibleIds = Set(cardFrames.keys)
        let visibleIndices = storeObserver.discoveries.enumerated()
            .filter { visibleIds.contains($0.element.id) }
            .map { $0.offset }
        
        let isAbove: Bool
        if let index = discoveryIndex, let minVisible = visibleIndices.min() {
            isAbove = index < minVisible
        } else {
            isAbove = false  // Default to animating down
        }
        
        // Position with just 1 pixel visible at the screen edge
        let yPosition: CGFloat
        if isAbove {
            // Card's bottom pixel at y=0 (top of screen)
            yPosition = -cardSize.height + 1
        } else {
            // Card's top pixel at screen bottom
            yPosition = screen.height - 1
        }
        
        // Center horizontally like grid cards
        let xPosition = gridHorizontalPadding
        
        return CGRect(origin: CGPoint(x: xPosition, y: yPosition), size: cardSize)
    }

    private func resolveOpenFromAudioGuidesIfNeeded() {
        print("[DEBUG DiscoveriesHomeView] resolveOpenFromAudioGuidesIfNeeded called, openFirstDetailFromAudioGuides=\(openFirstDetailFromAudioGuides)")
        guard openFirstDetailFromAudioGuides else {
            print("[DEBUG DiscoveriesHomeView] resolveOpenFromAudioGuidesIfNeeded: early exit (flag is false)")
            return
        }

        // Require an explicit target from Audio Guides; do not fall back to first.
        let targetId = audioGuidesTargetDiscoveryId ?? audioGuidesTargetDiscoverySummary?.id
        print("[DEBUG DiscoveriesHomeView] resolveOpenFromAudioGuidesIfNeeded: targetId=\(String(describing: targetId)), hasSummary=\(audioGuidesTargetDiscoverySummary != nil)")
        guard let discoveryId = targetId else {
            print("[DEBUG DiscoveriesHomeView] resolveOpenFromAudioGuidesIfNeeded: no discovery attached")
            discoveriesHomeLogger.info("AudioGuides Text tap: no discovery attached to guide")
            return
        }

        // Try to find in current feed; otherwise use the passed summary (may be from a different page).
        let feedTarget = storeObserver.discoveries.first(where: { $0.id == discoveryId })
        let resolvedTarget = feedTarget ?? audioGuidesTargetDiscoverySummary

        guard let target = resolvedTarget else {
            discoveriesHomeLogger.info("AudioGuides Text tap: target discovery not found id=\(discoveryId, privacy: .public)")
            openFirstDetailFromAudioGuides = false
            audioGuidesTargetDiscoveryId = nil
            audioGuidesTargetDiscoverySummary = nil
            return
        }

        let isOverlayActive = detailCoordinator.snapshot.phase.isActive
        let activeId = detailCoordinator.snapshot.context?.discovery.id

        let openBlock = {
            self.openFirstDetailFromAudioGuides = false
            self.audioGuidesTargetDiscoveryId = nil
            self.audioGuidesTargetDiscoverySummary = nil

            let startFrame = self.resolveStartFrame(for: target.id) ?? self.fallbackStartFrame()

            self.handleDiscoverySelection(
                discovery: target,
                imageURL: self.imageURL(for: target),
                startFrame: startFrame,
                animated: false,
                fromAudioGuides: true
            )
        }

        if isOverlayActive, let activeId, activeId != target.id {
            discoveriesHomeLogger.info("AudioGuides Text tap: replacing active discovery id=\(activeId, privacy: .public) with id=\(target.id, privacy: .public)")
            openBlock()
        } else if isOverlayActive, let activeId, activeId == target.id {
            discoveriesHomeLogger.info("AudioGuides Text tap: target already active id=\(activeId, privacy: .public); no action")
            openFirstDetailFromAudioGuides = false
            audioGuidesTargetDiscoveryId = nil
            audioGuidesTargetDiscoverySummary = nil
        } else {
            discoveriesHomeLogger.info("AudioGuides Text tap: will open discovery id=\(target.id, privacy: .public) (inFeed=\(feedTarget != nil, privacy: .public))")
            openBlock()
        }
    }

    private func handleDetailDragChanged(_ value: DragGesture.Value) {
        detailCoordinator.updateDrag(value)
    }

    private func handleDetailDragEnded(_ value: DragGesture.Value) {
        detailCoordinator.endDrag(value)
    }

    private func handleDeleteRequest(for discovery: DiscoverySummary) {
        guard !isDeletionInProgress else { return }
        deletingDiscoveryId = discovery.id
        isDeletionInProgress = true

        Task {
            do {
                try await deletionUseCase.delete(discovery)
                await storeObserver.remove(discovery)
                await MainActor.run {
                    detailCoordinator.dismiss(reason: .backButton)
                    deletingDiscoveryId = nil
                    isDeletionInProgress = false
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "We couldn't delete this discovery. Try again later."
                await MainActor.run {
                    deletionErrorMessage = message
                    deletingDiscoveryId = nil
                    isDeletionInProgress = false
                }
            }
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

    private var detailEdgeDragGesture: AnyGesture<DragGesture.Value> {
        AnyGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged(handleDetailDragChanged)
                .onEnded(handleDetailDragEnded)
        )
    }

    @ViewBuilder
    private func refreshHeaderView(metrics: DiscoveriesHeaderMetrics) -> some View {
        let pullDistance = max(scrollOffset - metrics.gridTopPadding, 0)
        let shouldShowIndicator = storeObserver.isRefreshing || pullDistance > refreshIndicatorRevealThreshold
        let indicatorOpacity: Double = {
            if storeObserver.isRefreshing {
                return 1
            } else if shouldShowIndicator {
                let pullBeyondThreshold = max(Double(pullDistance - refreshIndicatorRevealThreshold), 0)
                return min(max(pullBeyondThreshold / 60, 0.25), 1)
            } else {
                return 0
            }
        }()

        VStack(spacing: 0) {
            Color.clear
                .frame(height: metrics.headerSpacerHeight)
            Color.clear
                .frame(height: metrics.gridTopPadding)
        }
        .frame(maxWidth: .infinity)
        .overlay {
            if shouldShowIndicator {
                refreshIndicator(opacity: indicatorOpacity)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: shouldShowIndicator)
        .animation(.easeInOut(duration: 0.18), value: indicatorOpacity)
    }

    private func refreshIndicator(opacity: Double) -> some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.large)
            .scaleEffect(1.1, anchor: .center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Refreshing discoveries")
            .opacity(opacity)
            .allowsHitTesting(false)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }

    private var headerOpacity: Double {
        headerMetrics.headerOpacity(for: scrollOffset)
    }

    // Computes header opacity that starts fading after half of the first row
    // and completes once the first row is fully out of view.
    private func headerOpacityFollowingFirstRow(availableWidth: CGFloat) -> Double {
        let cardWidth = max((availableWidth - gridSpacing) / 2, 120)
        let cardHeight = cardWidth * 1.2
        let start = cardHeight * 0.5 // start fading after half row
        let end = cardHeight          // complete after full row

        // Distance scrolled past the point where the first row touches the top
        let displacement = max(0, -scrollOffset)
        let progress = (displacement - start) / max(end - start, 1)
        let clamped = min(max(progress, 0), 1)
        return 1 - Double(clamped)
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
