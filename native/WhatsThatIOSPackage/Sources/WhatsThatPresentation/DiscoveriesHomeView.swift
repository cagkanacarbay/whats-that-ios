import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct DiscoveriesHomeView: View {
    private let feedUseCase: DiscoveryFeedUseCase
    private let onSignOut: () -> Void
    private let onSettings: (() -> Void)?

    @StateObject private var viewModel: DiscoveryFeedViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollOffset: CGFloat = 0

    private let headerHeight: CGFloat = 110
    private let collapseDistance: CGFloat = 80
    private let gridSpacing: CGFloat = 8

    init(
        feedUseCase: DiscoveryFeedUseCase,
        onSignOut: @escaping () -> Void,
        onSettings: (() -> Void)? = nil
    ) {
        self.feedUseCase = feedUseCase
        self.onSignOut = onSignOut
        self.onSettings = onSettings
        _viewModel = StateObject(wrappedValue: DiscoveryFeedViewModel(feedUseCase: feedUseCase))
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = proxy.size.width

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
                        Color.clear.frame(height: headerHeight + BrandSpacing.large)

                        DiscoveriesGrid(
                            viewModel: viewModel,
                            availableWidth: contentWidth - (BrandSpacing.large * 2),
                            cardSpacing: gridSpacing,
                            onLoadMore: { discovery in
                                await viewModel.loadMoreIfNeeded(currentItem: discovery)
                            }
                        )
                        .padding(.horizontal, BrandSpacing.large)
                        .padding(.bottom, BrandSpacing.xLarge)
                    }
                }
                .coordinateSpace(name: "discoveriesScroll")
                .refreshable {
                    await viewModel.refresh()
                }
                .task {
                    await viewModel.loadInitialIfNeeded()
                }
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }

                header(opacity: headerOpacity)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: BrandSpacing.medium) {
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
            .padding(.bottom, BrandSpacing.medium)
        }
        .animation(.easeInOut, value: viewModel.loadState)
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

                Menu {
                    Button("Sign out", role: .destructive) {
                        onSignOut()
                    }

                    if let onSettings {
                        Button("Settings") {
                            onSettings()
                        }
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

private struct DiscoveriesGrid: View {
    @ObservedObject var viewModel: DiscoveryFeedViewModel
    let availableWidth: CGFloat
    let cardSpacing: CGFloat
    let onLoadMore: (DiscoverySummary) async -> Void

    private var cardWidth: CGFloat {
        let spacing = cardSpacing
        let totalSpacing = spacing
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
        return LazyVGrid(
            columns: [
                GridItem(.fixed(cardWidth), spacing: cardSpacing),
                GridItem(.fixed(cardWidth), spacing: cardSpacing)
            ],
            spacing: cardSpacing
        ) {
            ForEach(placeholderItems, id: \.self) { _ in
                DiscoveryCardSkeleton(width: cardWidth, height: cardHeight)
            }
        }
    }

    private var gridContent: some View {
        LazyVGrid(
            columns: [
                GridItem(.fixed(cardWidth), spacing: cardSpacing),
                GridItem(.fixed(cardWidth), spacing: cardSpacing)
            ],
            spacing: cardSpacing
        ) {
            ForEach(viewModel.discoveries) { discovery in
                DiscoveryCard(discovery: discovery, width: cardWidth, height: cardHeight)
                    .onAppear {
                        Task {
                            await onLoadMore(discovery)
                        }
                    }
            }
        }
    }
}

private struct DiscoveryCard: View {
    let discovery: DiscoverySummary
    let width: CGFloat
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            DiscoveryCardImage(url: imageURL, width: width, height: height)
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
                    .multilineTextAlignment(.center)
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

    private var imageURL: URL? {
        guard let path = discovery.imagePath else { return nil }
        return URL(string: path)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : BrandColors.Light.border
    }
}

private struct DiscoveryCardImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    @State private var didFail = false

    var body: some View {
        ZStack {
            placeholder

            if let url = url, !didFail {
                RemoteImage(
                    url: url,
                    onFailure: {
                        didFail = true
                    }
                )
            }
        }
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .clipped()
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

private struct RemoteImage: View {
    let url: URL
    var onFailure: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Color.clear
                    .onAppear {
                        onFailure?()
                    }
            case .empty:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(progressTint)
            @unknown default:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(progressTint)
            }
        }
    }

    private var progressTint: Color {
        colorScheme == .dark ? BrandColors.logo : BrandColors.Light.primaryAction
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
