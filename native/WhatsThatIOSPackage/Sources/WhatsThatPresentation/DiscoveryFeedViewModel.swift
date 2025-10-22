import Foundation
import WhatsThatDomain

@MainActor
public final class DiscoveryFeedViewModel: ObservableObject {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published public private(set) var discoveries: [DiscoverySummary] = []
    @Published public private(set) var hasMore: Bool = true
    @Published public private(set) var loadState: LoadState = .idle
    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var isPaginating: Bool = false
    @Published public private(set) var errorMessage: String?

    private let feedUseCase: DiscoveryFeedUseCase
    private let pageSize: Int
    private var didAttemptInitialLoad = false
    private var isFetchingPage = false

    public init(feedUseCase: DiscoveryFeedUseCase, pageSize: Int = 10) {
        self.feedUseCase = feedUseCase
        self.pageSize = pageSize
    }

    public func loadInitialIfNeeded() async {
        guard !didAttemptInitialLoad else { return }
        didAttemptInitialLoad = true
        await fetchPage(mode: .initial)
    }

    public func reload() async {
        didAttemptInitialLoad = true
        await fetchPage(mode: .initial, force: true)
    }

    public func refresh() async {
        await fetchPage(mode: .refresh)
    }

    public func clearError() {
        errorMessage = nil
    }

    public func loadMoreIfNeeded(currentItem item: DiscoverySummary?) async {
        guard let item else { return }
        guard hasMore else { return }

        let thresholdIndex = discoveries.index(discoveries.endIndex, offsetBy: -4, limitedBy: discoveries.startIndex) ?? discoveries.startIndex
        if discoveries.indices.contains(thresholdIndex), discoveries[thresholdIndex].id == item.id {
            await fetchPage(mode: .loadMore)
        } else if item.id == discoveries.last?.id {
            await fetchPage(mode: .loadMore)
        }
    }

    private func fetchPage(mode: FetchMode, force: Bool = false) async {
        if isFetchingPage && !force {
            return
        }

        isFetchingPage = true

        switch mode {
        case .initial:
            loadState = .loading
        case .refresh:
            isRefreshing = true
        case .loadMore:
            isPaginating = true
        }

        let cursor: Int64?
        switch mode {
        case .loadMore:
            cursor = discoveries.last?.id
        case .initial, .refresh:
            cursor = nil
        }

        do {
            errorMessage = nil
            let page = try await feedUseCase.loadPage(limit: pageSize, before: cursor)

            switch mode {
            case .initial, .refresh:
                applyNewPage(page, replaceExisting: true)
            case .loadMore:
                applyNewPage(page, replaceExisting: false)
            }

            hasMore = page.count == pageSize
            loadState = discoveries.isEmpty ? .idle : .loaded
        } catch {
            errorMessage = error.localizedDescription
            if discoveries.isEmpty {
                loadState = .failed(error.localizedDescription)
            } else {
                loadState = .loaded
            }
        }

        switch mode {
        case .initial:
            break
        case .refresh:
            isRefreshing = false
        case .loadMore:
            isPaginating = false
        }

        isFetchingPage = false
    }

    private func applyNewPage(_ page: [DiscoverySummary], replaceExisting: Bool) {
        let deduplicated: [DiscoverySummary]

        if replaceExisting {
            deduplicated = page.uniqued()
        } else {
            let existingIds = Set(discoveries.map(\.id))
            let filtered = page.filter { !existingIds.contains($0.id) }
            deduplicated = discoveries + filtered
        }

        discoveries = deduplicated
    }
}

private extension Array where Element == DiscoverySummary {
    func uniqued() -> [DiscoverySummary] {
        var seen: Set<Int64> = []
        var result: [DiscoverySummary] = []
        result.reserveCapacity(count)

        for item in self {
            if !seen.contains(item.id) {
                seen.insert(item.id)
                result.append(item)
            }
        }

        return result
    }
}

public extension DiscoveryFeedViewModel {
    func upsert(_ summary: DiscoverySummary) {
        var updated = discoveries.filter { $0.id != summary.id }
        updated.insert(summary, at: 0)
        updated.sort { $0.capturedAt > $1.capturedAt }
        discoveries = updated
        loadState = discoveries.isEmpty ? .idle : .loaded
        hasMore = true
    }
}

private extension DiscoveryFeedViewModel {
    enum FetchMode {
        case initial
        case refresh
        case loadMore
    }
}
