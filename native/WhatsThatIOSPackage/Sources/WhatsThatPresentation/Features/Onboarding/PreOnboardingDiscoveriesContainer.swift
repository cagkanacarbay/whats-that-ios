import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// Main container view for the pre-onboarding discovery gallery.
/// Displays a grid of sample discoveries, a detail overlay when tapped,
/// and a welcome modal that transitions to a slim bottom action bar.
struct PreOnboardingDiscoveriesContainer: View {
    @StateObject private var storeObserver: SampleDiscoveryStoreObserver
    @StateObject private var voiceoverController: VoiceoverPlaybackController
    @StateObject private var detailCoordinator: DiscoveryDetailTransitionCoordinator

    let onContinue: () -> Void
    let onSignIn: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollOffset: CGFloat = 0
    @State private var safeAreaTopInset: CGFloat = 0
    @State private var safeAreaBottomInset: CGFloat = 0
    @State private var headerHeight: CGFloat = 80
    @State private var isWelcomeModalVisible: Bool = true
    @State private var isDetailViewWarmedUp: Bool = false
    @State private var isMiniPlayerDismissedByUser: Bool = false

    private let gridSpacing: CGFloat = 1
    private let gridHorizontalPadding: CGFloat = 1

    /// Whether the mini player should be considered visible for layout purposes
    private var isMiniPlayerVisibleForLayout: Bool {
        // Not visible if user dismissed it
        if isMiniPlayerDismissedByUser {
            return false
        }

        switch voiceoverController.playbackState {
        case .playing, .paused, .preparing:
            return voiceoverController.currentDiscovery != nil
        default:
            return false
        }
    }

    /// Dynamic bottom padding for the grid based on whether mini player is visible
    /// - Without mini player: bottom sheet + safe area
    /// - With mini player: bottom sheet + mini player + safe area
    private var gridBottomPadding: CGFloat {
        if isMiniPlayerVisibleForLayout {
            return OnboardingLayoutConstants.bottomSheetHeight + OnboardingLayoutConstants.miniPlayerHeight + safeAreaBottomInset
        } else {
            return OnboardingLayoutConstants.bottomSheetHeight + safeAreaBottomInset
        }
    }

    init(
        discoveryService: SampleDiscoveryService,
        makeVoiceoverController: @escaping () -> VoiceoverPlaybackController,
        onContinue: @escaping () -> Void,
        onSignIn: @escaping () -> Void
    ) {
        // Create voiceover controller first so we can pass it to the coordinator
        let controller = makeVoiceoverController()
        _storeObserver = StateObject(wrappedValue: SampleDiscoveryStoreObserver(service: discoveryService))
        _voiceoverController = StateObject(wrappedValue: controller)
        _detailCoordinator = StateObject(wrappedValue: DiscoveryDetailTransitionCoordinator(voiceoverController: controller))
        self.onContinue = onContinue
        self.onSignIn = onSignIn
    }

    private var headerMetrics: DiscoveriesHeaderMetrics {
        DiscoveriesHeaderMetrics(
            headerHeight: headerHeight,
            safeAreaTopInset: safeAreaTopInset
        )
    }

    var body: some View {
        GeometryReader { proxy in
            mainContent(proxy: proxy)
        }
    }

    @ViewBuilder
    private func mainContent(proxy: GeometryProxy) -> some View {
        let safeBottom = proxy.safeAreaInsets.bottom
        let safeTop = proxy.safeAreaInsets.top
        let gridAvailableWidth = proxy.size.width == 0 ? UIScreen.main.bounds.width : proxy.size.width
        let contentWidth = max(gridAvailableWidth - (gridHorizontalPadding * 2), 0)
        let metrics = headerMetrics

        ZStack(alignment: .top) {
            backgroundColor
                .ignoresSafeArea()

            scrollContent(contentWidth: contentWidth, metrics: metrics)
                .blur(radius: isWelcomeModalVisible ? 1.5 : 0)
                .animation(.easeOut(duration: 0.3), value: isWelcomeModalVisible)

            headerView(contentWidth: contentWidth, metrics: metrics)
                .blur(radius: isWelcomeModalVisible ? 1.5 : 0)
                .animation(.easeOut(duration: 0.3), value: isWelcomeModalVisible)

            detailOverlayContent

            // Bottom area blocker - covers the safe area plus the gap behind rounded corners
            // This prevents discoveries from showing through behind the bottom sheet
            // Sits between detail overlay (zIndex 1 when closing) and bottom sheet (zIndex 2)
            if !isWelcomeModalVisible {
                VStack {
                    Spacer()
                    backgroundColor
                        .frame(height: safeAreaBottomInset + OnboardingLayoutConstants.bottomAreaBlockerOverlap)
                }
                .ignoresSafeArea(edges: .bottom)
                .zIndex(1.5)
            }

            // Bottom bar (always visible when not in welcome modal)
            if !isWelcomeModalVisible {
                VStack {
                    Spacer()
                    PreOnboardingBottomSheetView(
                        onContinue: handleContinue,
                        onSignIn: handleSignIn
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: isWelcomeModalVisible)
                .zIndex(2)
            }

            // Mini player (shown above bottom bar, visible even in detail view)
            if !isWelcomeModalVisible {
                VStack {
                    Spacer()
                    PreOnboardingMiniPlayer(
                        voiceoverController: voiceoverController,
                        discoveries: storeObserver.discoveries,
                        isDismissedByUser: $isMiniPlayerDismissedByUser
                    )
                }
                // Position depends on context:
                // - Detail view (presented): just above safe area
                // - Discoveries page or closing: above bottom sheet (button + link + padding)
                // Use phase == .presented so animation starts immediately when closing begins
                .padding(.bottom, detailCoordinator.snapshot.phase == .presented
                    ? BrandSpacing.medium + safeAreaBottomInset
                    : OnboardingLayoutConstants.miniPlayerDetailViewBottomPadding + safeAreaBottomInset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: voiceoverController.playbackState)
                .animation(.easeInOut(duration: 0.25), value: detailCoordinator.snapshot.phase)
                .zIndex(6) // Above detail overlay (zIndex 5)
            }

            // Welcome modal overlay
            if isWelcomeModalVisible {
                PreOnboardingWelcomeModal {
                    isWelcomeModalVisible = false
                }
                .zIndex(10)
            }

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
            try? await Task.sleep(nanoseconds: OnboardingLayoutConstants.detailViewWarmupDelayNanoseconds)
            isDetailViewWarmedUp = true
        }
        .onAppear {
            updateSafeAreaBottomInsetIfNeeded(safeBottom)
            updateSafeAreaTopInsetIfNeeded(safeTop)
            // Set up discovery queue provider for the voiceover controller
            voiceoverController.setDiscoveryQueueProvider { [weak storeObserver] in
                storeObserver?.discoveries ?? []
            }
        }
        .onChange(of: safeBottom) { _, newValue in
            updateSafeAreaBottomInsetIfNeeded(newValue)
        }
        .onChange(of: safeTop) { _, newValue in
            updateSafeAreaTopInsetIfNeeded(newValue)
        }
    }

    // MARK: - Actions

    private func handleContinue() {
        // Stop audio playback before navigating away
        voiceoverController.pause()
        onContinue()
    }

    private func handleSignIn() {
        // Stop audio playback before navigating away
        voiceoverController.pause()
        onSignIn()
    }

    @ViewBuilder
    private func scrollContent(contentWidth: CGFloat, metrics: DiscoveriesHeaderMetrics) -> some View {
        // For pre-onboarding, the header doesn't extend into safe area,
        // so we need to use the full header height plus a small gap
        let headerSpacerHeight = headerHeight + BrandSpacing.small

        ScrollView {
            VStack(spacing: 0) {
                // Header spacer - accounts for full header height
                Color.clear
                    .frame(height: headerSpacerHeight)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named("preOnboardingScroll")).minY
                            )
                        }
                    )

                // Grid content
                gridContent(contentWidth: contentWidth)
                    .padding(.horizontal, gridHorizontalPadding)
                    .padding(.bottom, gridBottomPadding)
            }
        }
        .coordinateSpace(name: "preOnboardingScroll")
        .task {
            await storeObserver.loadSampleDiscoveries()

            // After discoveries load, fetch and register voiceover assets
            if storeObserver.loadState == .loaded {
                let voiceovers = await storeObserver.fetchVoiceovers()
                for asset in voiceovers {
                    voiceoverController.applyFetchedAsset(asset)
                }
            }
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { rawValue in
            guard let rawValue else { return }
            scrollOffset = rawValue
        }
    }

    @ViewBuilder
    private func gridContent(contentWidth: CGFloat) -> some View {
        let cardWidth = max((contentWidth - gridSpacing) / 2, 120)
        let cardHeight = cardWidth * 1.2

        switch storeObserver.loadState {
        case .loading, .idle:
            skeletonGrid(contentWidth: contentWidth, cardWidth: cardWidth, cardHeight: cardHeight)
        case .failed:
            errorView
        case .loaded:
            if storeObserver.discoveries.isEmpty {
                emptyView
            } else {
                discoveryGrid(contentWidth: contentWidth, cardWidth: cardWidth, cardHeight: cardHeight)
            }
        }
    }

    private func skeletonGrid(contentWidth: CGFloat, cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let gridColumns = [
            GridItem(.fixed(cardWidth), spacing: gridSpacing, alignment: .top),
            GridItem(.fixed(cardWidth), spacing: gridSpacing, alignment: .top)
        ]
        let placeholderItems = Array(0..<6)

        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: gridSpacing) {
            ForEach(placeholderItems, id: \.self) { _ in
                DiscoveryCardSkeletonView(width: cardWidth, height: cardHeight)
            }
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private func discoveryGrid(contentWidth: CGFloat, cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let gridColumns = [
            GridItem(.fixed(cardWidth), spacing: gridSpacing, alignment: .top),
            GridItem(.fixed(cardWidth), spacing: gridSpacing, alignment: .top)
        ]

        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: gridSpacing) {
            ForEach(storeObserver.discoveries) { discovery in
                DiscoveryCardView(
                    discovery: discovery,
                    width: cardWidth,
                    height: cardHeight,
                    isHidden: detailCoordinator.snapshot.activeDiscoveryId == discovery.id,
                    isDeleting: false,
                    onSelect: { selectedDiscovery, imageURL, frame in
                        handleDiscoverySelection(
                            discovery: selectedDiscovery,
                            imageURL: imageURL,
                            startFrame: frame
                        )
                    }
                )
            }
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private var errorView: some View {
        VStack(spacing: BrandSpacing.medium) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundColor(palette.textSecondary)

            Text("Connect to the internet")
                .font(.adaptiveSystem(size: 17, weight: .medium))
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)

            Text("We need a connection to load the sample discoveries.")
                .font(.adaptiveSystem(size: 14, weight: .regular))
                .foregroundColor(palette.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)

            BrandSecondaryButton(title: "Refresh") {
                Task { await storeObserver.reload() }
            }
        }
        .padding(BrandSpacing.xLarge)
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.medium) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(palette.textSecondary)

            Text("No samples available")
                .font(.adaptiveSystem(size: 17, weight: .medium))
                .foregroundColor(palette.textSecondary)
        }
        .padding(BrandSpacing.xLarge)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func headerView(contentWidth: CGFloat, metrics: DiscoveriesHeaderMetrics) -> some View {
        let headerOpacityStretched = headerOpacityFollowingFirstRow(availableWidth: contentWidth)

        PreOnboardingHeaderView(
            opacity: headerOpacityStretched,
            metrics: metrics,
            backgroundColor: backgroundColor
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
            // When closing/dismissing, put detail behind bottom sheet (zIndex 2)
            // When presented, keep it above (zIndex 5)
            let isClosing = detailSnapshot.phase == .closing || detailSnapshot.phase == .interactiveDismiss
            let detailZIndex: Double = isClosing ? 1 : 5

            DiscoveryDetailOverlayView(
                snapshot: detailSnapshot,
                destinationFrame: targetCloseFrame,
                backgroundColor: backgroundColor,
                colorScheme: colorScheme,
                voiceoverController: voiceoverController,
                onClose: { detailCoordinator.dismiss(reason: .backButton) },
                deletingDiscoveryId: nil,
                isDeletingDiscovery: false,
                onDelete: nil,          // No delete in pre-onboarding
                onShowOptions: nil,     // No options menu in pre-onboarding
                onOpenAudioGuide: nil,  // No audio guide creation in pre-onboarding
                onScrollContentOffsetChanged: { detailCoordinator.updateContentScrollOffset($0) }
            )
            .ignoresSafeArea(edges: .top)
            .transition(.identity)
            .simultaneousGesture(detailEdgeDragGesture, including: .gesture)
            .zIndex(detailZIndex)
        }
    }

    // MARK: - Helpers

    private func handleDiscoverySelection(
        discovery: DiscoverySummary,
        imageURL: URL?,
        startFrame: CGRect
    ) {
        if detailCoordinator.snapshot.activeDiscoveryId == discovery.id {
            if detailCoordinator.snapshot.phase.isActive {
                return
            }
        }

        let resolvedImageURL = imageURL ?? self.imageURL(for: discovery)
        detailCoordinator.present(
            discovery: discovery,
            cardFrame: startFrame,
            imageURL: resolvedImageURL,
            animated: true
        )
    }

    private func computeTargetCloseFrame(context: DiscoveryDetailContext) -> CGRect {
        let isLargeFallback = context.startFrame.width > (UIScreen.main.bounds.width * 0.6)

        if !isLargeFallback {
            return context.startFrame
        }

        return resolveCloseFrame(for: context.discovery.id) ?? context.startFrame
    }

    private func resolveCloseFrame(for discoveryId: Int64) -> CGRect? {
        guard let index = storeObserver.discoveries.firstIndex(where: { $0.id == discoveryId }) else { return nil }

        let screen = UIScreen.main.bounds
        let availableWidth = max(screen.width - (gridHorizontalPadding * 2), 0)
        let cardWidth = max((availableWidth - gridSpacing) / 2, 120)
        let cardHeight = cardWidth * 1.2
        let rowHeight = cardHeight + gridSpacing

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

        let screenY = scrollOffset + headerMetrics.headerSpacerHeight + safeAreaTopInset + CGFloat(rowIndex) * rowHeight

        return CGRect(x: xPos, y: screenY, width: cardWidth, height: cardHeight)
    }

    private func headerOpacityFollowingFirstRow(availableWidth: CGFloat) -> Double {
        let cardWidth = max((availableWidth - gridSpacing) / 2, 120)
        let cardHeight = cardWidth * 1.2
        let start = cardHeight * 0.5
        let end = cardHeight

        let displacement = max(0, -scrollOffset)
        let progress = (displacement - start) / max(end - start, 1)
        let clamped = min(max(progress, 0), 1)
        return 1 - Double(clamped)
    }

    private func imageURL(for discovery: DiscoverySummary) -> URL? {
        guard let path = discovery.imagePath else { return nil }
        return URL(string: path)
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

    private var detailEdgeDragGesture: AnyGesture<DragGesture.Value> {
        AnyGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { value in detailCoordinator.updateDrag(value) }
                .onEnded { value in detailCoordinator.endDrag(value) }
        )
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }
}

// MARK: - Pre-Onboarding Header

private struct PreOnboardingHeaderView: View {
    let opacity: Double
    let metrics: DiscoveriesHeaderMetrics
    let backgroundColor: Color

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: metrics.headerStackSpacing) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What's That?")
                        .font(.adaptiveSystem(size: 28, weight: .bold))
                        .foregroundStyle(palette.textPrimary)

                    Text("The world is full of stories")
                        .font(.adaptiveSystem(size: 14, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.top, metrics.headerTopPadding)

            // Matches the main header's subtle separator
            Color.clear
                .frame(height: 1)
        }
        .background(
            LinearGradient(
                colors: [
                    backgroundColor,
                    backgroundColor.opacity(0.92),
                    backgroundColor.opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HeaderHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        )
        .opacity(opacity)
    }
}
