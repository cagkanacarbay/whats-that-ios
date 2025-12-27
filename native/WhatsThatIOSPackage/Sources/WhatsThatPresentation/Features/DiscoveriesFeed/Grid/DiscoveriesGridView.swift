import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct DiscoveriesGridView: View {
    @ObservedObject var storeObserver: DiscoveryStoreObserver
    let availableWidth: CGFloat
    // Used to center empty state vertically
    var availableHeight: CGFloat? = nil
    let cardSpacing: CGFloat
    @Binding var cardFrames: [Int64: CGRect]
    let activeDiscoveryId: Int64?
    let onLoadMore: (DiscoverySummary) async -> Void
    let onSelect: (DiscoverySummary, URL?, CGRect) -> Void
    // Empty-state quick actions
    var onTapCamera: (() -> Void)? = nil
    var onTapUpload: (() -> Void)? = nil

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
        switch storeObserver.loadState {
        case .idle where storeObserver.discoveries.isEmpty:
            if storeObserver.isRefreshing {
                skeletonGrid
            } else {
                EmptyDiscoveriesView(onCamera: onTapCamera, onUpload: onTapUpload, minHeight: availableHeight)
            }
        case .loading:
            skeletonGrid
        case .failed(let message):
            DiscoveriesErrorView(
                message: message,
                action: {
                    Task { await storeObserver.reload() }
                }
            )
        case .loaded, .idle:
            if storeObserver.discoveries.isEmpty {
                EmptyDiscoveriesView(onCamera: onTapCamera, onUpload: onTapUpload, minHeight: availableHeight)
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
            ForEach(storeObserver.discoveries) { discovery in
                DiscoveryCardView(
                    discovery: discovery,
                    width: cardWidth,
                    height: cardHeight,
                    isHidden: activeDiscoveryId == discovery.id,
                    onSelect: { selectedDiscovery, imageURL in
                        let frame = cardFrames[selectedDiscovery.id] ?? .zero
                        onSelect(selectedDiscovery, imageURL, frame)
                    }
                )
                .background(
                    GeometryReader { proxy in
                        let isFirstDiscovery = discovery.id == storeObserver.discoveries.first?.id
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
