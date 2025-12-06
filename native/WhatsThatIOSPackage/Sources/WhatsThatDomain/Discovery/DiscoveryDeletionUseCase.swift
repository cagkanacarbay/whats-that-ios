import Foundation
import WhatsThatShared

/// Handles discovery deletion with cascading cleanup of audio-related caches and stores.
public actor DiscoveryDeletionUseCase: Sendable {
    private let repository: DiscoveryRepository
    private let voiceoverFileCache: VoiceoverFileCache?
    private let progressStoreClear: ((Int64) async -> Void)?
    private let queueStoreRemove: ((Int64) async -> Void)?
    
    /// Creates a deletion use case with optional audio cleanup dependencies.
    /// - Parameters:
    ///   - repository: The discovery repository for backend deletion
    ///   - voiceoverFileCache: Cache for audio files (optional, for cleanup)
    ///   - progressStoreClear: Closure to clear progress for a discoveryId (optional)
    ///   - queueStoreRemove: Closure to remove from all queue lists (optional)
    public init(
        repository: DiscoveryRepository,
        voiceoverFileCache: VoiceoverFileCache? = nil,
        progressStoreClear: ((Int64) async -> Void)? = nil,
        queueStoreRemove: ((Int64) async -> Void)? = nil
    ) {
        self.repository = repository
        self.voiceoverFileCache = voiceoverFileCache
        self.progressStoreClear = progressStoreClear
        self.queueStoreRemove = queueStoreRemove
    }
    
    /// Convenience initializer for backward compatibility (no audio cleanup)
    public init(repository: DiscoveryRepository) {
        self.repository = repository
        self.voiceoverFileCache = nil
        self.progressStoreClear = nil
        self.queueStoreRemove = nil
    }

    /// Deletes a discovery and cascades cleanup to audio-related stores.
    public func delete(_ summary: DiscoverySummary) async throws {
        let discoveryId = summary.id
        
        // 1. Delete from backend
        try await repository.deleteDiscovery(summary)
        
        // 2. Delete cached audio file
        await voiceoverFileCache?.remove(discoveryId: discoveryId)
        
        // 3. Clear progress/lastPlayed
        await progressStoreClear?(discoveryId)
        
        // 4. Remove from queue/history
        await queueStoreRemove?(discoveryId)
    }
}
