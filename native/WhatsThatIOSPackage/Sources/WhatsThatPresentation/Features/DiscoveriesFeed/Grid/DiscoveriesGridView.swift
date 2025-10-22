import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct DiscoveriesGridView: View {
    @ObservedObject var viewModel: DiscoveryFeedViewModel
    let availableWidth: CGFloat
    let cardSpacing: CGFloat
    @Binding var cardFrames: [Int64: CGRect]
    let hiddenDiscovery: HiddenDiscovery?
    let onLoadMore: (DiscoverySummary) async -> Void
    let onSelect: (DiscoverySummary, URL?, CGRect) -> Void

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
        let placeholderItems = Array(0..<8)
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: cardSpacing) {
            ForEach(placeholderItems, id: \.self) { _ in
                DiscoveryCardSkeletonView(width: cardWidth, height: cardHeight)
            }
        }
        .frame(width: availableWidth, alignment: .leading)
    }

    private var gridContent: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: cardSpacing) {
            ForEach(viewModel.discoveries) { discovery in
                DiscoveryCardView(
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
                        let isFirstDiscovery = discovery.id == viewModel.discoveries.first?.id
                        let globalFrame = proxy.frame(in: .global)
                        let localFrame = proxy.frame(in: .named("discoveriesScroll"))
                        Color.clear
                            .preference(
                                key: DiscoveryCardFramePreferenceKey.self,
                                value: [discovery.id: globalFrame]
                            )
                            .if(isFirstDiscovery) { view in
                                view.preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: localFrame.minY
                                )
                            }
                    }
                    .transaction { tx in tx.animation = nil }
                )
                .onAppear {
                    Task { await onLoadMore(discovery) }
                }
            }
        }
        .frame(width: availableWidth, alignment: .leading)
        .onPreferenceChange(DiscoveryCardFramePreferenceKey.self) { value in
            if cardFrames != value {
                cardFrames = value
            }
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
