import Foundation
import OSLog

private let logger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "DiscoveryStoreObserver"
)

/// A @MainActor wrapper around DiscoveryStore that provides @Published properties
/// for reactive SwiftUI updates. This is the single source of truth for discovery
/// data across the app - both Discoveries Feed and Audio Guides read from this observer.
@MainActor
public final class DiscoveryStoreObserver: ObservableObject {
    
    // MARK: - Published State
    
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
    
    // MARK: - Dependencies
    
    private let store: DiscoveryStore
    private let pageSize: Int
    private var didAttemptInitialLoad = false
    private var isFetchingPage = false
    
    // MARK: - Init
    
    public init(store: DiscoveryStore, pageSize: Int = 10) {
        self.store = store
        self.pageSize = pageSize
    }
    
    // MARK: - Public API (Fetching)
    
    /// Loads the initial page of discoveries if not already loaded.
    public func loadInitialIfNeeded() async {
        guard !didAttemptInitialLoad else { return }
        didAttemptInitialLoad = true
        await fetchPage(mode: .initial)
    }
    
    /// Forces a reload of the initial page.
    public func reload() async {
        didAttemptInitialLoad = true
        await fetchPage(mode: .initial, force: true)
    }
    
    /// Refreshes discoveries (pull-to-refresh).
    public func refresh() async {
        logger.info("refresh() invoked. isRefreshing=\(self.isRefreshing, privacy: .public)")
        await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                await self.fetchPage(mode: .refresh)
                continuation.resume()
            }
        }
    }
    
    /// Clears the current error message.
    public func clearError() {
        errorMessage = nil
    }
    
    /// Loads more discoveries when approaching the end of the list.
    public func loadMoreIfNeeded(currentItem item: DiscoverySummary?) async {
        guard let item else { return }
        guard hasMore else { return }
        
        let thresholdIndex = discoveries.index(
            discoveries.endIndex,
            offsetBy: -4,
            limitedBy: discoveries.startIndex
        ) ?? discoveries.startIndex
        
        if discoveries.indices.contains(thresholdIndex),
           discoveries[thresholdIndex].id == item.id {
            await fetchPage(mode: .loadMore)
        } else if item.id == discoveries.last?.id {
            await fetchPage(mode: .loadMore)
        }
    }
    
    // MARK: - Public API (Mutations)
    
    /// Upserts a discovery (e.g., after creation). Updates are immediately visible.
    public func upsert(_ summary: DiscoverySummary) async {
        await store.upsert(summary)
        await syncFromStore()
        loadState = discoveries.isEmpty ? .idle : .loaded
        hasMore = true
    }
    
    /// Removes a discovery by ID. Updates are immediately visible.
    public func remove(id: Int64) async {
        await store.remove(id: id)
        await syncFromStore()
        loadState = discoveries.isEmpty ? .idle : .loaded
    }
    
    /// Removes a discovery. Updates are immediately visible.
    public func remove(_ summary: DiscoverySummary) async {
        await remove(id: summary.id)
    }
    
    // MARK: - Internal
    
    private enum FetchMode {
        case initial
        case refresh
        case loadMore
        
        var logDescription: String {
            switch self {
            case .initial: return "initial"
            case .refresh: return "refresh"
            case .loadMore: return "loadMore"
            }
        }
    }
    
    private func fetchPage(mode: FetchMode, force: Bool = false) async {
        if isFetchingPage && !force {
            logger.notice("fetchPage skipped due to in-flight request mode=\(mode.logDescription, privacy: .public)")
            return
        }
        
        isFetchingPage = true
        
        if Task.isCancelled {
            logger.warning("fetchPage invoked with cancelled task mode=\(mode.logDescription, privacy: .public)")
        }
        
        switch mode {
        case .initial:
            loadState = .loading
        case .refresh:
            isRefreshing = true
        case .loadMore:
            isPaginating = true
        }
        
        defer {
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
        
        let cursor: Int64?
        switch mode {
        case .loadMore:
            cursor = discoveries.last?.id
        case .initial, .refresh:
            cursor = nil
        }
        
        do {
            errorMessage = nil
            
            // Use the store's loadMore which handles caching internally
            let page = try await store.loadMore(limit: pageSize, before: cursor)
            
            switch mode {
            case .initial, .refresh:
                // For initial/refresh, sync full cache (store replaces on nil cursor)
                await syncFromStore()
            case .loadMore:
                // For pagination, sync to include the new items
                await syncFromStore()
            }
            
            hasMore = page.count == pageSize
            loadState = discoveries.isEmpty ? .idle : .loaded
            
        } catch {
            let resolvedMessage: String
            
            if error is CancellationError {
                resolvedMessage = DiscoveryFeedError.failedToLoad.localizedDescription
                logger.error("fetchPage unexpectedly cancelled mode=\(mode.logDescription, privacy: .public)")
            } else {
                resolvedMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                logger.error("fetchPage failed mode=\(mode.logDescription, privacy: .public) error=\(resolvedMessage, privacy: .public)")
            }
            
            errorMessage = resolvedMessage
            if discoveries.isEmpty {
                loadState = .failed(resolvedMessage)
            } else {
                loadState = .loaded
            }
        }
    }
    
    private func syncFromStore() async {
        discoveries = await store.allCached()
    }
}
