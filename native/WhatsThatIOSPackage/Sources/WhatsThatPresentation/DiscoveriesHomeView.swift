#if canImport(UIKit)
import SwiftUI
import WhatsThatDomain
import WhatsThatShared
import UIKit
import MapKit
#if canImport(MarkdownUI)
import MarkdownUI
#endif

struct DiscoveriesHomeView: View {
    private let feedUseCase: DiscoveryFeedUseCase
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    @Binding private var pendingDiscoveryId: Int64?
    private let onSignOut: () -> Void
    private let onSettings: (() -> Void)?

    @StateObject private var viewModel: DiscoveryFeedViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollOffset: CGFloat = 0
    @State private var heroContext: DiscoveryHeroContext?
    @State private var heroProgress: CGFloat = 0
    @State private var heroContentOpacity: Double = 0
    @State private var heroIsClosing = false
    @State private var hiddenDiscovery: HiddenDiscovery?
    @State private var safeAreaBottomInset: CGFloat = 0

    private let headerHeight: CGFloat = 110
    private let collapseDistance: CGFloat = 110
    private let gridSpacing: CGFloat = 1
    private let gridHorizontalPadding: CGFloat = 1
    private let gridBottomPadding: CGFloat = 16

    init(
        feedUseCase: DiscoveryFeedUseCase,
        voiceoverController: VoiceoverPlaybackController,
        pendingDiscoveryId: Binding<Int64?>,
        onSignOut: @escaping () -> Void,
        onSettings: (() -> Void)? = nil
    ) {
        self.feedUseCase = feedUseCase
        self._voiceoverController = ObservedObject(initialValue: voiceoverController)
        self._pendingDiscoveryId = pendingDiscoveryId
        self.onSignOut = onSignOut
        self.onSettings = onSettings
        _viewModel = StateObject(wrappedValue: DiscoveryFeedViewModel(feedUseCase: feedUseCase))
    }

    var body: some View {
        GeometryReader { proxy in
            let safeBottom = proxy.safeAreaInsets.bottom

            let _ = proxy.size // retain to keep dependency updates
            let gridAvailableWidth = proxy.size.width == 0 ? UIScreen.main.bounds.width : proxy.size.width
            let contentWidth = max(gridAvailableWidth - (gridHorizontalPadding * 2), 0)

            ZStack(alignment: .top) {
                backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    GeometryReader { scrollProxy in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: scrollProxy.frame(in: .named("discoveriesScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    VStack(spacing: 0) {
                        Color.clear.frame(height: headerHeight)

                        DiscoveriesGrid(
                            viewModel: viewModel,
                            availableWidth: contentWidth,
                            cardSpacing: gridSpacing,
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
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
                .onChange(of: viewModel.discoveries) { _ in
                    presentPendingDiscoveryIfNeeded()
                }
                .onChange(of: pendingDiscoveryId) { _ in
                    presentPendingDiscoveryIfNeeded()
                }

                header(opacity: headerOpacity)

                if let context = heroContext {
                    DiscoveryHeroOverlay(
                        context: context,
                        progress: heroProgress,
                        contentOpacity: heroContentOpacity,
                        isClosing: heroIsClosing,
                        backgroundColor: backgroundColor,
                        colorScheme: colorScheme,
                        voiceoverController: voiceoverController,
                        onClose: handleDetailDismissal,
                        onShare: makeShareAction(for: context.discovery),
                        onShowOptions: nil
                    )
                    .transition(.identity)
                    .zIndex(5)
                }
            }
            .onAppear {
                updateSafeAreaBottomInsetIfNeeded(safeBottom)
            }
            .onChange(of: safeBottom) { newValue in
                updateSafeAreaBottomInsetIfNeeded(newValue)
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
        let snapshot = cachedImage ?? captureSnapshot(of: resolvedFrame)
        if cachedImage == nil, let snapshot {
            DiscoveryHeroImageCache.shared.store(snapshot, for: discovery.id)
        }

        hiddenDiscovery = HiddenDiscovery(id: discovery.id, sessionId: sessionId)
        heroContext = DiscoveryHeroContext(
            sessionId: sessionId,
            discovery: discovery,
            imageURL: resolvedImageURL,
            startFrame: resolvedFrame,
            placeholderImage: snapshot
        )
        heroProgress = 0
        heroContentOpacity = 0
        heroIsClosing = false
        voiceoverController.ensureMetadata(for: discovery)
        voiceoverController.isDetailOverlayActive = true

        withAnimation(.timingCurve(0.33, 1.0, 0.68, 1.0, duration: 0.5)) {
            heroProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard heroContext?.sessionId == sessionId, !heroIsClosing else { return }
            withAnimation(.linear(duration: 0)) {
                heroProgress = 1
            }
            withAnimation(.easeIn(duration: 0.12)) {
                heroContentOpacity = 1
            }
        }
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

        pendingDiscoveryId = nil
        handleDiscoverySelection(
            discovery: discovery,
            imageURL: imageURL(for: discovery),
            startFrame: .zero
        )
    }

    private func handleDetailDismissal() {
        guard let context = heroContext else { return }

        heroIsClosing = true

        withAnimation(.linear(duration: 0.05)) {
            heroContentOpacity = 0
        }

        withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.45)) {
            heroProgress = 0
        }

        let closingSessionId = context.sessionId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            if heroContext?.sessionId == closingSessionId {
                heroContext = nil
                heroIsClosing = false
                heroProgress = 0
                heroContentOpacity = 0
            } else if heroContext == nil {
                heroIsClosing = false
                heroProgress = 0
                heroContentOpacity = 0
            }

            withAnimation(.linear(duration: 0)) {
                heroProgress = 0
            }

            if hiddenDiscovery?.sessionId == closingSessionId {
                hiddenDiscovery = nil
            }
            voiceoverController.isDetailOverlayActive = false
        }
    }

    private func makeShareAction(for discovery: DiscoverySummary) -> (() -> Void)? {
        guard let shareURL = shareURL(for: discovery) else { return nil }

        return {
            presentShareSheet(for: discovery, url: shareURL)
        }
    }

    private func shareURL(for discovery: DiscoverySummary) -> URL? {
        if let token = discovery.shareToken {
            return URL(string: "https://whats-that.app/\(token.uuidString)")
        }

        if let path = discovery.imagePath {
            return URL(string: path)
        }

        return nil
    }

    private func presentShareSheet(for discovery: DiscoverySummary, url: URL) {
        let message = [
            discovery.title,
            discovery.shortDescription ?? discovery.highlight
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")

        let items: [Any] = message.isEmpty ? [url] : [message, url]
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)

        guard let root = keyWindowRootViewController() else { return }
        root.present(controller, animated: true)
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }

    private func keyWindowRootViewController() -> UIViewController? {
        keyWindow()?.rootViewController
    }

    private func captureSnapshot(of frame: CGRect) -> UIImage? {
        guard let window = keyWindow() else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(bounds: frame, format: format)
        return renderer.image { context in
            context.cgContext.translateBy(x: -frame.origin.x, y: -frame.origin.y)
            window.layer.render(in: context.cgContext)
    }
}

    private func updateSafeAreaBottomInsetIfNeeded(_ value: CGFloat) {
        if abs(value - safeAreaBottomInset) > 0.5 {
            safeAreaBottomInset = value
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

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }

    private var headerOpacity: Double {
        let offset = max(0, -scrollOffset)
        let progress = min(offset / collapseDistance, 1)
        return 1 - Double(progress)
    }

    @ViewBuilder
    private func header(opacity: Double) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("My Discoveries")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(headerTitleColor)
                    .accessibilityAddTraits(.isHeader)
                Spacer()

                if let onSettings {
                    Menu {
                        Button("Sign out", role: .destructive) {
                            onSignOut()
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(headerTitleColor)
                            .padding(10)
                            .background(headerIconBackground)
                            .clipShape(Circle())
                            .accessibilityLabel("Settings")
                    } primaryAction: {
                        onSettings()
                    }
                } else {
                    Menu {
                        Button("Sign out", role: .destructive) {
                            onSignOut()
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(headerTitleColor)
                            .padding(10)
                            .background(headerIconBackground)
                            .clipShape(Circle())
                            .accessibilityLabel("Options")
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.top, BrandSpacing.large)

            Divider()
                .background(dividerColor)
                .padding(.horizontal, BrandSpacing.large)
        }
        .frame(height: headerHeight)
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
        .opacity(opacity)
    }

    private var headerTitleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var headerIconBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : BrandColors.Light.border
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : BrandColors.Light.border
    }
}


private struct DiscoveryCardSkeleton: View {
    let width: CGFloat
    let height: CGFloat
    @State private var animate = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: width, height: height)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.gray.opacity(0.1),
                                    Color.gray.opacity(0.3),
                                    Color.gray.opacity(0.1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .mask {
                            Rectangle()
                                .fill(Color.white.opacity(animate ? 1 : 0))
                                .blur(radius: 40)
                                .offset(x: animate ? width : -width)
                        }
                        .animation(
                            .easeInOut(duration: 1.2)
                                .repeatForever(autoreverses: false),
                            value: animate
                        )
                }
                .onAppear {
                    animate = true
                }

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: width * 0.7, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: width * 0.5, height: 12)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.02),
                        Color.black.opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

private struct DiscoveriesErrorView: View {
    let message: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.orange)

            Text("We couldn’t refresh your discoveries.")
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            BrandPrimaryButton(title: "Try again", action: action)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(BrandSpacing.large)
    }
}

private struct EmptyDiscoveriesView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)

            Text("Start making discoveries")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(titleColor)

            Text("Snap a photo or upload from your library to unlock stories about the world around you.")
                .font(.system(size: 16, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(bodyColor)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(.horizontal, BrandSpacing.large)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : BrandColors.Light.bodyText
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

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
private struct DiscoveryCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int64: CGRect] = [:]

    static func reduce(value: inout [Int64: CGRect], nextValue: () -> [Int64: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct DiscoveriesGrid: View {
    @ObservedObject var viewModel: DiscoveryFeedViewModel
    let availableWidth: CGFloat
    let cardSpacing: CGFloat
    let hiddenDiscovery: HiddenDiscovery?
    let onLoadMore: (DiscoverySummary) async -> Void
    let onSelect: (DiscoverySummary, URL?, CGRect) -> Void

    @State private var cardFrames: [Int64: CGRect] = [:]

    private var gridColumns: [GridItem] {
        [
            GridItem(.fixed(cardWidth), spacing: cardSpacing, alignment: .top),
            GridItem(.fixed(cardWidth), spacing: cardSpacing, alignment: .top)
        ]
    }

    private var cardWidth: CGFloat {
        let totalSpacing = cardSpacing
        return max((availableWidth - totalSpacing) / 2, 120)
    }

    private var cardHeight: CGFloat {
        cardWidth * 1.2
    }

    var body: some View {
        switch viewModel.loadState {
        case .idle where viewModel.discoveries.isEmpty:
            if viewModel.isRefreshing {
                skeletonGrid
            } else {
                EmptyDiscoveriesView()
            }
        case .loading:
            skeletonGrid
        case .failed(let message):
            DiscoveriesErrorView(
                message: message,
                action: {
                    Task { await viewModel.reload() }
                }
            )
        case .loaded, .idle:
            if viewModel.discoveries.isEmpty {
                EmptyDiscoveriesView()
            } else {
                gridContent
            }
        }
    }

    private var skeletonGrid: some View {
        let placeholderItems = Array(repeating: UUID(), count: 8)
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: cardSpacing) {
            ForEach(placeholderItems, id: \.self) { _ in
                DiscoveryCardSkeleton(width: cardWidth, height: cardHeight)
            }
        }
        .frame(width: availableWidth, alignment: .leading)
    }

    private var gridContent: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: cardSpacing) {
            ForEach(viewModel.discoveries) { discovery in
                DiscoveryCard(
                    discovery: discovery,
                    width: cardWidth,
                    height: cardHeight,
                    isHidden: hiddenDiscovery?.id == discovery.id,
                    onSelect: { selectedDiscovery, imageURL in
                        let frame = cardFrames[selectedDiscovery.id] ?? .zero
                        onSelect(selectedDiscovery, imageURL, frame)
                    }
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: DiscoveryCardFramePreferenceKey.self,
                            value: [discovery.id: proxy.frame(in: .global)]
                        )
                    }
                )
                .onAppear {
                    Task { await onLoadMore(discovery) }
                }
            }
        }
        .frame(width: availableWidth, alignment: .leading)
        .onPreferenceChange(DiscoveryCardFramePreferenceKey.self) { value in
            cardFrames = value
        }
    }
}

private struct DiscoveryCard: View {
    let discovery: DiscoverySummary
    let width: CGFloat
    let height: CGFloat
    let isHidden: Bool
    let onSelect: (DiscoverySummary, URL?) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            onSelect(discovery, imageURL)
        } label: {
            ZStack(alignment: .bottom) {
                DiscoveryCardImage(
                    discoveryId: discovery.id,
                    url: imageURL,
                    width: width,
                    height: height
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(borderColor, lineWidth: 0.3)
                }

                VStack(spacing: 4) {
                    Text(discovery.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .shadow(color: Color.black.opacity(0.6), radius: 3, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0),
                            Color.black.opacity(0.25),
                            Color.black.opacity(0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .opacity(isHidden ? 0 : 1)
    }

    private var imageURL: URL? {
        guard let path = discovery.imagePath else { return nil }
        return URL(string: path)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : BrandColors.Light.border
    }
}

private struct DiscoveryCardImage: View {
    let discoveryId: Int64
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    @State private var didFail = false
    @State private var cached = false

    var body: some View {
        ZStack {
            placeholder

            if let url, !didFail {
                AsyncImage(url: url, transaction: Transaction(animation: .none)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .onAppear {
                                cacheIfNeeded(image: image)
                            }
                    case .failure:
                        Color.clear.onAppear { didFail = true }
                    case .empty:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .clipped()
    }

    private func cacheIfNeeded(image: Image) {
        guard !cached else { return }
        cached = true

        let rendered = image
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()

        let renderer = ImageRenderer(content: rendered)
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        renderer.scale = UIScreen.main.scale

        if let snapshot = renderer.uiImage {
            DiscoveryHeroImageCache.shared.store(snapshot, for: discoveryId)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#20293A"),
                    Color(hex: "#141927")
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .opacity(0.25)
        }
    }
}
private struct DiscoveryHeroContext: Identifiable {
    let sessionId: UUID
    let discovery: DiscoverySummary
    let imageURL: URL?
    let startFrame: CGRect
    let placeholderImage: UIImage?

    var id: UUID { sessionId }
}

private struct HiddenDiscovery {
    let id: Int64
    let sessionId: UUID
}

private final class DiscoveryHeroImageCache {
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

private struct DiscoveryHeroOverlay: View {
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    let context: DiscoveryHeroContext
    let progress: CGFloat
    let contentOpacity: Double
    let isClosing: Bool
    let backgroundColor: Color
    let colorScheme: ColorScheme
    let onClose: () -> Void
    let onShare: (() -> Void)?
    let onShowOptions: (() -> Void)?
    @State private var scrollOffset: CGFloat = 0

    init(
        context: DiscoveryHeroContext,
        progress: CGFloat,
        contentOpacity: Double,
        isClosing: Bool,
        backgroundColor: Color,
        colorScheme: ColorScheme,
        voiceoverController: VoiceoverPlaybackController,
        onClose: @escaping () -> Void,
        onShare: (() -> Void)?,
        onShowOptions: (() -> Void)?
    ) {
        self.context = context
        self.progress = progress
        self.contentOpacity = contentOpacity
        self.isClosing = isClosing
        self.backgroundColor = backgroundColor
        self.colorScheme = colorScheme
        self.onClose = onClose
        self.onShare = onShare
        self.onShowOptions = onShowOptions
        _voiceoverController = ObservedObject(initialValue: voiceoverController)
    }

    var body: some View {
        GeometryReader { proxy in
            let containerFrame = proxy.frame(in: .global)
            let screenBounds = UIScreen.main.bounds
            let rawWidth = proxy.size.width == 0 ? screenBounds.width : proxy.size.width
            let containerWidth = min(rawWidth, screenBounds.width)
            let rawHeight = proxy.size.height == 0 ? screenBounds.height : proxy.size.height
            let containerSize = CGSize(width: containerWidth, height: rawHeight)
            let geometry = HeroGeometry(
                startFrame: context.startFrame,
                containerSize: containerSize,
                containerOrigin: CGPoint(x: 0, y: containerFrame.origin.y),
                progress: progress
            )
            let safeAreaInsets = proxy.safeAreaInsets

            ZStack(alignment: .topLeading) {
                Color.black
                    .opacity(overlayOpacity(for: progress))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ZStack(alignment: .top) {
                    DiscoveryHeroImageView(
                        imageURL: context.imageURL,
                        placeholderImage: context.placeholderImage,
                        height: geometry.imageHeight,
                        pullDownOffset: max(scrollOffset, 0)
                    )
                    .offset(y: scrollOffset > 0 ? scrollOffset : 0)

                    DiscoveryHeroContentView(
                        discovery: context.discovery,
                        imageHeight: geometry.imageHeight,
                        backgroundColor: backgroundColor,
                        colorScheme: colorScheme,
                        voiceoverController: voiceoverController,
                        containerWidth: containerWidth,
                        onShare: onShare,
                        scrollOffset: $scrollOffset
                    )
                    .opacity(contentOpacity)

                    DiscoveryHeroTopControls(
                        safeAreaInsets: safeAreaInsets,
                        onClose: onClose,
                        onShowOptions: onShowOptions
                    )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: geometry.cornerRadius, style: .continuous))
                .shadow(
                    color: Color.black.opacity(geometry.shadowOpacity),
                    radius: geometry.shadowRadius,
                    x: 0,
                    y: geometry.shadowYOffset
                )
                .offset(x: geometry.offset.x, y: geometry.offset.y)
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

    private struct HeroGeometry {
        let size: CGSize
        let offset: CGPoint
        let cornerRadius: CGFloat
        let imageHeight: CGFloat
        let shadowOpacity: Double
        let shadowRadius: CGFloat
        let shadowYOffset: CGFloat

        init(startFrame: CGRect, containerSize: CGSize, containerOrigin: CGPoint, progress: CGFloat) {
            let clamped = max(0, min(progress, 1))
            let startX = startFrame.minX - containerOrigin.x
            let startY = startFrame.minY - containerOrigin.y
            let width = HeroGeometry.lerp(startFrame.width, containerSize.width, clamped)
            let height = HeroGeometry.lerp(startFrame.height, containerSize.height, clamped)
            let x = HeroGeometry.lerp(startX, 0, clamped)
            let y = HeroGeometry.lerp(startY, 0, clamped)
            let headerHeightFactor: CGFloat = 0.72
            let targetImageHeight = containerSize.height * headerHeightFactor
            let imageHeight = HeroGeometry.lerp(startFrame.height, targetImageHeight, clamped)

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

private struct DiscoveryHeroImageView: View {
    let imageURL: URL?
    let placeholderImage: UIImage?
    let height: CGFloat
    let pullDownOffset: CGFloat
    @State private var didFail = false
    @State private var hasLoaded = false

    var body: some View {
        ZStack {
            if let placeholderImage, !hasLoaded {
                Image(uiImage: placeholderImage)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#20293A"),
                        Color(hex: "#141927")
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            if let imageURL, !didFail {
                AsyncImage(url: imageURL, transaction: Transaction(animation: .none)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .onAppear { hasLoaded = true }
                    case .failure:
                        Color.clear.onAppear { didFail = true }
                    case .empty:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height + pullDownOffset)
        .clipped()
    }
}

private struct DiscoveryHeroContentView: View {
    let discovery: DiscoverySummary
    let imageHeight: CGFloat
    let backgroundColor: Color
    let colorScheme: ColorScheme
    let containerWidth: CGFloat
    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    let onShare: (() -> Void)?
    @Binding var scrollOffset: CGFloat

    init(
        discovery: DiscoverySummary,
        imageHeight: CGFloat,
        backgroundColor: Color,
        colorScheme: ColorScheme,
        voiceoverController: VoiceoverPlaybackController,
        containerWidth: CGFloat,
        onShare: (() -> Void)?,
        scrollOffset: Binding<CGFloat>
    ) {
        self.discovery = discovery
        self.imageHeight = imageHeight
        self.backgroundColor = backgroundColor
        self.colorScheme = colorScheme
        self.containerWidth = containerWidth
        self.onShare = onShare
        _voiceoverController = ObservedObject(initialValue: voiceoverController)
        _scrollOffset = scrollOffset
    }

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
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
                    .frame(height: imageHeight)
                    .overlay(headerOverlay, alignment: .bottom)
                    .overlay(headerButtons, alignment: .bottom)

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

                        detailDescriptionView
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
            }
        }
        .id(discovery.id)
        .coordinateSpace(name: "hero-scroll")
        .frame(width: containerWidth)
        .onPreferenceChange(HeroScrollOffsetPreferenceKey.self) { value in
            scrollOffset = max(value, 0)
        }
        .onAppear {
            voiceoverController.ensureMetadata(for: discovery)
        }
        .onChange(of: discovery.id) { _ in
            scrollOffset = 0
        }
    }

    private var headerOverlay: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.clear, location: 0.0),
                    .init(color: palette.overlayMidtone, location: 0.7),
                    .init(color: palette.background, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: BrandSpacing.small) {
                Text(discovery.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text(discovery.capturedAt.formatted(.dateTime.month().day().year()))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)

                if let shortDescription = discovery.shortDescription ?? discovery.highlight.nonEmptyOrNil {
                    Text(shortDescription)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.large)
                }
            }
            .padding(.bottom, BrandSpacing.xLarge)
            .padding(.horizontal, BrandSpacing.large)
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var headerButtons: some View {
        HStack {
            if let location = discovery.location {
                buttonCircle(systemName: "mappin.and.ellipse") {
                    openInMaps(location: location)
                }
            }

            Spacer()

            if let onShare {
                buttonCircle(systemName: "square.and.arrow.up", action: onShare)
            }
        }
        .padding(.horizontal, BrandSpacing.large)
        .padding(.bottom, 28)
    }

    private func buttonCircle(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.overlayButtonForeground)
                .padding(16)
                .background(palette.overlayButtonBackground)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(palette.overlayButtonBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(palette.overlayButtonShadowOpacity), radius: 8, x: 0, y: 4)
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
    private var detailDescriptionView: some View {
        if let description = discovery.detailDescription, !description.isEmpty {
            #if canImport(MarkdownUI)
            Markdown(description)
                .markdownTheme(BrandMarkdownThemeFactory.discoveryDetailTheme(for: palette))
                .textSelection(.enabled)
            #else
            Text(description)
                .font(.system(size: 16))
                .foregroundStyle(palette.textSecondary)
            #endif
        } else {
            Text(discovery.highlight)
                .font(.system(size: 16))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func openInMaps(location: DiscoveryLocation) {
        let coordinate = CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = discovery.title
        mapItem.openInMaps()
    }
}

private struct HeroScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct VoiceoverDetailButton: View {
    let discovery: DiscoverySummary
    @ObservedObject private var controller: VoiceoverPlaybackController
    let palette: BrandTheme.Palette

    init(discovery: DiscoverySummary, controller: VoiceoverPlaybackController, palette: BrandTheme.Palette) {
        self.discovery = discovery
        self.palette = palette
        _controller = ObservedObject(initialValue: controller)
    }

    var body: some View {
        Button(action: { controller.togglePlayback(for: discovery) }) {
            HStack(spacing: BrandSpacing.small) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(palette.overlayButtonForeground)
                } else {
                    Image(systemName: playbackIconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.overlayButtonForeground.opacity(iconOpacity))
                }

                Text(buttonTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.overlayButtonForeground.opacity(titleOpacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: BrandCornerRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var asset: DiscoveryVoiceoverAsset? {
        controller.assetStates[discovery.id]
    }

    private var isLoading: Bool {
        controller.isLoading(discoveryId: discovery.id) && asset == nil
    }

    private var isUnavailable: Bool {
        asset?.status == .missing
    }

    private var playbackIconName: String {
        switch controller.playbackState {
        case let .playing(id) where id == discovery.id:
            return "pause.fill"
        case let .paused(id) where id == discovery.id:
            return "play.fill"
        case let .failed(id, _ ) where id == discovery.id:
            return "arrow.clockwise"
        default:
            return "play.fill"
        }
    }

    private var buttonTitle: String {
        if isLoading {
            return "Loading narration..."
        }

        if let playback = controller.playbackState.discoveryId,
           playback == discovery.id {
            switch controller.playbackState {
            case .playing:
                return "Pause Audio"
            case .paused:
                return "Resume Audio"
            case .failed:
                return "Retry Audio"
            default:
                break
            }
        }

        if isUnavailable {
            return "Narration unavailable"
        }

        if case let .failed(id, _) = controller.playbackState, id == discovery.id {
            return "Retry Audio"
        }

        return "Play Audio Narration"
    }

    private var buttonBackground: some View {
        palette.primaryAction
            .opacity(isUnavailable ? 0.55 : 1.0)
    }

    private var iconOpacity: Double {
        isUnavailable ? 0.7 : 1.0
    }

    private var titleOpacity: Double {
        isUnavailable ? 0.75 : 1.0
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
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "waveform")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.secondary)
                    case .empty:
                        ProgressView()
                            .progressViewStyle(.circular)
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .padding(.top, safeAreaInsets.top + 12)
        .padding(.bottom, BrandSpacing.small)
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
