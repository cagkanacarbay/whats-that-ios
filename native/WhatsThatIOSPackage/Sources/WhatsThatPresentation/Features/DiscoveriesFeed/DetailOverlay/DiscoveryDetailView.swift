import SwiftUI

import UIKit
import WhatsThatDomain
import WhatsThatShared
import MarkdownUI
#if canImport(Photos)
import Photos
#endif

struct DiscoveryDetailView: View {
    struct LayoutConfiguration {
        let cardSize: CGSize
        let heroHeight: CGFloat
        let heroImageHeight: CGFloat
        let heroVisibleHeight: CGFloat
        let heroBottomGlobalY: CGFloat
        let headerOffset: CGFloat
        let pullDownOffset: CGFloat
        let cornerRadius: CGFloat
        let containerWidth: CGFloat
        let safeAreaTopInset: CGFloat
        let contentOpacity: Double
        let backgroundOpacity: Double
        let heroOverlayOpacity: Double
        let scrollOverlayOpacity: Double
        let isChromeReady: Bool
        let isMarkdownReady: Bool
        let isScrollDisabled: Bool
        let isClosing: Bool
        let showTopControls: Bool
    }

    let discovery: DiscoverySummary
    let imageURL: URL?
    let placeholderImage: UIImage?
    let backgroundColor: Color
    let colorScheme: ColorScheme
    let layout: LayoutConfiguration
    let safeAreaInsets: EdgeInsets
    let overlayNamespace: Namespace.ID
    let onScrollViewContentOffsetChange: ((CGFloat) -> Void)?
    let onClose: () -> Void
    let isDeleting: Bool
    let onDelete: (() -> Void)?
    let onShowOptions: (() -> Void)?
    let onShowImage: (() -> Void)?
    let onOpenAudioGuide: (() -> Void)?
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    @Binding private var scrollOffset: CGFloat
    @State private var isOptionsPresented = false
    @State private var isSaving = false
    @State private var showSaveError = false
    @State private var shareSheetPayload: DiscoveryDetailSharePayload?
    @State private var shareSheetDetent: PresentationDetent = .medium

    init(
        discovery: DiscoverySummary,
        imageURL: URL?,
        placeholderImage: UIImage?,
        backgroundColor: Color,
        colorScheme: ColorScheme,
        layout: LayoutConfiguration,
        safeAreaInsets: EdgeInsets,
        voiceoverController: VoiceoverPlaybackController,
        overlayNamespace: Namespace.ID,
        scrollOffset: Binding<CGFloat>,
        onScrollViewContentOffsetChange: ((CGFloat) -> Void)? = nil,
        onClose: @escaping () -> Void,
        isDeleting: Bool,
        onDelete: (() -> Void)?,
        onShowOptions: (() -> Void)?,
        onShowImage: (() -> Void)? = nil,
        onOpenAudioGuide: (() -> Void)? = nil
    ) {
        self.discovery = discovery
        self.imageURL = imageURL
        self.placeholderImage = placeholderImage
        self.backgroundColor = backgroundColor
        self.colorScheme = colorScheme
        self.layout = layout
        self.safeAreaInsets = safeAreaInsets
        self.overlayNamespace = overlayNamespace
        self.onScrollViewContentOffsetChange = onScrollViewContentOffsetChange
        self.onClose = onClose
        self.isDeleting = isDeleting
        self.onDelete = onDelete
        self.onShowOptions = onShowOptions
        self.onShowImage = onShowImage
        self.onOpenAudioGuide = onOpenAudioGuide
        _voiceoverController = ObservedObject(initialValue: voiceoverController)
        _scrollOffset = scrollOffset
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DiscoveryHeroHeaderView(
                imageURL: imageURL,
                placeholderImage: placeholderImage,
                height: layout.heroHeight,
                pullDownOffset: layout.pullDownOffset,
                cornerRadius: layout.cornerRadius,
                width: layout.cardSize.width,
                namespace: nil,
                isGeometrySource: false,
                discoveryId: discovery.id
            )
            .offset(y: layout.headerOffset)

            DiscoveryDetailContentView(
                discovery: discovery,
                imageHeight: layout.heroImageHeight,
                headerOffset: layout.headerOffset,
                heroVisibleHeight: layout.heroVisibleHeight,
                heroBottomGlobalY: layout.heroBottomGlobalY,
                pullDownOffset: layout.pullDownOffset,
                backgroundColor: backgroundColor,
                backgroundOpacity: layout.backgroundOpacity,
                colorScheme: colorScheme,
                voiceoverController: voiceoverController,
                safeAreaInsets: safeAreaInsets,
                safeAreaTopInset: layout.safeAreaTopInset,
                containerWidth: layout.containerWidth,
                contentOpacity: layout.contentOpacity,
                isChromeReady: layout.isChromeReady,
                isMarkdownReady: layout.isMarkdownReady,
                isScrollDisabled: layout.isScrollDisabled,
                scrollOverlayOpacity: layout.scrollOverlayOpacity,
                overlayNamespace: overlayNamespace,
                isClosing: layout.isClosing,
                showTopControls: layout.showTopControls,
                onClose: onClose,
                onShowOptions: handleOptionsTapped,
                isOptionsEnabled: !isDeleting,
                onShowImage: onShowImage,
                onScrollViewContentOffsetChange: onScrollViewContentOffsetChange,
                scrollOffset: $scrollOffset,
                onShare: { presentShareSheet() },
                onShowMap: discovery.location != nil ? { openLocationIfAvailable() } : nil,
                onOpenAudioGuide: onOpenAudioGuide
            )
        }
        .frame(width: layout.cardSize.width, height: layout.cardSize.height)
        .background(backgroundColor.opacity(layout.backgroundOpacity))
            .compositingGroup()
            .clipShape(
                RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous),
                style: FillStyle(eoFill: false, antialiased: true)
            )
            .modifier(
                ShareSheetModifier(
                    shareSheetPayload: $shareSheetPayload,
                    shareSheetDetent: $shareSheetDetent
                )
            )
        .overlay {
            if isOptionsPresented {
                DiscoveryDetailOptionsSheet(
                    isPresented: $isOptionsPresented,
                    isDeleting: isDeleting,
                    isSaving: isSaving,
                    onSaveImage: handleSaveImage,
                    onDelete: handleDeleteSelection
                )
            }
        }
        .onChange(of: isDeleting) { _, newValue in
            if newValue {
                isOptionsPresented = false
            }
        }
        .onChange(of: shareSheetPayload?.id) { _, id in
            if id == nil {
                shareSheetDetent = .medium
            }
        }
    }
}



private extension DiscoveryDetailView {
    var overlayGeometryId: String {
        "discovery-detail-overlay-\(discovery.id)"
    }

    func handleOptionsTapped() {
        guard !isDeleting else { return }
        isOptionsPresented = true
        onShowOptions?()
    }

    func handleDeleteSelection() {
        guard !isDeleting else { return }
        isOptionsPresented = false
        onDelete?()
    }

    func handleSaveImage() {
        guard !isSaving else { return }
        isSaving = true
        
        Task {
            defer {
                Task { @MainActor in
                    isSaving = false
                }
            }
            
            #if canImport(Photos)
            // Check/request permission
            var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            if status == .notDetermined {
                status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            }
            
            guard status == .authorized || status == .limited else {
                await MainActor.run {
                    showSaveError = true
                }
                return
            }
            
            // Get image data from placeholder or download from URL
            let imageData: Data?
            if let placeholder = placeholderImage {
                imageData = placeholder.jpegData(compressionQuality: 0.95)
            } else if let url = imageURL {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    imageData = data
                } catch {
                    await MainActor.run {
                        showSaveError = true
                    }
                    return
                }
            } else {
                imageData = nil
            }
            
            guard let data = imageData, let image = UIImage(data: data) else {
                await MainActor.run {
                    showSaveError = true
                }
                return
            }
            
            // Save to Photos library
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                await MainActor.run {
                    isOptionsPresented = false
                }
            } catch {
                await MainActor.run {
                    showSaveError = true
                }
            }
            #else
            await MainActor.run {
                showSaveError = true
            }
            #endif
        }
    }

    func presentShareSheet() {
        Task {
            let handler = DiscoveryDetailShareHandler()
            let context = DiscoveryDetailShareContext(
                discovery: discovery,
                placeholderImage: placeholderImage,
                imageURL: imageURL
            )

            guard let payload = await handler.makeSharePayload(for: context) else { return }
            await MainActor.run {
                shareSheetDetent = .medium
                shareSheetPayload = payload
            }
        }
    }

    func openLocationIfAvailable() {
        DiscoveryDetailShareHandler().openLocationIfAvailable(from: discovery)
    }
}

private struct DiscoveryDetailContentView: View {
    let discovery: DiscoverySummary
    let imageHeight: CGFloat
    let headerOffset: CGFloat
    let heroVisibleHeight: CGFloat
    let heroBottomGlobalY: CGFloat
    let pullDownOffset: CGFloat
    let backgroundColor: Color
    let backgroundOpacity: Double
    let colorScheme: ColorScheme
    let safeAreaInsets: EdgeInsets
    let safeAreaTopInset: CGFloat
    let containerWidth: CGFloat
    let contentOpacity: Double
    let isChromeReady: Bool
    let isMarkdownReady: Bool
    let isScrollDisabled: Bool
    let scrollOverlayOpacity: Double
    let overlayNamespace: Namespace.ID
    let isClosing: Bool
    let showTopControls: Bool
    let onClose: (() -> Void)?
    let onShowOptions: (() -> Void)?
    let isOptionsEnabled: Bool
    let onShowImage: (() -> Void)?
    let onShare: (() -> Void)?
    let onShowMap: (() -> Void)?
    let onScrollViewContentOffsetChange: ((CGFloat) -> Void)?
    let onOpenAudioGuide: (() -> Void)?
    @Environment(\.audioServices) private var audioServices
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    // Player inset store is not required when using a bottom safeAreaInset.
    @Binding var scrollOffset: CGFloat
    @State private var baselineOffset: CGFloat?
    @State private var audioControlsScrollOffset: CGFloat = 0
    // Scrolling/dismiss gating has no need for persistent local state
    // no external measurement needed

    init(
        discovery: DiscoverySummary,
        imageHeight: CGFloat,
        headerOffset: CGFloat,
        heroVisibleHeight: CGFloat,
        heroBottomGlobalY: CGFloat,
        pullDownOffset: CGFloat,
        backgroundColor: Color,
        backgroundOpacity: Double,
        colorScheme: ColorScheme,
        voiceoverController: VoiceoverPlaybackController,
        safeAreaInsets: EdgeInsets,
        safeAreaTopInset: CGFloat,
        containerWidth: CGFloat,
        contentOpacity: Double,
        isChromeReady: Bool,
        isMarkdownReady: Bool,
        isScrollDisabled: Bool,
        scrollOverlayOpacity: Double,
        overlayNamespace: Namespace.ID,
        isClosing: Bool,
        showTopControls: Bool,
        onClose: (() -> Void)? = nil,
        onShowOptions: (() -> Void)? = nil,
        isOptionsEnabled: Bool = true,
        onShowImage: (() -> Void)? = nil,
        onScrollViewContentOffsetChange: ((CGFloat) -> Void)? = nil,
        scrollOffset: Binding<CGFloat>,
        onShare: (() -> Void)? = nil,
        onShowMap: (() -> Void)? = nil,
        onOpenAudioGuide: (() -> Void)? = nil
    ) {
        self.discovery = discovery
        self.imageHeight = imageHeight
        self.headerOffset = headerOffset
        self.heroVisibleHeight = heroVisibleHeight
        self.heroBottomGlobalY = heroBottomGlobalY
        self.pullDownOffset = pullDownOffset
        self.backgroundColor = backgroundColor
        self.backgroundOpacity = backgroundOpacity
        self.colorScheme = colorScheme
        self.safeAreaInsets = safeAreaInsets
        self.safeAreaTopInset = safeAreaTopInset
        self.containerWidth = containerWidth
        self.contentOpacity = contentOpacity
        self.isChromeReady = isChromeReady
        self.isMarkdownReady = isMarkdownReady
        self.isScrollDisabled = isScrollDisabled
        self.scrollOverlayOpacity = scrollOverlayOpacity
        self.overlayNamespace = overlayNamespace
        self.isClosing = isClosing
        self.showTopControls = showTopControls
        self.onClose = onClose
        self.onShowOptions = onShowOptions
        self.isOptionsEnabled = isOptionsEnabled
        self.onShowImage = onShowImage
        self.onScrollViewContentOffsetChange = onScrollViewContentOffsetChange
        self.onShare = onShare
        self.onShowMap = onShowMap
        self.onOpenAudioGuide = onOpenAudioGuide
        _voiceoverController = ObservedObject(initialValue: voiceoverController)
        _scrollOffset = scrollOffset
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    private var headerLayoutHeight: CGFloat {
        imageHeight + safeAreaTopInset + pullDownOffset
    }

    private var headerOverlayHeight: CGFloat { imageHeight + safeAreaTopInset }

    // Overlay Y offset derived analytically from hero geometry:
    // offset = headerOffset - pullDownOffset, keeping the overlay pinned.
    private var overlayYOffset: CGFloat { headerOffset - pullDownOffset }

    var body: some View {
        ScrollView(showsIndicators: false) {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: HeroScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named("hero-scroll")).minY
                    )
            }
            .frame(height: 1)

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Color.clear
                        .frame(height: headerLayoutHeight)
                        .clipped()

                    DiscoveryHeaderOverlayView(
                        discovery: discovery,
                        palette: palette,
                        maxDescriptionLines: 3,
                        gradientFalloff: 0.55,
                        contentWidth: containerWidth,
                        onShare: onShare,
                        onShowMap: onShowMap,
                        isClosing: isClosing,
                        showTopControls: showTopControls,
                        topControlsSafeAreaInsets: safeAreaInsets,
                        onClose: onClose,
                        onShowOptions: onShowOptions,
                        isOptionsEnabled: isOptionsEnabled,
                        onCreateAudioGuide: onOpenAudioGuide
                    )
                    .frame(height: heroVisibleHeight)
                    .offset(y: overlayYOffset)
                    // Prevent any position-based animations: only fade
                    .animation(nil, value: overlayYOffset)
                    .animation(nil, value: heroVisibleHeight)
                    .transaction { $0.animation = nil }
                    .opacity(scrollOverlayOpacity)
                    .allowsHitTesting(isChromeReady)
                    .overlay(alignment: .top) {
                        if onShowImage != nil, isChromeReady, !isClosing {
                            // Simple full-size tap area that sits *below* the interactive controls
                            // because we are in an overlay. But wait, this overlay is on top of the header.
                            // The header controls (back button, etc.) are inside DiscoveryHeaderOverlayView.
                            // If this tap overlay covers them, they won't work.
                            // However, SwiftUI's ZStack order matters.
                            // DiscoveryHeaderOverlayView is strictly visually composed.
                            // We need to ensure this tap gesture doesn't block the controls.
                            // Using allowHitTesting(false) on the spacer area for controls is one way.
                            
                            heroTapOverlay
                        }
                    }
                }

                if isChromeReady && !isClosing {

                    VStack(alignment: .leading, spacing: 0) {
                        
                        // Audio Controls replacing the old voiceover button
                        if let audioServices {
                            DiscoveryAudioControls(
                                discovery: discovery,
                                audioServices: audioServices,
                                scrollOffset: $audioControlsScrollOffset
                            )
                            .padding(.bottom, BrandSpacing.medium)
                            .animation(.easeOut(duration: 0.15), value: audioControlsScrollOffset)
                        }
                        


                        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
                            // Title is already shown in the image overlay; avoid repeating here.
                            detailDescriptionView(isReady: isMarkdownReady)
                        }
                    }
                    .padding(.top, -6)
                    .padding(.horizontal, BrandSpacing.large)
                    .padding(
                        .bottom,
                        // Keep a small base gap and cap the extra inset so large insets (e.g. player) don't balloon spacing.
                        BrandSpacing.small + min(safeAreaInsets.bottom, BrandSpacing.medium)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(backgroundColor.opacity(backgroundOpacity))
                    .opacity(contentOpacity)
                }
            }
            // Attach UIKit offset observer inside the scroll content so the
            // representable sits within the UIScrollView's view hierarchy.
            .background(
                ScrollViewContentOffsetObserver { offset in
                    // Defer state update to avoid "Modifying state during view update" warning
                    DispatchQueue.main.async {
                        audioControlsScrollOffset = offset
                    }
                    updateGatedDistanceFromTop(distance: offset)
                }
                .allowsHitTesting(false)
            )
        }
        .id(discovery.id)
        .coordinateSpace(name: "hero-scroll")
        .miniPlayerScrollInset()
        .frame(width: containerWidth)
        .contentMargins(.all, 0, for: .scrollContent)
        .conditionalScrollDisabled(isScrollDisabled)
        // Track scroll position via geometry to compute a stable
        // distance-from-top value for gesture gating.
        .onPreferenceChange(HeroScrollOffsetPreferenceKey.self) { value in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                if baselineOffset == nil {
                    baselineOffset = value
                }
                let adjusted = value - (baselineOffset ?? 0)
                scrollOffset = adjusted
                // Positive distance from top (0 at top, grows as you scroll down)
                let distanceFromTop = max(-adjusted, 0)
                updateGatedDistanceFromTop(distance: distanceFromTop)
            }
        }
        .onAppear {
            voiceoverController.prefetch(for: [discovery.id])
        }
        .onChange(of: discovery.id) { _, _ in
            scrollOffset = 0
            baselineOffset = nil
        }
    }

    // Determine if the voiceover button should be visible.
    // Show only when:
    // - asset is available, or
    // - an error occurred and a retry makes sense, or
    // - playback previously failed for this discovery (retry)

    @ViewBuilder
    private func detailDescriptionView(isReady: Bool) -> some View {
        if let description = discovery.detailDescription, !description.isEmpty {
            if isReady {
                #if canImport(MarkdownUI)
                Markdown(description)
                    .markdownTheme(BrandMarkdownThemeFactory.discoveryDetailTheme(for: palette))
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
private extension DiscoveryDetailContentView {
    var overlayGeometryId: String {
        "discovery-detail-overlay-\(discovery.id)"
    }

    @ViewBuilder
    private var heroTapOverlay: some View {
        GeometryReader { proxy in
            let topPadding = min(topTapExclusionHeight, proxy.size.height)
            let bottomPadding = min(bottomExclusionHeight, max(proxy.size.height - topPadding, 0))
            let interactiveHeight = max(proxy.size.height - topPadding - bottomPadding, 0)

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: topPadding)
                    .allowsHitTesting(false)

                Color.clear
                    .frame(height: interactiveHeight)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard let onShowImage,
                                      isTap(translation: value.translation) else { return }
                                onShowImage()
                            }
                    )

                Spacer()
                    .frame(height: bottomPadding)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: heroVisibleHeight)
        .allowsHitTesting(true)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("View image full screen")
    }

    private func isTap(translation: CGSize) -> Bool {
        abs(translation.width) < 6 && abs(translation.height) < 6
    }

    private var topTapExclusionHeight: CGFloat {
        var height = safeAreaTopInset + 12
        if showTopControls {
            height += 48 + BrandSpacing.small
        }
        if hasActionRow {
            height += 48 + BrandSpacing.small
        }
        height += BrandSpacing.medium
        return height
    }

    private var bottomExclusionHeight: CGFloat {
        BrandSpacing.large
    }

    private var hasActionRow: Bool {
        onShare != nil || onShowMap != nil
    }

    func updateGatedDistanceFromTop(distance: CGFloat) {
        onScrollViewContentOffsetChange?(distance)
    }

    func resolvedTapExclusions(
        for interactiveRects: [CGRect],
        topPadding: CGFloat,
        interactiveHeight: CGFloat,
        containerWidth: CGFloat
    ) -> [CGRect] {
        guard interactiveHeight > 0 else { return [] }
        let expansion: CGFloat = 12
        let interactiveArea = CGRect(
            x: 0,
            y: topPadding,
            width: containerWidth,
            height: interactiveHeight
        )

        return interactiveRects.compactMap { rect in
            let intersection = rect.intersection(interactiveArea)
            guard intersection.width > 0, intersection.height > 0 else { return nil }

            let localRect = CGRect(
                x: intersection.origin.x,
                y: intersection.origin.y - topPadding,
                width: intersection.width,
                height: intersection.height
            )

            let minX = max(localRect.minX - expansion, 0)
            let maxX = min(localRect.maxX + expansion, containerWidth)
            let minY = max(localRect.minY - expansion, 0)
            let maxY = min(localRect.maxY + expansion, interactiveHeight)

            let width = max(0, maxX - minX)
            let height = max(0, maxY - minY)
            guard width > 0, height > 0 else { return nil }

            return CGRect(x: minX, y: minY, width: width, height: height)
        }
    }
}

private struct HeroTapHitShape: Shape {
    var exclusions: [CGRect]

    var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        exclusions.forEach { exclusion in
            path.addRect(exclusion)
        }
        return path
    }
}

// MARK: - Targeted type boundary for share sheet

private struct ShareSheetModifier: ViewModifier {
    @Binding var shareSheetPayload: DiscoveryDetailSharePayload?
    @Binding var shareSheetDetent: PresentationDetent

    // Explicitly-typed detents to avoid inference churn
    private var detents: Set<PresentationDetent> { [.medium, .large] }

    func body(content: Content) -> some View {
        content.sheet(item: $shareSheetPayload) { payload in
            DiscoveryShareSheet(activityItems: payload.items)
                .presentationDetents(detents, selection: $shareSheetDetent)
                .presentationDragIndicator(.visible)
        }
    }
}


