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
    /// When true, the settings icon shows as selected (filled with orange)
    private var isSettingsSelected: Bool
    private let onQuickCamera: (() -> Void)?
    private let onQuickUpload: (() -> Void)?
    private let onOpenAudioGuide: ((DiscoverySummary) -> Void)?

    @StateObject private var detailCoordinator: DiscoveryDetailTransitionCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.audioServices) private var audioServices
    @State private var scrollOffset: CGFloat = 0
    @State private var safeAreaBottomInset: CGFloat = 0
    @State private var headerHeight: CGFloat = 110
    @State private var safeAreaTopInset: CGFloat = 0
    @State private var refreshErrorMessage: String?
    @State private var deletingDiscoveryId: Int64?
    @State private var isDeletionInProgress = false
    @State private var deletionErrorMessage: String?
    @State private var isDetailFromAudioGuides = false
    @State private var isDetailViewWarmedUp = false

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
        isSettingsSelected: Bool = false,
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
        self.isSettingsSelected = isSettingsSelected
        self.onQuickCamera = onQuickCamera
        self.onQuickUpload = onQuickUpload
        self.onOpenAudioGuide = onOpenAudioGuide
        _detailCoordinator = StateObject(
            wrappedValue: DiscoveryDetailTransitionCoordinator(voiceoverController: voiceoverController)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            mainContent(proxy: proxy)
        }
        .overlay(alignment: .bottom) {
            paginatingOverlay
        }
        .animation(.easeInOut, value: storeObserver.loadState)
        .alert(
            "An error occurred",
            isPresented: refreshErrorBinding,
            actions: { refreshErrorActions },
            message: { refreshErrorMessage_view }
        )
        .overlay {
            deletionErrorOverlay
        }
    }
    
    // MARK: - Body Sub-expressions
    
    private func mainContent(proxy: GeometryProxy) -> some View {
        let safeBottom = proxy.safeAreaInsets.bottom
        let safeTop = proxy.safeAreaInsets.top
        let _ = proxy.size // retain to keep dependency updates
        let gridAvailableWidth = proxy.size.width == 0 ? UIScreen.main.bounds.width : proxy.size.width
        let contentWidth = max(gridAvailableWidth - (gridHorizontalPadding * 2), 0)
        let metrics = headerMetrics
        let contentHeight = max(
            proxy.size.height - metrics.headerSpacerHeight - metrics.gridTopPadding - gridBottomPadding,
            0
        )
        
        return ZStack(alignment: .top) {
            backgroundColor
                .ignoresSafeArea()
            
            scrollContent(contentWidth: contentWidth, contentHeight: contentHeight, metrics: metrics)
            
            headerContent(contentWidth: contentWidth, metrics: metrics)

            detailOverlayContent

            // Invisible warmup view to pre-compile the detail overlay view hierarchy.
            // This eliminates first-tap animation jank by forcing SwiftUI to compile
            // the complex view before the user interacts with it.
            if !isDetailViewWarmedUp {
                DiscoveryDetailWarmupView(
                    voiceoverController: voiceoverController,
                    backgroundColor: backgroundColor,
                    colorScheme: colorScheme
                )
                .allowsHitTesting(false)
                .zIndex(-1)
            }
        }
        .task {
            // Schedule warmup completion after the warmup animation completes (300ms + buffer)
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms
            isDetailViewWarmedUp = true
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
    
    private func scrollContent(contentWidth: CGFloat, contentHeight: CGFloat, metrics: DiscoveriesHeaderMetrics) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                refreshHeaderView(metrics: metrics)
                
                DiscoveriesGridView(
                    storeObserver: storeObserver,
                    availableWidth: contentWidth,
                    availableHeight: contentHeight,
                    cardSpacing: gridSpacing,
                    activeDiscoveryId: detailCoordinator.snapshot.activeDiscoveryId,
                    deletingDiscoveryId: deletingDiscoveryId,
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

            // Prefetch voiceover metadata to avoid jank on first tap
            if storeObserver.loadState == .loaded && !storeObserver.discoveries.isEmpty {
                prefetchVoiceovers(for: storeObserver.discoveries)
            }

            presentPendingDiscoveryIfNeeded()
            resolveOpenFromAudioGuidesIfNeeded()
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { rawValue in
            guard let rawValue else { return }
            let adjusted = rawValue + metrics.gridTopPadding
            scrollOffset = adjusted
        }
        .onChange(of: storeObserver.discoveries) { oldValue, newValue in
            // Prefetch voiceovers for newly added discoveries
            let oldIds = Set(oldValue.map { $0.id })
            let newDiscoveries = newValue.filter { !oldIds.contains($0.id) }
            if !newDiscoveries.isEmpty {
                prefetchVoiceovers(for: newDiscoveries)
            }

            DispatchQueue.main.async {
                presentPendingDiscoveryIfNeeded()
                resolveOpenFromAudioGuidesIfNeeded()
            }
        }
        .onChange(of: pendingDiscoveryId) {
            DispatchQueue.main.async {
                presentPendingDiscoveryIfNeeded()
            }
        }
        .onChange(of: openFirstDetailFromAudioGuides) { _, newValue in
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
        .onChange(of: storeObserver.errorMessage) { _, newValue in
            if let message = newValue?.nonEmptyOrNil, !storeObserver.discoveries.isEmpty {
                refreshErrorMessage = message
            } else if newValue == nil {
                refreshErrorMessage = nil
            }
        }
    }
    
    private func headerContent(contentWidth: CGFloat, metrics: DiscoveriesHeaderMetrics) -> some View {
        let headerOpacityStretched = headerOpacityFollowingFirstRow(availableWidth: contentWidth)
        
        return DiscoveriesHeaderView(
            opacity: headerOpacityStretched,
            metrics: metrics,
            backgroundColor: backgroundColor,
            onSignOut: onSignOut,
            onSettings: onSettings,
            isSettingsSelected: isSettingsSelected
        )
        .onPreferenceChange(HeaderHeightPreferenceKey.self) { value in
            guard value > 0 else { return }
            if abs(value - headerHeight) > 0.5 {
                headerHeight = value
            }
        }
    }
    
    @ViewBuilder
    private var detailOverlayContent: some View {
        let detailSnapshot = detailCoordinator.snapshot
        if detailSnapshot.hasActiveOverlay, let context = detailSnapshot.context {
            let targetCloseFrame = computeTargetCloseFrame(context: context)
            
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
                onShowOptions: {},  // Enable options/share/map buttons
                onOpenAudioGuide: onOpenAudioGuide,
                onScrollContentOffsetChanged: { detailCoordinator.updateContentScrollOffset($0) }
            )
            .ignoresSafeArea(edges: .top)
            .transition(.identity)
            .simultaneousGesture(detailEdgeDragGesture, including: .gesture)
            .zIndex(5)
        }
    }
    
    private func computeTargetCloseFrame(context: DiscoveryDetailContext) -> CGRect {
        let isLargeFallback = context.startFrame.width > (UIScreen.main.bounds.width * 0.6)
        
        if !isLargeFallback {
            return context.startFrame
        }
        
        return resolveCloseFrame(for: context.discovery.id) ?? context.startFrame
    }
    
    @ViewBuilder
    private var paginatingOverlay: some View {
        if storeObserver.isPaginating {
            HStack(spacing: BrandSpacing.small) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: BrandColors.spinner))
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
    
    private var refreshErrorBinding: Binding<Bool> {
        Binding(
            get: { refreshErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    refreshErrorMessage = nil
                    storeObserver.clearError()
                }
            }
        )
    }
    
    @ViewBuilder
    private var refreshErrorActions: some View {
        Button("OK", role: .cancel) {
            refreshErrorMessage = nil
            storeObserver.clearError()
        }
    }
    
    private var refreshErrorMessage_view: some View {
        Text(refreshErrorMessage ?? "Please try again later.")
    }
    
    private var deletionErrorOverlay: some View {
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

    private func handleDiscoverySelection(
        discovery: DiscoverySummary,
        imageURL: URL?,
        startFrame: CGRect,
        animated: Bool = true,
        fromAudioGuides: Bool = false
    ) {
        // Prevent strictly redundant presentations
        if detailCoordinator.snapshot.activeDiscoveryId == discovery.id {
             if detailCoordinator.snapshot.phase.isActive {
                 discoveriesHomeLogger.info("Ignoring redundant presentation for active discovery id=\(discovery.id)")
                 return
             }
        }
        
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
        guard let pendingId = pendingDiscoveryId else {
            return
        }

        guard let discovery = storeObserver.discoveries.first(where: { $0.id == pendingId }) else {
            return
        }

        let isOverlayActive = detailCoordinator.snapshot.phase.isActive
        let activeId = detailCoordinator.snapshot.context?.discovery.id

        // If already showing the pending discovery, just clear the pending ID
        if let activeId, activeId == pendingId {
            pendingDiscoveryId = nil
            return
        }
        
        // Anti-thrash: if the coordinator is already preparing/animating this ID, stop.
        if detailCoordinator.snapshot.activeDiscoveryId == pendingId {
            pendingDiscoveryId = nil
            return
        }

        let startFrame = resolveStartFrame(for: discovery.id) ?? fallbackStartFrame()
        // No animation when replacing an active overlay (instant switch)
        let shouldAnimate = !isOverlayActive

        pendingDiscoveryId = nil
        discoveriesHomeLogger.info("Pending discovery resolved id=\(discovery.id, privacy: .public) animated=\(shouldAnimate, privacy: .public)")
        handleDiscoverySelection(
            discovery: discovery,
            imageURL: imageURL(for: discovery),
            startFrame: startFrame,
            animated: shouldAnimate,
            fromAudioGuides: false
        )
    }

    private func resolveStartFrame(for discoveryId: Int64) -> CGRect? {
        // Since we removed cardFrames, we rely on the frame passed during selection.
        // For programmatic access (deep links, pending), we don't have the frame.
        return nil
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

    private func resolveOpenFromAudioGuidesIfNeeded() {
        guard openFirstDetailFromAudioGuides else {
            return
        }

        // Require an explicit target from Audio Guides; do not fall back to first.
        let targetId = audioGuidesTargetDiscoveryId ?? audioGuidesTargetDiscoverySummary?.id
        guard let discoveryId = targetId else {
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
        
        // Dismiss the detail view INSTANTLY (no animation) so the user immediately sees the delete animation on the grid
        detailCoordinator.dismiss(reason: .backButton, animated: false)

        Task {
            do {
                try await deletionUseCase.delete(discovery)
                await storeObserver.remove(discovery)
                await MainActor.run {
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

    /// Prefetches voiceover metadata for the given discoveries.
    /// Fire-and-forget - VoiceoverPlaybackController handles caching and deduplication.
    private func prefetchVoiceovers(for discoveries: [DiscoverySummary]) {
        let discoveryIds = discoveries.map { $0.id }
        voiceoverController.prefetch(for: discoveryIds)
        discoveriesHomeLogger.info("Prefetched voiceovers for \(discoveryIds.count) discoveries")
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
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named("discoveriesScroll")).minY
                )
            }
        )
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
            .progressViewStyle(CircularProgressViewStyle(tint: BrandColors.spinner))
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

    private func resolveCloseFrame(for discoveryId: Int64) -> CGRect? {
        guard let index = storeObserver.discoveries.firstIndex(where: { $0.id == discoveryId }) else { return nil }
        
        // Geometry constants matching Grid
        let screen = UIScreen.main.bounds
        let availableWidth = max(screen.width - (gridHorizontalPadding * 2), 0)
        let cardWidth = max((availableWidth - gridSpacing) / 2, 120) 
        let cardHeight = cardWidth * 1.2
        let rowHeight = cardHeight + gridSpacing
        
        // Calculate visible range based on scroll offset
        // -scrollOffset is how far we've scrolled down (positive value)
        // visibleTopY relative to content start is -scrollOffset
        
        let scrolledDistance = headerMetrics.gridTopPadding - scrollOffset
        let viewportHeight = screen.height
        
        let firstVisibleRowIndex = Int(floor(scrolledDistance / rowHeight))
        let visibleRowsCount = Int(ceil(viewportHeight / rowHeight)) + 1
        let lastVisibleRowIndex = firstVisibleRowIndex + visibleRowsCount
        
        let rowIndex = index / 2
        
        let col = CGFloat(index % 2)
        let xPos = gridHorizontalPadding + col * (cardWidth + gridSpacing)
        
        if rowIndex < firstVisibleRowIndex {
            return CGRect(x: xPos, y: -cardHeight - 10, width: cardWidth, height: cardHeight)
        } else if rowIndex > lastVisibleRowIndex {
            return CGRect(x: xPos, y: screen.height + 10, width: cardWidth, height: cardHeight)
        }
        
        // Calculate the estimated on-screen frame for the card.
        // Screen Y = ScrollView Offset (relative to Safe Area Top) + Header + Safe Area + Grid Item Y
        let screenY = scrollOffset + headerMetrics.headerSpacerHeight + safeAreaTopInset + CGFloat(rowIndex) * rowHeight
         
        return CGRect(x: xPos, y: screenY, width: cardWidth, height: cardHeight)
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
