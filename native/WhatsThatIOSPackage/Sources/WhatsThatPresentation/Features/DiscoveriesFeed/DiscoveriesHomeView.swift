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
    private let feedUseCase: DiscoveryFeedUseCase
    private let deletionUseCase: DiscoveryDeletionUseCase
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    @Binding private var pendingDiscoveryId: Int64?
    @Binding private var pendingCreatedSummary: DiscoverySummary?
    private let onSignOut: () -> Void
    private let onSettings: (() -> Void)?

    @StateObject private var viewModel: DiscoveryFeedViewModel
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
        feedUseCase: DiscoveryFeedUseCase,
        deletionUseCase: DiscoveryDeletionUseCase,
        voiceoverController: VoiceoverPlaybackController,
        pendingDiscoveryId: Binding<Int64?>,
        pendingCreatedSummary: Binding<DiscoverySummary?>,
        onSignOut: @escaping () -> Void,
        onSettings: (() -> Void)? = nil
    ) {
        self.feedUseCase = feedUseCase
        self.deletionUseCase = deletionUseCase
        self._voiceoverController = ObservedObject(initialValue: voiceoverController)
        self._pendingDiscoveryId = pendingDiscoveryId
        self._pendingCreatedSummary = pendingCreatedSummary
        self.onSignOut = onSignOut
        self.onSettings = onSettings
        _viewModel = StateObject(wrappedValue: DiscoveryFeedViewModel(feedUseCase: feedUseCase))
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

            ZStack(alignment: .top) {
                backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        refreshHeaderView(metrics: metrics)

                        DiscoveriesGridView(
                            viewModel: viewModel,
                            availableWidth: contentWidth,
                            cardSpacing: gridSpacing,
                            cardFrames: $cardFrames,
                            activeDiscoveryId: detailCoordinator.snapshot.activeDiscoveryId,
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
                .onChange(of: viewModel.isRefreshing) { _, newValue in
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
                .onChange(of: viewModel.errorMessage) { _, newValue in
                    if let message = newValue?.nonEmptyOrNil, !viewModel.discoveries.isEmpty {
                        refreshErrorMessage = message
                    } else if newValue == nil {
                        refreshErrorMessage = nil
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

                let detailSnapshot = detailCoordinator.snapshot
                if detailSnapshot.hasActiveOverlay, let context = detailSnapshot.context {
                    let targetCloseFrame = cardFrames[context.discovery.id] ?? context.startFrame
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
            }
            .onChange(of: safeBottom) { _, newValue in
                updateSafeAreaBottomInsetIfNeeded(newValue)
            }
            .onChange(of: safeTop) { _, newValue in
                updateSafeAreaTopInsetIfNeeded(newValue)
            }
        }
        .overlay(alignment: .bottom) {
            Group {
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
                    .padding(.horizontal, BrandSpacing.large)
                    .padding(.bottom, BrandSpacing.medium)
                }
            }
        }
        .animation(.easeInOut, value: viewModel.loadState)
        .alert(
            "An error occurred",
            isPresented: Binding(
                get: { refreshErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        refreshErrorMessage = nil
                        viewModel.clearError()
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    refreshErrorMessage = nil
                    viewModel.clearError()
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

    private func handleDiscoverySelection(discovery: DiscoverySummary, imageURL: URL?, startFrame: CGRect) {
        let resolvedImageURL = imageURL ?? self.imageURL(for: discovery)
        detailCoordinator.present(
            discovery: discovery,
            cardFrame: startFrame,
            imageURL: resolvedImageURL
        )
    }

    private func presentPendingDiscoveryIfNeeded() {
        guard let pendingId = pendingDiscoveryId,
              !detailCoordinator.snapshot.phase.isActive
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
                await MainActor.run {
                    viewModel.remove(discovery)
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
        let shouldShowIndicator = viewModel.isRefreshing || pullDistance > refreshIndicatorRevealThreshold
        let indicatorOpacity: Double = {
            if viewModel.isRefreshing {
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
