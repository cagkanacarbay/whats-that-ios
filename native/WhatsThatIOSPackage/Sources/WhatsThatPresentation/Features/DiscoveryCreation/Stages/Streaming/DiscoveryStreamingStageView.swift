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

    init(
        viewModel: DiscoveryCreationFlowViewModel,
        imageData: Data?,
        capturedAt: Date?,
        onCancel: @escaping () -> Void
    ) {
        self._viewModel = ObservedObject(initialValue: viewModel)
        self.imageData = imageData
        self.capturedAt = capturedAt
        self.onCancel = onCancel
    }

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var playerInsetStore: VoiceoverPlayerInsetStore
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

                        markdownSection
                            .id(ScrollTarget.markdown)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Image/header drawn inside content overlay, so the whole page scrolls.
                .background(palette.background.ignoresSafeArea())
                .onAppear {
                    resetStateForInitialRender()
                    if loaderCleared {
                        DispatchQueue.main.async {
                            scrollToContent(using: scrollProxy, animated: false)
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
                    updateDisplayedMarkdown()
                }
                .onChange(of: currentMessageIndex) { newIndex in
                    let currentOpacityFormatted = String(format: "%.2f", currentMessageOpacity)
                    let previousOpacityFormatted = String(format: "%.2f", previousMessageOpacity)
                    debugLog(
                        "loaderMessageIndex -> \(newIndex) message=\"\(currentLoadingMessage)\" prev=\"\(previousMessage ?? "nil")\" currentOpacity=\(currentOpacityFormatted) previousOpacity=\(previousOpacityFormatted)"
                    )
                }
                .onChange(of: currentMessageOpacity) { newValue in
                    let formatted = String(format: "%.2f", newValue)
                    debugLog("currentMessageOpacity changed -> \(formatted) message=\"\(currentLoadingMessage)\"")
                }
                .onChange(of: previousMessageOpacity) { newValue in
                    let formatted = String(format: "%.2f", newValue)
                    debugLog("previousMessageOpacity changed -> \(formatted) previous=\"\(previousMessage ?? "nil")\"")
                }
                .onChange(of: state.streamedText) {
                    // Throttle noisy updates: only consider stream text for clearing
                    // the loader if we still have no metadata and the loader is visible.
                    guard !loaderCleared,
                          (state.metadataTitle?.isEmpty ?? true) && (state.metadataShortDescription?.isEmpty ?? true)
                    else { return }
                    evaluateLoaderCleared(with: currentMarkdown)
                }
                .onChange(of: state.metadataTitle) {
                    evaluateMetadataVisibility()
                    evaluateLoaderCleared(with: displayedMarkdown)
                }
                .onChange(of: state.metadataShortDescription) {
                    evaluateMetadataVisibility()
                    evaluateLoaderCleared(with: displayedMarkdown)
                }
                .onChange(of: state.isStreaming) {
                    if !state.isStreaming {
                        // Streaming ended: snap to final text (no animation) to avoid cut-offs
                        markdownAnimationTask?.cancel()
                        let final = currentMarkdown
                        displayedMarkdown = final
                        evaluateLoaderCleared(with: final)
                        loaderCleared = true
                    }
                }
                .onChange(of: loaderCleared) {
                    debugLog("loaderCleared changed -> \(loaderCleared)")
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
        debugLog("resetState loaderCleared=\(loaderCleared) initialMarkdownLength=\(initialNarrative.count) metadataTitle=\(state.metadataTitle ?? "nil")")
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
            debugLog("loaderShouldBeCleared -> true (metadataTitle=\"\(title)\")")
            return true
        }
        if let short = state.metadataShortDescription, !short.isEmpty {
            debugLog("loaderShouldBeCleared -> true (metadataShortDescription length=\(short.count))")
            return true
        }
        let visibleLength = DiscoveryStreamFormatter.visibleLength(for: state.streamedText)
        if visibleLength > 0 {
            debugLog("loaderShouldBeCleared -> true (visibleStreamLength=\(visibleLength))")
            return true
        }
        debugLog("loaderShouldBeCleared -> false (textLength=\(text.count))")
        return false
    }

    private func evaluateLoaderCleared(with text: String) {
        if loaderCleared {
            return
        }
        if loaderShouldBeCleared(for: text) {
            loaderCleared = true
            debugLog("loaderCleared = true (textLength=\(text.count), isStreaming=\(state.isStreaming), title=\(state.metadataTitle ?? "nil"))")
        }
    }

    private func evaluateMetadataVisibility() {
        let hasMetadata = (state.metadataTitle?.isEmpty == false) || (state.metadataShortDescription?.isEmpty == false)
        if hasMetadata && !metadataVisible {
            if loaderCleared {
                withAnimation(.easeInOut(duration: 0.25)) {
                    metadataVisible = true
                }
                debugLog("metadataVisible = true (title=\(state.metadataTitle ?? "nil"), shortLen=\(state.metadataShortDescription?.count ?? 0))")
            } else {
                // Wait to animate title/short until the loader clears so it matches the description reveal.
            }
        } else if !hasMetadata && metadataVisible && state.isStreaming {
            metadataVisible = false
            debugLog("metadataVisible = false (awaiting metadata)")
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
            debugLog: { debugLog($0) }
        )
    }

    private func advanceMessage() {
        guard shouldShowLoader else {
            debugLog("advanceMessage skipped (loader already cleared)")
            return
        }
        guard !shuffledMessages.isEmpty else {
            debugLog("advanceMessage skipped (no shuffled messages)")
            return
        }

        // Prepare crossfade: show previous message beneath and fade it out while the new fades in
        let old = currentLoadingMessage
        previousMessage = old
        previousMessageOpacity = 1
        currentMessageOpacity = 0
        debugLog("advanceMessage preparing crossfade from \"\(old)\" (index=\(currentMessageIndex))")

        // Compute next index and add a brief dwell before crossfading
        let nextIndex = (currentMessageIndex + 1) % shuffledMessages.count
        let upcomingMessage = shuffledMessages[nextIndex]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            debugLog("advanceMessage switching to index \(nextIndex) message=\"\(upcomingMessage)\"")
            currentMessageIndex = nextIndex
            withAnimation(.easeInOut(duration: 0.28)) {
                previousMessageOpacity = 0
                currentMessageOpacity = 1
            }
            let currentOpacityFormatted = String(format: "%.2f", currentMessageOpacity)
            let previousOpacityFormatted = String(format: "%.2f", previousMessageOpacity)
            debugLog(
                "advanceMessage crossfade applied currentOpacity=\(currentOpacityFormatted) previousOpacity=\(previousOpacityFormatted) loaderCleared=\(loaderCleared)"
            )
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

    private static let streamRevealThreshold: Int = 12
    private static let streamContentThreshold: Int = 40

    private enum ScrollTarget {
        static let markdown = "analysisMarkdown"
    }

    private func debugLog(_ message: String) {
        guard debugLoggingEnabled else { return }
        print("[DiscoveryStreamingStageView] \(message)")
    }
}
