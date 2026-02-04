import Foundation
import SwiftUI
import WhatsThatDomain
import WhatsThatShared
#if canImport(MarkdownUI)
import MarkdownUI
#endif
import UIKit
struct DiscoveryStreamingStageView: View {
    @ObservedObject private var viewModel: DiscoveryCreationFlowViewModel
    let imageData: Data?
    let capturedAt: Date?
    let onCancel: () -> Void
    let onNewDiscovery: (() -> Void)?
    private let makeCreditsViewModel: (() -> CreditsViewModel)?

    init(
        viewModel: DiscoveryCreationFlowViewModel,
        imageData: Data?,
        capturedAt: Date?,
        onCancel: @escaping () -> Void,
        onNewDiscovery: (() -> Void)? = nil,
        makeCreditsViewModel: (() -> CreditsViewModel)? = nil
    ) {
        self.viewModel = viewModel
        self.imageData = imageData
        self.capturedAt = capturedAt
        self.onCancel = onCancel
        self.onNewDiscovery = onNewDiscovery
        self.makeCreditsViewModel = makeCreditsViewModel
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.audioServices) private var audioServices
    @State private var displayedMarkdown: String = ""
    @State private var loaderCleared: Bool = false
    @State private var shuffledMessages: [String] = DiscoveryStreamingStageView.loadingMessages.shuffled()
    @State private var currentMessageIndex: Int = 0
    @State private var markdownAnimationTask: Task<Void, Never>?
    // For smooth crossfade between loader messages
    @State private var previousMessage: String? = nil
    @State private var previousMessageOpacity: Double = 0
    @State private var currentMessageOpacity: Double = 1
    @State private var metadataVisible: Bool = false
    @State private var hasScrolledToContent = false
    @State private var shouldScrollToBottom = false
    @State private var hasLoggedStreamStart = false
    @State private var hasLoggedStreamEnd = false
    @State private var hasLoggedMetadata = false
    @State private var isImageFullscreenPresented = false
    @State private var shareSheetPayload: DiscoveryDetailSharePayload?
    @State private var shareSheetDetent: PresentationDetent = .medium

    private enum Layout {
        static let headerHeightFactor: CGFloat = 0.72
        static let minimumHeaderHeight: CGFloat = 360
        static let minimumHeaderWidth: CGFloat = 320
    }

    private enum AnimationConstants {
        static let minimumCharacterDelay: Double = 0.002
        static let maximumCharacterDelay: Double = 0.02
        static let speedMultiplier: Double = 1.0 / 3.0
        static let minimumAcceleratedDelay = minimumCharacterDelay * speedMultiplier
    }

    #if DEBUG
    private let debugLoggingEnabled = true
    #else
    private let debugLoggingEnabled = false
    #endif

    private var palette: DiscoveryCreationPalette {
        DiscoveryCreationPalette.resolve(for: colorScheme)
    }

    // Read the current analysis state from the view model to allow streaming updates
    private var state: DiscoveryAnalysisState {
        viewModel.analysisState ?? DiscoveryAnalysisState()
    }

    private var previewImage: Image? {
        guard
            let data = imageData,
            let uiImage = UIImage(data: data)
        else {
            return nil
        }
        return Image(uiImage: uiImage)
    }

    private var currentLoadingMessage: String {
        guard !shuffledMessages.isEmpty else { return "" }
        let index = min(currentMessageIndex, shuffledMessages.count - 1)
        return shuffledMessages[index]
    }

    private var currentMarkdown: String {
        // Prefer already-formatted markdown if present, otherwise derive
        // narrative from streamed text while stripping metadata JSON.
        let trimmed = state.displayMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return DiscoveryStreamFormatter.narrative(from: state.streamedText)
    }

    private var shouldShowLoader: Bool {
        !loaderCleared
    }
    


    var body: some View {
        // Safety guard: if analysis state is nil (e.g. flow cancelled), do not render the stage.
        // This prevents "update multiple times per frame" crashes caused by the view trying to
        // process an empty/default state before it is removed from the hierarchy.
        if viewModel.analysisState == nil {
            Color.clear
        } else {
            GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Match DiscoveryHero overlay behavior: place a placeholder
                        // header inside the scroll content and overlay the image onto it
                        // so the entire page (including the image) scrolls together.
                        // Reserve only the visible header height. The image is drawn
                        // in a top overlay and already extends into the safe area.
                        let reservedHeight = max(proxy.size.height * Layout.headerHeightFactor, Layout.minimumHeaderHeight)
                        let safeTop = proxy.safeAreaInsets.top
                        let headerWidth = max(proxy.size.width, Layout.minimumHeaderWidth)
                        Color.clear
                            .frame(height: reservedHeight)
                            // Layer image first so it remains stable
                            .overlay(
                                headerImageSection(size: proxy.size, safeTop: safeTop)
                                    .ignoresSafeArea(edges: .top)
                                    .compositingGroup(),
                                alignment: .bottom
                            )
                            // Then overlay the text/loader in its own compositing group
                            .overlay(
                                headerOverlayContent(width: headerWidth)
                                    .padding(.horizontal, BrandSpacing.large)
                                    .padding(.bottom, BrandSpacing.large * CGFloat(1.2))
                                    .compositingGroup(),
                                alignment: .bottom
                            )

                        // Audio controls and markdown only shown when content has arrived
                        // Hidden in pre-streaming state to place button directly below header
                        if !state.streamedText.isEmpty {
                            // Audio controls - shown when stream completes and discovery summary is available
                            // Placed at top to match DiscoveryDetailView
                            audioControlsSection
                                .padding(.top, -6)
                                .padding(.horizontal, BrandSpacing.large)

                            markdownSection
                                .id(ScrollTarget.markdown)
                        }

                        // "Discover More" button - shown before content arrives and after streaming completes
                        // Hidden only while actively streaming content
                        if (!state.isStreaming || state.streamedText.isEmpty), let onNewDiscovery {
                            newDiscoveryButton(action: onNewDiscovery)
                                .padding(.horizontal, BrandSpacing.large)
                                .padding(.top, state.streamedText.isEmpty ? BrandSpacing.large : 0)
                                .padding(.bottom, BrandSpacing.large)
                                .id(ScrollTarget.bottomAction)
                        }

                        // Mini player filler: extends the background color downward when mini player is visible
                        // Applies whenever the "Discover More" button is shown (before streaming and after completion)
                        // Uses a wrapper view with @ObservedObject to properly observe nested ObservableObject changes
                        if (!state.isStreaming || state.streamedText.isEmpty), let audioServices {
                            MiniPlayerFillerView(
                                miniPlayerPresence: audioServices.miniPlayerPresence,
                                backgroundColor: palette.background
                            )
                        }

                        // Scroll anchor at the very bottom of content (after filler)
                        Color.clear
                            .frame(height: 1)
                            .id(ScrollTarget.contentBottom)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Image/header drawn inside content overlay, so the whole page scrolls.
                // Only ignore top safe area so tab bar remains visible during streaming
                .background(palette.background.ignoresSafeArea(edges: .top))
                .onAppear {
                    // Check if this is a restoration (streaming already complete on appear)
                    let isRestoration = !state.isStreaming && !state.streamedText.isEmpty
                    // Check if this is pre-streaming (no content yet, button should be visible)
                    let isPreStreaming = state.streamedText.isEmpty
                    shouldScrollToBottom = isRestoration

                    resetStateForInitialRender()

                    DispatchQueue.main.async {
                        if isPreStreaming {
                            // Pre-streaming: scroll to show the button above mini player
                            scrollToButton(using: scrollProxy, animated: false)
                        } else if loaderCleared {
                            if shouldScrollToBottom {
                                scrollToBottom(using: scrollProxy, animated: false)
                            } else {
                                scrollToContent(using: scrollProxy, animated: false)
                            }
                        }
                    }
                }
                .onDisappear {
                    markdownAnimationTask?.cancel()
                }
                .overlay(alignment: .topLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .buttonStyle(
                        DiscoveryCreationOverlayButtonStyle(
                            palette: palette,
                            shape: .circle()
                        )
                    )
                    .padding(.leading, BrandSpacing.large)
                    .padding(.top, BrandSpacing.xLarge)
                }
                .onChange(of: state.displayMarkdown) {
                    // Defer to next runloop to prevent "update multiple times per frame" error
                    DispatchQueue.main.async {
                        updateDisplayedMarkdown()
                    }
                }
                .onAppear {
                    logStreamStarted()
                }
                .onChange(of: state.streamedText) {
                    // Defer to next runloop to prevent "update multiple times per frame" error
                    DispatchQueue.main.async { [self] in
                        // Throttle noisy updates: only consider stream text for clearing
                        // the loader if we still have no metadata and the loader is visible.
                        guard !loaderCleared,
                              (state.metadataTitle?.isEmpty ?? true) && (state.metadataShortDescription?.isEmpty ?? true)
                        else { return }
                        evaluateLoaderCleared(with: currentMarkdown)
                    }
                }
                .onChange(of: state.metadataTitle) {
                    // Defer to next runloop to prevent "update multiple times per frame" error
                    DispatchQueue.main.async { [self] in
                        logMetadataVisibleIfNeeded()
                        evaluateMetadataVisibility()
                        evaluateLoaderCleared(with: displayedMarkdown)
                    }
                }
                .onChange(of: state.metadataShortDescription) {
                    // Defer to next runloop to prevent "update multiple times per frame" error
                    DispatchQueue.main.async { [self] in
                        logMetadataVisibleIfNeeded()
                        evaluateMetadataVisibility()
                        evaluateLoaderCleared(with: displayedMarkdown)
                    }
                }
                .onChange(of: state.isStreaming) {
                    // Capture values NOW before async dispatch to avoid race condition.
                    // The `state` computed property reads from viewModel.analysisState, which
                    // could become nil (returning default with isStreaming=true) if the view
                    // hierarchy changes before the async block executes.
                    let isStreamingEnded = !state.isStreaming
                    let finalMarkdown = currentMarkdown
                    // Defer to next runloop to prevent "update multiple times per frame" error
                    DispatchQueue.main.async {
                        if isStreamingEnded {
                            // Streaming ended: snap to final text (no animation) to avoid cut-offs
                            markdownAnimationTask?.cancel()
                            displayedMarkdown = finalMarkdown
                            evaluateLoaderCleared(with: finalMarkdown)
                            loaderCleared = true
                            logStreamEnded()
                        }
                    }
                }
                .onChange(of: loaderCleared) {
                    // Defer to next runloop to prevent "update multiple times per frame" error
                    DispatchQueue.main.async {
                        if loaderCleared {
                            scrollToContent(using: scrollProxy)
                            let hasMetadata = (state.metadataTitle?.isEmpty == false) || (state.metadataShortDescription?.isEmpty == false)
                            if hasMetadata && !metadataVisible {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    metadataVisible = true
                                }
                            }
                        } else {
                            hasScrolledToContent = false
                        }
                    }
                }
            }
            .applyingIf(UIDevice.isIPad) { view in
                view.fullScreenCover(isPresented: $isImageFullscreenPresented) {
                    if previewImage != nil {
                        DiscoveryDetailImageFullscreenView(
                            discoveryId: state.discoverySummary?.id ?? 0,
                            imageURL: nil,
                            placeholderImage: UIImage(data: imageData ?? Data()),
                            onClose: { isImageFullscreenPresented = false }
                        )
                    }
                }
            }
            .applyingIf(!UIDevice.isIPad) { view in
                view.sheet(isPresented: $isImageFullscreenPresented) {
                    if previewImage != nil {
                        DiscoveryDetailImageFullscreenView(
                            discoveryId: state.discoverySummary?.id ?? 0,
                            imageURL: nil,
                            placeholderImage: UIImage(data: imageData ?? Data()),
                            onClose: { isImageFullscreenPresented = false }
                        )
                        .presentationDetents([.fraction(0.995)])
                        .presentationDragIndicator(.visible)
                    }
                }
            }
            .modifier(
                ShareSheetModifier(
                    shareSheetPayload: $shareSheetPayload,
                    shareSheetDetent: $shareSheetDetent
                )
            )
            .onChange(of: shareSheetPayload?.id) { _, id in
                if id == nil {
                    shareSheetDetent = .medium
                }
            }
        }
        }
    }

    private func resetStateForInitialRender() {
        shuffledMessages = DiscoveryStreamingStageView.loadingMessages.shuffled()
        currentMessageIndex = 0
        previousMessage = nil
        previousMessageOpacity = 0
        currentMessageOpacity = 1
        metadataVisible = (state.metadataTitle?.isEmpty == false) || (state.metadataShortDescription?.isEmpty == false)
        let initialNarrative = currentMarkdown
        displayedMarkdown = initialNarrative
        loaderCleared = loaderShouldBeCleared(for: initialNarrative)
        hasScrolledToContent = false
    }

    private func updateDisplayedMarkdown() {
        let newValue = currentMarkdown
        guard newValue != displayedMarkdown else {
            evaluateLoaderCleared(with: newValue)
            return
        }
        animateMarkdown(to: newValue)
    }

    private func animateMarkdown(to target: String) {
        markdownAnimationTask?.cancel()
        let current = displayedMarkdown

        // If the change is very small, just apply it instantly.
        if target.count <= current.count + 2 {
            displayedMarkdown = target
            evaluateLoaderCleared(with: target)
            return
        }

        let delta = target.dropFirst(current.count)
        let deltaCount = delta.count

        // Stream quickly in smooth chunks to avoid flicker and long waits.
        // Aim to reveal a typical sentence (< ~120 chars) in ~0.35–0.5s.
        let targetDuration: Double = 0.42
        let minDelay: Double = 0.016   // ~60 FPS lower bound
        let maxDelay: Double = 0.06
        let steps = max(3, min(12, (deltaCount + 23) / 24))
        let chunkSize = max(1, deltaCount / steps)
        let stepDelay = max(minDelay, min(maxDelay, targetDuration / Double(steps)))
        let delayNs = UInt64(stepDelay * 1_000_000_000)

        markdownAnimationTask = Task {
            var buffer = current
            var idx = delta.startIndex
            while idx < delta.endIndex {
                if Task.isCancelled { return }
                let nextIdx = delta.index(idx, offsetBy: chunkSize, limitedBy: delta.endIndex) ?? delta.endIndex
                buffer.append(contentsOf: delta[idx..<nextIdx])
                idx = nextIdx
                await MainActor.run {
                    displayedMarkdown = buffer
                    evaluateLoaderCleared(with: buffer)
                }
                if idx < delta.endIndex {
                    try? await Task.sleep(nanoseconds: delayNs)
                }
            }
        }
    }

    private func loaderShouldBeCleared(for text: String) -> Bool {
        // End loading as soon as actual streamed narrative content is visible,
        // or metadata is present. Do not wait for the stream to finish.
        if let title = state.metadataTitle, !title.isEmpty {
            return true
        }
        if let short = state.metadataShortDescription, !short.isEmpty {
            return true
        }
        let visibleLength = DiscoveryStreamFormatter.visibleLength(for: state.streamedText)
        if visibleLength > 0 {
            return true
        }
        return false
    }

    private func evaluateLoaderCleared(with text: String) {
        if loaderCleared {
            return
        }
        if loaderShouldBeCleared(for: text) {
            loaderCleared = true
        }
    }

    private func evaluateMetadataVisibility() {
        let hasMetadata = (state.metadataTitle?.isEmpty == false) || (state.metadataShortDescription?.isEmpty == false)
        if hasMetadata && !metadataVisible {
            if loaderCleared {
                withAnimation(.easeInOut(duration: 0.25)) {
                    metadataVisible = true
                }
            } else {
                // Wait to animate title/short until the loader clears so it matches the description reveal.
            }
        } else if !hasMetadata && metadataVisible && state.isStreaming {
            metadataVisible = false
        }
    }

    // Rotation handled by ShimmerTextView's onFinished callback.

    private func animationDelay(for count: Int) -> UInt64 {
        // Legacy per-character delay (kept for reference). Not used by the chunked animator.
        let characters = max(1, count)
        let baseDelay = min(0.02, max(0.002, 0.3 / Double(characters)))
        return UInt64(baseDelay * 1_000_000_000)
    }

    private func scrollToContent(using proxy: ScrollViewProxy, animated: Bool = true) {
        guard !hasScrolledToContent else { return }
        hasScrolledToContent = true
        let action = {
            proxy.scrollTo(ScrollTarget.markdown, anchor: .top)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.45)) {
                action()
            }
        } else {
            action()
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool = true) {
        hasScrolledToContent = true
        let action = {
            proxy.scrollTo(ScrollTarget.contentBottom, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.45)) {
                action()
            }
        } else {
            action()
        }
    }

    private func scrollToButton(using proxy: ScrollViewProxy, animated: Bool = true) {
        let action = {
            proxy.scrollTo(ScrollTarget.bottomAction, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.45)) {
                action()
            }
        } else {
            action()
        }
    }

    @ViewBuilder
    private func headerImageSection(size: CGSize, safeTop: CGFloat) -> some View {
        // Full-bleed image header with gradient/title overlay.
        let height = max(size.height * Layout.headerHeightFactor, Layout.minimumHeaderHeight)
        let width = max(size.width, Layout.minimumHeaderWidth)
        ZStack(alignment: .bottom) {
            if let image = previewImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height + safeTop)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [
                        Color(hex: "#20293A"),
                        Color(hex: "#141927")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: width, height: height + safeTop)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                            Text("Image preview unavailable")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
            }

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.clear, location: 0.0),
                    .init(color: palette.overlayMidtone, location: 0.7),
                    .init(color: palette.background, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: width, height: height + safeTop)
            .allowsHitTesting(false)


        }
        .frame(width: width, height: height + safeTop)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            isImageFullscreenPresented = true
        }
    }

    private func headerOverlayContent(width: CGFloat) -> some View {
        let availableWidth = max(width - (BrandSpacing.large * 2), 0)
        return DiscoveryStreamingLoaderView(
            palette: palette,
            shouldShowLoader: shouldShowLoader,
            currentMessage: currentLoadingMessage,
            previousMessage: previousMessage,
            currentMessageOpacity: currentMessageOpacity,
            previousMessageOpacity: previousMessageOpacity,
            metadataVisible: metadataVisible,
            state: state,
            capturedAt: capturedAt,
            availableWidth: availableWidth,
            onMessageFinished: { advanceMessage() },
            onShare: makeShareHandler(),
            onShowMap: makeMapHandler(),
            debugLog: { _ in }
        )
    }

    private func advanceMessage() {
        guard shouldShowLoader else {
            return
        }
        guard !shuffledMessages.isEmpty else {
            return
        }

        // Prepare crossfade: show previous message beneath and fade it out while the new fades in
        let old = currentLoadingMessage
        previousMessage = old
        previousMessageOpacity = 1
        currentMessageOpacity = 0

        // Compute next index and add a brief dwell before crossfading
        let nextIndex = (currentMessageIndex + 1) % shuffledMessages.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            currentMessageIndex = nextIndex
            withAnimation(.easeInOut(duration: 0.28)) {
                previousMessageOpacity = 0
                currentMessageOpacity = 1
            }
        }
    }

    private var markdownSection: some View {
        DiscoveryStreamingMarkdownView(
            palette: palette,
            displayedMarkdown: displayedMarkdown,
            shouldShowLoader: shouldShowLoader,
            isStreaming: state.isStreaming
        )
    }
    
    @ViewBuilder
    private var audioControlsSection: some View {
        // Show audio controls only when:
        // 1. Stream has finished
        // 2. Discovery summary is available (hydrated from server)
        // 3. Audio services are available
        // OTHERWISE: Reserve space to prevent layout jump
        Group {
            if !state.isStreaming,
               let discovery = state.discoverySummary,
               let audioServices {
                DiscoveryAudioControls(
                    discovery: discovery,
                    audioServices: audioServices,
                    scrollOffset: .constant(100), // Force "embedded" mode
                    makeCreditsViewModel: makeCreditsViewModel
                )
                .onAppear {
                    // Prefetch voiceover status for this discovery
                    audioServices.playbackController.prefetch(for: [discovery.id])
                }
            } else {
                // Reserve space matching DiscoveryAudioControls height (approx 50pt)
                Color.clear
                    .frame(height: 50)
            }
        }
        .padding(.bottom, BrandSpacing.small)
    }

    @ViewBuilder
    private func newDiscoveryButton(action: @escaping () -> Void) -> some View {
        BrandPrimaryButton(title: "Discover More") {
            action()
        }
        .frame(maxWidth: 320)
    }

    private static let loadingMessages: [String] = [
        "Identifying landmarks…",
        "Admiring nature…",
        "Looking for leprechauns…",
        "Analyzing architecture…",
        "Uncovering hidden history…",
        "Spotting local wildlife…",
        "Decoding ancient symbols…",
        "Consulting travel guides…",
        "Tracking bigfoot sightings…",
        "Translating squirrel chatter…"
    ]

    private enum ScrollTarget {
        static let markdown = "analysisMarkdown"
        static let bottomAction = "bottomAction"
        static let contentBottom = "contentBottom"
    }

    private func logStreamStarted() {
        guard debugLoggingEnabled, !hasLoggedStreamStart else { return }
        hasLoggedStreamStart = true
        print("[DiscoveryStreamingStageView] Stream started")
    }

    private func logStreamEnded() {
        guard debugLoggingEnabled, !hasLoggedStreamEnd else { return }
        hasLoggedStreamEnd = true
        let title = state.metadataTitle ?? "nil"
        let shortLen = state.metadataShortDescription?.count ?? 0
        print("[DiscoveryStreamingStageView] Stream ended metadataTitle=\"\(title)\" shortLen=\(shortLen)")
    }

    private func logMetadataVisibleIfNeeded() {
        guard debugLoggingEnabled, !hasLoggedMetadata else { return }
        guard let title = state.metadataTitle, !title.isEmpty else { return }
        let shortLen = state.metadataShortDescription?.count ?? 0
        hasLoggedMetadata = true
        print("[DiscoveryStreamingStageView] Metadata received title=\"\(title)\" shortLen=\(shortLen)")
    }
    private func makeShareHandler() -> (() -> Void)? {
        guard let discovery = state.discoverySummary, !state.isStreaming else { return nil }
        
        return {
            Task {
                let handler = DiscoveryDetailShareHandler()
                let context = DiscoveryDetailShareContext(
                    discovery: discovery,
                    placeholderImage: UIImage(data: imageData ?? Data()),
                    imageURL: nil // Using local image data for streaming stage usually
                )

                guard let payload = await handler.makeSharePayload(for: context) else { return }
                await MainActor.run {
                    shareSheetDetent = .medium
                    shareSheetPayload = payload
                }
            }
        }
    }

    private func makeMapHandler() -> (() -> Void)? {
        guard let discovery = state.discoverySummary, !state.isStreaming, discovery.location != nil else { return nil }
        
        return {
            DiscoveryDetailShareHandler().openLocationIfAvailable(from: discovery)
        }
    }
}

private struct ShareSheetModifier: ViewModifier {
    @Binding var shareSheetPayload: DiscoveryDetailSharePayload?
    @Binding var shareSheetDetent: PresentationDetent

    private var detents: Set<PresentationDetent> { [.medium, .large] }

    func body(content: Content) -> some View {
        content.sheet(item: $shareSheetPayload) { payload in
            DiscoveryShareSheet(activityItems: payload.items)
                .presentationDetents(detents, selection: $shareSheetDetent)
                .presentationDragIndicator(.visible)
        }
    }
}

/// Wrapper view that properly observes MiniPlayerPresenceStore to reactively show/hide the filler.
/// Using @ObservedObject ensures SwiftUI re-renders when the nested ObservableObject's @Published properties change.
private struct MiniPlayerFillerView: View {
    @ObservedObject var miniPlayerPresence: MiniPlayerPresenceStore
    let backgroundColor: Color

    private var isActive: Bool {
        miniPlayerPresence.isVisible && !miniPlayerPresence.isDismissed
    }

    var body: some View {
        backgroundColor
            .frame(height: isActive ? miniPlayerPresence.effectiveInset : 0)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.25), value: isActive)
    }
}
