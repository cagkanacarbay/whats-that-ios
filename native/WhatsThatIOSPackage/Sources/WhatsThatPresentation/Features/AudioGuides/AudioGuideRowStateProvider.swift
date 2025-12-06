import Foundation
import SwiftUI
import WhatsThatDomain

// MARK: - Row State Model

/// Pre-computed state for an Audio Guide row, avoiding per-render recomputation
public struct AudioGuideRowState: Equatable {
    public let discoveryId: Int64
    public let voiceoverStatus: AudioGuideRowStatus
    public let isQueued: Bool
    public let isPlaying: Bool
    public let progress: Double?
    
    public init(
        discoveryId: Int64,
        voiceoverStatus: AudioGuideRowStatus,
        isQueued: Bool,
        isPlaying: Bool,
        progress: Double?
    ) {
        self.discoveryId = discoveryId
        self.voiceoverStatus = voiceoverStatus
        self.isQueued = isQueued
        self.isPlaying = isPlaying
        self.progress = progress
    }
}

/// Status of an audio guide based on normalized voiceover asset
public enum AudioGuideRowStatus: Equatable {
    case ready(duration: TimeInterval?)
    case generating
    case generationQueued  // Rate limiting: waiting in local queue
    case failed
    case empty
    case checking  // Loading voiceover status from server
    
    /// Returns true if the guide can be played
    public var isPlayable: Bool {
        if case .ready = self { return true }
        return false
    }
    
    /// Returns true if generation can be triggered
    public var canTriggerGeneration: Bool {
        switch self {
        case .empty, .failed: return true
        default: return false
        }
    }
}

// MARK: - Row State Provider

/// Computes and caches row states for Audio Guides, combining data from multiple sources
@MainActor
public final class AudioGuideRowStateProvider: ObservableObject {
    @Published private(set) var rowStates: [Int64: AudioGuideRowState] = [:]
    
    private let voiceoverController: VoiceoverPlaybackController
    private let queueStore: AudioGuidesQueueStore
    private let progressStore: VoiceoverProgressStore
    
    /// Discovery IDs that are in the local generation queue (rate limiting)
    private var generationQueue: Set<Int64> = []
    
    /// Discovery IDs that are currently being checked for voiceover status
    private var checkingIds: Set<Int64> = []
    
    public init(
        voiceoverController: VoiceoverPlaybackController,
        queueStore: AudioGuidesQueueStore,
        progressStore: VoiceoverProgressStore
    ) {
        self.voiceoverController = voiceoverController
        self.queueStore = queueStore
        self.progressStore = progressStore
    }
    
    // MARK: - Public API
    
    /// Returns the row state for a discovery, computing if not cached
    public func rowState(for discoveryId: Int64) -> AudioGuideRowState {
        if let cached = rowStates[discoveryId] {
            return cached
        }
        let computed = computeRowState(for: discoveryId)
        rowStates[discoveryId] = computed
        return computed
    }
    
    /// Invalidates cached state for a discovery (call when underlying data changes)
    public func invalidate(discoveryId: Int64) {
        rowStates.removeValue(forKey: discoveryId)
    }
    
    /// Invalidates all cached states
    public func invalidateAll() {
        rowStates.removeAll()
    }
    
    /// Marks a discovery as queued for generation (rate limiting)
    public func markGenerationQueued(_ discoveryId: Int64) {
        generationQueue.insert(discoveryId)
        invalidate(discoveryId: discoveryId)
    }
    
    /// Removes a discovery from the generation queue
    public func clearGenerationQueued(_ discoveryId: Int64) {
        generationQueue.remove(discoveryId)
        invalidate(discoveryId: discoveryId)
    }
    
    /// Marks discovery IDs as being checked for voiceover status
    public func markChecking(_ ids: [Int64]) {
        checkingIds.formUnion(ids)
        for id in ids {
            invalidate(discoveryId: id)
        }
    }
    
    /// Clears checking status for discovery IDs (call after prefetch completes)
    public func clearChecking(_ ids: [Int64]) {
        checkingIds.subtract(ids)
        for id in ids {
            invalidate(discoveryId: id)
        }
    }
    
    // MARK: - Computation
    
    private func computeRowState(for discoveryId: Int64) -> AudioGuideRowState {
        let status = computeStatus(for: discoveryId)
        
        return AudioGuideRowState(
            discoveryId: discoveryId,
            voiceoverStatus: status,
            isQueued: queueStore.isQueued(discoveryId),
            isPlaying: queueStore.isPlaying(discoveryId),
            progress: progressStore.position(for: discoveryId)
        )
    }
    
    private func computeStatus(for discoveryId: Int64) -> AudioGuideRowStatus {
        // Check local generation queue first (rate limiting)
        if generationQueue.contains(discoveryId) {
            return .generationQueued
        }
        
        // Get normalized asset from controller
        guard let asset = voiceoverController.normalizedAsset(for: discoveryId) else {
            // If we're still fetching status for this ID, show checking state
            if checkingIds.contains(discoveryId) {
                return .checking
            }
            return .empty
        }
        
        switch asset.status {
        case .ready:
            // Try to get duration from the asset (if available)
            // Duration is typically only known after playback begins
            return .ready(duration: nil)
        case .processing:
            return .generating
        case .failed:
            return .failed
        case .none, .missing:
            return .empty
        }
    }
}
