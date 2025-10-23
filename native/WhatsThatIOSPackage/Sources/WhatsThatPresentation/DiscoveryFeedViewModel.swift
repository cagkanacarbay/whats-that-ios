import Foundation
import OSLog
import WhatsThatDomain

private let discoveryFeedLogger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "DiscoveryFeedViewModel"
)

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
        discoveryFeedLogger.info("refresh() invoked. isRefreshing=\(self.isRefreshing, privacy: .public)")
        await fetchPage(mode: .refresh)
    }

    public func clearError() {
        errorMessage = nil
    }

    public func loadMoreIfNeeded(currentItem item: DiscoverySummary?) async {
        guard let item else { return }
        guard self.hasMore else { return }

        let thresholdIndex = self.discoveries.index(self.discoveries.endIndex, offsetBy: -4, limitedBy: self.discoveries.startIndex) ?? self.discoveries.startIndex
        if self.discoveries.indices.contains(thresholdIndex), self.discoveries[thresholdIndex].id == item.id {
            await fetchPage(mode: .loadMore)
        } else if item.id == self.discoveries.last?.id {
            await fetchPage(mode: .loadMore)
        }
    }

    private func fetchPage(mode: FetchMode, force: Bool = false) async {
        if self.isFetchingPage && !force {
            return
        }

        self.isFetchingPage = true
        let previousLoadState = self.loadState
        discoveryFeedLogger.info("fetchPage start mode=\(mode.logDescription, privacy: .public) force=\(force, privacy: .public)")

        switch mode {
        case .initial:
            self.loadState = .loading
        case .refresh:
            self.isRefreshing = true
        case .loadMore:
            self.isPaginating = true
        }

        defer {
            switch mode {
            case .initial:
                break
            case .refresh:
                self.isRefreshing = false
            case .loadMore:
                self.isPaginating = false
            }

            self.isFetchingPage = false
            discoveryFeedLogger.info("fetchPage finished mode=\(mode.logDescription, privacy: .public) isRefreshing=\(self.isRefreshing, privacy: .public) isPaginating=\(self.isPaginating, privacy: .public)")
        }

        let cursor: Int64?
        switch mode {
        case .loadMore:
            cursor = self.discoveries.last?.id
        case .initial, .refresh:
            cursor = nil
        }

        do {
            self.errorMessage = nil

            if Task.isCancelled {
                self.loadState = previousLoadState
                discoveryFeedLogger.notice("fetchPage cancelled before request mode=\(mode.logDescription, privacy: .public)")
                return
            }

            let page = try await self.feedUseCase.loadPage(limit: self.pageSize, before: cursor)

            switch mode {
            case .initial, .refresh:
                self.applyNewPage(page, replaceExisting: true)
            case .loadMore:
                self.applyNewPage(page, replaceExisting: false)
            }

            self.hasMore = page.count == self.pageSize
            self.loadState = self.discoveries.isEmpty ? .idle : .loaded
            discoveryFeedLogger.debug("fetchPage succeeded mode=\(mode.logDescription, privacy: .public) received=\(page.count, privacy: .public) total=\(self.discoveries.count, privacy: .public) hasMore=\(self.hasMore, privacy: .public)")
        } catch is CancellationError {
            self.loadState = previousLoadState
            discoveryFeedLogger.notice("fetchPage received CancellationError mode=\(mode.logDescription, privacy: .public)")
            return
        } catch {
            self.errorMessage = error.localizedDescription
            discoveryFeedLogger.error("fetchPage failed mode=\(mode.logDescription, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            if self.discoveries.isEmpty {
                self.loadState = .failed(error.localizedDescription)
            } else {
                self.loadState = .loaded
            }
        }
    }

    private func applyNewPage(_ page: [DiscoverySummary], replaceExisting: Bool) {
        let deduplicated: [DiscoverySummary]

        if replaceExisting {
            deduplicated = page.uniqued()
        } else {
            let existingIds = Set(self.discoveries.map(\.id))
            let filtered = page.filter { !existingIds.contains($0.id) }
            deduplicated = self.discoveries + filtered
        }

        self.discoveries = deduplicated
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

        var logDescription: String {
            switch self {
            case .initial:
                return "initial"
            case .refresh:
                return "refresh"
            case .loadMore:
                return "loadMore"
            }
        }
    }
}
