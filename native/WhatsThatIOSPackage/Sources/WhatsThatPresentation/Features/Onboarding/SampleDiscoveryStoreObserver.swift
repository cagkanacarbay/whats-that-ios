import Foundation
import OSLog
import WhatsThatDomain
import WhatsThatShared

private let logger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "SampleDiscoveryStoreObserver"
)

/// Store observer for sample discoveries used in pre-onboarding.
/// Fetches all sample discoveries and provides @Published state for SwiftUI.
@MainActor
public final class SampleDiscoveryStoreObserver: ObservableObject {

    // MARK: - Published State

    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published public private(set) var discoveries: [DiscoverySummary] = []
    @Published public private(set) var loadState: LoadState = .idle

    // MARK: - Dependencies

    private let service: SampleDiscoveryService
    private var didAttemptLoad = false

    // MARK: - Init

    public init(service: SampleDiscoveryService) {
        self.service = service
    }

    // MARK: - Public API

    /// Loads sample discoveries for pre-onboarding.
    public func loadSampleDiscoveries() async {
        guard !didAttemptLoad else {
            logger.info("Sample discoveries already loaded, skipping")
            return
        }

        didAttemptLoad = true
        loadState = .loading

        do {
            let samples = try await service.fetchSampleDiscoveries()

            // Check for cancellation after async operation
            if Task.isCancelled {
                didAttemptLoad = false
                loadState = .idle
                return
            }

            discoveries = samples
            loadState = .loaded

            // Start preloading images in background (non-blocking)
            // Cards show immediately with shimmer, images appear as they cache
            Task.detached(priority: .userInitiated) { [samples] in
                await self.preloadImages(for: samples)
            }
            logger.info("Loaded \(samples.count) sample discoveries for pre-onboarding")
        } catch {
            // Check if task was cancelled (handles both CancellationError and wrapped cancellation)
            if Task.isCancelled {
                didAttemptLoad = false
                loadState = .idle
                return
            }

            logger.error("Failed to load sample discoveries: \(error.localizedDescription, privacy: .public)")
            loadState = .failed
        }
    }

    /// Reloads sample discoveries (for retry after error).
    public func reload() async {
        didAttemptLoad = false
        await loadSampleDiscoveries()
    }

    /// Fetches voiceover assets for the loaded sample discoveries.
    /// Call this after `loadSampleDiscoveries()` completes.
    public func fetchVoiceovers() async -> [DiscoveryVoiceoverAsset] {
        guard !discoveries.isEmpty else { return [] }
        let ids = discoveries.map { $0.id }
        do {
            return try await service.fetchSampleVoiceovers(for: ids)
        } catch {
            logger.error("Failed to fetch sample voiceovers: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Private Helpers

    /// Preloads all images for sample discoveries so they appear simultaneously.
    private func preloadImages(for discoveries: [DiscoverySummary]) async {
        let imageURLs = discoveries.compactMap { discovery -> (Int64, URL)? in
            guard let path = discovery.imagePath, let url = URL(string: path) else { return nil }
            return (discovery.id, url)
        }

        await withTaskGroup(of: Void.self) { group in
            for (discoveryId, url) in imageURLs {
                group.addTask {
                    _ = await DiscoveryAssetCache.shared.ensureImageCached(
                        for: discoveryId,
                        signedURL: url
                    )
                }
            }
        }

        logger.debug("Preloaded \(imageURLs.count) images for sample discoveries")
    }
}
