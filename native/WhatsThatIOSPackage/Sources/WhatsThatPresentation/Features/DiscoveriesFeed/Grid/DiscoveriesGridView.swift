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
                            .applyingIf(isFirstDiscovery) { view in
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
