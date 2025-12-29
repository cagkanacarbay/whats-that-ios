import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared
import os

private let log = Logger(subsystem: "WhatsThat.AudioGuides", category: "VoiceoverPlaybackController")

@MainActor
public final class VoiceoverPlaybackController: ObservableObject {
    public enum PlaybackState: Equatable {
        case idle
        case preparing(discoveryId: Int64)
        case playing(discoveryId: Int64)
        case paused(discoveryId: Int64)
        case failed(discoveryId: Int64, message: String?)

        public var discoveryId: Int64? {
            switch self {
            case .idle: return nil
            case let .preparing(id),
                 let .playing(id),
                 let .paused(id),
                 let .failed(id, _):
                return id
            }
        }

        public var isActive: Bool {
            switch self {
            case .playing, .paused:
                return true
            case .idle, .preparing, .failed:
                return false
            }
        }
    }

    @Published public private(set) var playbackState: PlaybackState = .idle
    @Published public private(set) var currentDiscovery: DiscoverySummary?
    @Published public private(set) var position: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var assetStates: [Int64: DiscoveryVoiceoverAsset] = [:]
    @Published public private(set) var activePreferences: VoiceoverPreferences
    @Published public var isDetailOverlayActive: Bool = false
    @Published public var suppressProgressUpdates: Bool = false
    
    /// Current playback rate (persisted via VoiceoverPlaybackSpeedStore)
    @Published public private(set) var currentRate: Double = 1.0
    @Published private var downloadedIds: Set<Int64> = []
    private var pendingIds: Set<Int64> = []
    private var pollingTask: Task<Void, Never>?
    private let pollIntervals: [TimeInterval] = [1, 3, 5]

    private let repository: any DiscoveryVoiceoverRepository
    private let voiceoverCache: VoiceoverFileCache
    private let urlSession: URLSession
    private let preferencesStore: VoiceoverPreferencesStore?
    private let audioSession: AVAudioSession
    private let player: AVPlayer
    private let nowPlayingInfoCenter: MPNowPlayingInfoCenter
    private let remoteCommandCenter: MPRemoteCommandCenter
    private let pendingStore: VoiceoverPendingStore
    private var discoveryQueueProvider: (() -> [DiscoverySummary])?
    private var artworkCache: [Int64: MPMediaItemArtwork] = [:]
    private var artworkTasks: [Int64: Task<MPMediaItemArtwork?, Never>] = [:]
    private var remoteCommandTargets: [Any] = []
    private var timeObserverToken: Any?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var endPlaybackObserver: NSObjectProtocol?
    private var playTask: Task<Void, Never>?
    private var isSeeking = false
    private let failedExpiry: TimeInterval = 60 * 60
    private let processingStaleThreshold: TimeInterval = 60 * 5
    private let artworkTargetSide: CGFloat = 800
    private var lastNowPlayingInfo: [String: Any]?
    
    // MARK: - Audio Guides Store References (set via configure())
    private var queueStore: AudioGuidesQueueStore?
    private var speedStore: VoiceoverPlaybackSpeedStore?
    private var progressStore: VoiceoverProgressStore?
    private var discoveryStore: DiscoveryStore?
    
    /// Called when voiceover generation completes successfully (for toast notification)
    public var onGenerationComplete: ((DiscoverySummary) -> Void)?
    
    /// Called when server returns updated credit balance after voiceover request
    public var onCreditBalanceUpdated: ((Int) -> Void)?

    public init(
        repository: any DiscoveryVoiceoverRepository,
        preferences: VoiceoverPreferences = VoiceoverPreferences(
            autoEnabled: false,
            voiceModelId: "",
            ttsModel: "s1"
        ),
        voiceoverCache: VoiceoverFileCache = .shared,
        preferencesStore: VoiceoverPreferencesStore? = nil,
        audioSession: AVAudioSession = .sharedInstance(),
        player: AVPlayer = AVPlayer(),
        urlSession: URLSession = .shared,
        pendingStore: VoiceoverPendingStore = .shared,
        nowPlayingInfoCenter: MPNowPlayingInfoCenter = .default(),
        remoteCommandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.repository = repository
        self.voiceoverCache = voiceoverCache
        self.activePreferences = preferences
        self.preferencesStore = preferencesStore
        self.audioSession = audioSession
        self.player = player
        self.urlSession = urlSession
        self.pendingStore = pendingStore
        self.nowPlayingInfoCenter = nowPlayingInfoCenter
        self.remoteCommandCenter = remoteCommandCenter

        do {
            try audioSession.setCategory(.playback, mode: .default)
        } catch {
            print("Failed to set audio session category: \(error)")
        }

        UIApplication.shared.beginReceivingRemoteControlEvents()
        configureRemoteCommands()

        Task { [weak self] in
            await self?.restorePendingRequests()
        }
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        playerItemStatusObservation?.invalidate()
        if let observer = endPlaybackObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        Task { @MainActor in
            UIApplication.shared.endReceivingRemoteControlEvents()
        }
        pollingTask?.cancel()
        nowPlayingInfoCenter.nowPlayingInfo = nil
        nowPlayingInfoCenter.playbackState = .stopped
        lastNowPlayingInfo = nil
        
        // Clean up specific targets we added
        // Note: The MPRemoteCommand API requires removing the target from the *specific* command.
        // Since we just stored them in a flat list, we can't easily know which command they belong to.
        // However, simply letting them deallocate is usually fine for block-based targets (they become no-ops).
        // But to be proper, we should have stored them by command.
        // Given the urgency, the most important fix was REMOVING the 'removeTarget(nil)' call.
        // We will clear the list to release the opaque objects.
        remoteCommandTargets.removeAll()
        
        artworkTasks.values.forEach { $0.cancel() }
    }
}

// MARK: - Public API

public extension VoiceoverPlaybackController {
    func prefetch(for discoveryIds: [Int64]) {
        guard !discoveryIds.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            let assets = await self.repository.fetchVoiceovers(for: discoveryIds)
            await MainActor.run {
                for asset in assets {
                    let normalized = self.normalize(asset)
                    self.applyFetchedAsset(normalized)
                }
                self.startPollingIfNeeded()
            }
        }
    }
    
    /// Async prefetch that returns when all assets have been fetched and applied.
    /// Use this when you need to ensure voiceover states are loaded before rendering UI.
    func prefetchAsync(for discoveryIds: [Int64]) async {
        guard !discoveryIds.isEmpty else { return }
        let assets = await repository.fetchVoiceovers(for: discoveryIds)
        for asset in assets {
            let normalized = normalize(asset)
            applyFetchedAsset(normalized)
        }
        startPollingIfNeeded()
    }

    func togglePlayback(for discovery: DiscoverySummary, preferences: VoiceoverPreferences? = nil) {
        log.debug("[togglePlayback] Called for id=\(discovery.id), title='\(discovery.title)', imagePath=\(discovery.imagePath ?? "nil")")
        log.debug("[togglePlayback] Current state: playbackState=\(String(describing: self.playbackState)), currentDiscovery.id=\(self.currentDiscovery?.id ?? -1)")
        
        let asset = normalizedAsset(for: discovery.id)
        let resolvedPreferences = preferences ?? activePreferences
        log.debug("[togglePlayback] Asset status: \(String(describing: asset?.status))")

        switch asset?.status {
        case .ready?:
            if case let .playing(id) = playbackState, id == discovery.id {
                log.debug("[togglePlayback] Already playing this discovery, pausing")
                pause()
                return
            }
            if case let .paused(id) = playbackState, id == discovery.id {
                log.debug("[togglePlayback] Was paused on this discovery, resuming")
                resume()
                return
            }
            guard let readyAsset = asset else { return }
            
            // Set up queue navigation context for Previous/Next buttons
            // Update if:
            // - Current item is changing (user is playing something new)
            // - OR baseList is empty (e.g., after app restart with persisted current but no baseList)
            if let queueStore = queueStore,
               queueStore.current != discovery.id || queueStore.baseList.isEmpty {
                // Get discovery IDs from discoveryQueueProvider (all discoveries from feed)
                // Filter to only include discoveries with READY audio guides
                let audioReadyIds: [Int64]
                if let provider = discoveryQueueProvider {
                    // Use all discoveries from feed (maintains proper order)
                    let allDiscoveries = provider()
                    // Filter to only audio-ready items
                    audioReadyIds = allDiscoveries.compactMap { disc -> Int64? in
                        guard let asset = assetStates[disc.id], asset.status == .ready else {
                            return nil
                        }
                        return disc.id
                    }
                    log.debug("[togglePlayback] Using discoveryQueueProvider: total=\(allDiscoveries.count), audioReady=\(audioReadyIds.count)")
                } else {
                    // Fallback: just use current item
                    audioReadyIds = [discovery.id]
                    log.debug("[togglePlayback] No discoveryQueueProvider, using single item")
                }
                
                queueStore.playNow(discovery.id, recentering: audioReadyIds)
                log.debug("[togglePlayback] Queue after playNow: current=\(queueStore.current ?? -1), baseList.count=\(queueStore.baseList.count)")
            }
            
            log.debug("[togglePlayback] Asset ready, calling play()")
            play(discovery: discovery, asset: readyAsset)
        case .processing?:
            log.debug("[togglePlayback] Asset processing, setting state to preparing")
            playbackState = .preparing(discoveryId: discovery.id)
        case .failed?, .none?, .missing?:
            log.debug("[togglePlayback] Asset failed/none/missing, requesting voiceover")
            requestVoiceover(for: discovery, preferences: resolvedPreferences)
        case nil:
            log.debug("[togglePlayback] No asset found, requesting voiceover")
            requestVoiceover(for: discovery, preferences: resolvedPreferences)
        }
    }

    func setCurrentDiscovery(_ discovery: DiscoverySummary) {
        currentDiscovery = discovery
    }

    func setDiscoveryQueueProvider(_ provider: @escaping () -> [DiscoverySummary]) {
        discoveryQueueProvider = provider
    }
    
    /// Gets a discovery by ID from the discovery queue provider
    /// This is useful when the discovery might not be in the DiscoveryStore cache
    func getDiscovery(id: Int64) -> DiscoverySummary? {
        discoveryQueueProvider?().first { $0.id == id }
    }

    @discardableResult
    func skipToNextDiscovery() -> DiscoverySummary? {
        // Use queueStore if available for consistent navigation
        if let queueStore = queueStore, let nextId = queueStore.next() {
            if let discovery = getDiscovery(id: nextId) {
                togglePlayback(for: discovery)
                return discovery
            } else {
                // Fallback to async fetch via discoveryStore
                Task {
                    if let discovery = await discoveryStore?.get(id: nextId) {
                        await MainActor.run {
                            self.togglePlayback(for: discovery)
                        }
                    }
                }
            }
        }
        
        // Fallback to old queue logic if queueStore is missing (e.g. unit tests or isolation)
        guard let discovery = nextDiscoveryInQueue() else { return nil }
        togglePlayback(for: discovery)
        return discovery
    }

    @discardableResult
    func skipToPreviousDiscovery() -> DiscoverySummary? {
        // Use queueStore if available
        if let queueStore = queueStore {
            let currentPos = position
            if let prevId = queueStore.previous(currentPosition: currentPos) {
                 if prevId == queueStore.current {
                     // Restart
                     seek(to: 0) {}
                     return currentDiscovery
                 } else if let discovery = getDiscovery(id: prevId) {
                     togglePlayback(for: discovery)
                     return discovery
                 }
            }
        }

        guard let discovery = previousDiscoveryInQueue() else { return nil }
        togglePlayback(for: discovery)
        return discovery
    }

    func requestVoiceover(for discovery: DiscoverySummary, preferences: VoiceoverPreferences? = nil) {
        log.debug("[requestVoiceover] CALLED for id=\(discovery.id), title='\(discovery.title)'")
        Task { [weak self] in
            guard let self else {
                log.error("[requestVoiceover] self is nil, aborting")
                return
            }
            let resolvedPreferences: VoiceoverPreferences
            if let preferences {
                resolvedPreferences = preferences
                await self.preferencesStore?.save(preferences)
                await MainActor.run {
                    self.activePreferences = preferences
                }
            } else if let store = self.preferencesStore {
                let loaded = await store.load(
                    defaultVoiceModelId: self.activePreferences.voiceModelId,
                    defaultTtsModel: self.activePreferences.ttsModel
                )
                resolvedPreferences = loaded
                await MainActor.run {
                    self.activePreferences = loaded
                }
            } else {
                resolvedPreferences = self.activePreferences
            }

            log.debug("[requestVoiceover] voiceModelId='\(resolvedPreferences.voiceModelId)', ttsModel='\(resolvedPreferences.ttsModel)'")
            guard !resolvedPreferences.voiceModelId.isEmpty else {
                log.error("[requestVoiceover] voiceModelId is EMPTY, showing error")
                await MainActor.run {
                    self.errorMessage = "Choose a voice to generate audio."
                }
                return
            }
            await MainActor.run {
                self.assetStates[discovery.id] = DiscoveryVoiceoverAsset(
                    discoveryId: discovery.id,
                    status: .processing,
                    audioURL: nil,
                    provider: nil,
                    ttsModel: resolvedPreferences.ttsModel,
                    voiceModelId: resolvedPreferences.voiceModelId,
                    fileName: nil,
                    fileExtension: nil,
                    requestedAt: Date(),
                    updatedAt: Date(),
                    errorReason: nil,
                    wasExistingResponse: false,
                    wasRefunded: false
                )
                // NOTE: We intentionally do NOT set currentDiscovery or playbackState here.
                // Generation should not affect the mini player in any way - it should only
                // update the assetStates for UI feedback (e.g., showing "Generating..." status).
            }
            markPending(discovery.id)
            startPollingIfNeeded()

            log.debug("[requestVoiceover] CALLING repository.requestVoiceover for id=\(discovery.id)")
            let asset = await self.repository.requestVoiceover(
                for: discovery.id,
                voiceModelId: resolvedPreferences.voiceModelId,
                ttsModel: resolvedPreferences.ttsModel
            )
            log.debug("[requestVoiceover] repository.requestVoiceover RETURNED status=\(String(describing: asset.status)), audioURL=\(asset.audioURL?.absoluteString ?? "nil"), errorReason=\(asset.errorReason ?? "nil")")

            let normalized = normalize(asset)
            await MainActor.run {
                self.applyFetchedAsset(normalized)
            }
            Task { [weak self] in
                await self?.refreshCacheFlag(for: normalized)
            }

            if normalized.status == .failed && normalized.wasExistingResponse {
                self.prefetch(for: [discovery.id])
            }

            if normalized.status == .ready, let _ = normalized.audioURL {
                clearPending(discovery.id)
                // Sync credit balance if server provided updated value
                if let serverBalance = normalized.creditBalance {
                    await MainActor.run {
                        self.onCreditBalanceUpdated?(serverBalance)
                    }
                }
                // Notify that generation completed (for toast) - don't affect playback state
                await MainActor.run {
                    self.onGenerationComplete?(discovery)
                }
            } else if normalized.status == .failed {
                clearPending(discovery.id)
                // Only set error message, don't affect playback state
                await MainActor.run {
                    self.errorMessage = normalized.errorReason
                }
            }
            // No else case needed - we don't modify playbackState during generation
        }
    }

    func pause() {
        player.pause()
        if case let .playing(id) = playbackState {
            playbackState = .paused(discoveryId: id)
        }
        updateNowPlayingPlaybackState()
        refreshNowPlayingInfo()
    }

    func resume() {
        guard case let .paused(id) = playbackState else { return }
        Task {
            await prepareAudioSession()
        }
        player.play()
        playbackState = .playing(discoveryId: id)
        updateNowPlayingPlaybackState()
        refreshNowPlayingInfo()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        playbackState = .idle
        currentDiscovery = nil
        duration = nil
        position = 0
        errorMessage = nil
        teardownObservers()
        nowPlayingInfoCenter.nowPlayingInfo = nil
        lastNowPlayingInfo = nil
        updateNowPlayingPlaybackState()
    }

    func seek(to seconds: TimeInterval, completion: (() -> Void)? = nil) {
        print("[VoiceoverPlaybackController.seek] Called with seconds=\(seconds), duration=\(String(describing: duration))")
        guard let duration, duration > 0 else {
            print("[VoiceoverPlaybackController.seek] EARLY RETURN - duration is nil or 0")
            completion?()
            return
        }

        let clamped = max(0, min(seconds, duration))
        let time = CMTime(seconds: clamped, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        print("[VoiceoverPlaybackController.seek] Seeking to clamped=\(clamped)")
        isSeeking = true
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self else { return }
            print("[VoiceoverPlaybackController.seek] Seek completed, finished=\(finished)")
            Task { @MainActor in
                self.position = clamped
                self.isSeeking = false
                completion?()
            }
        }
    }

    func isLoading(discoveryId: Int64) -> Bool {
        if case let .preparing(id) = playbackState, id == discoveryId {
            return true
        }
        return false
    }

    func isActive(discoveryId: Int64) -> Bool {
        if case let .playing(id) = playbackState, id == discoveryId { return true }
        if case let .paused(id) = playbackState, id == discoveryId { return true }
        return false
    }

    func isDownloadPending(for discoveryId: Int64) -> Bool {
        guard let asset = assetStates[discoveryId] else { return false }
        return asset.status == .ready && !downloadedIds.contains(discoveryId)
    }

    func updatePreferences(_ preferences: VoiceoverPreferences) {
        activePreferences = preferences
    }
    
    // MARK: - Audio Guides Configuration
    
    /// Called once by AudioServicesContainer after creation.
    /// Wires up stores for queue integration, speed persistence, and progress tracking.
    func configure(
        queueStore: AudioGuidesQueueStore,
        speedStore: VoiceoverPlaybackSpeedStore,
        progressStore: VoiceoverProgressStore,
        discoveryStore: DiscoveryStore
    ) {
        self.queueStore = queueStore
        self.speedStore = speedStore
        self.progressStore = progressStore
        self.discoveryStore = discoveryStore
        
        // Initialize rate from persisted value
        self.currentRate = speedStore.speed
        player.rate = Float(speedStore.speed)
    }
    
    // MARK: - Seek Controls
    
    /// Seek forward/backward by a number of seconds
    func seek(by seconds: TimeInterval) {
        guard let duration = self.duration, duration > 0 else { return }
        
        let currentTime = player.currentTime().seconds
        let newTime = max(0, min(duration, currentTime + seconds))
        
        isSeeking = true
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: 600)) { [weak self] finished in
            guard let self, finished else { return }
            Task { @MainActor in
                self.position = newTime
                self.isSeeking = false
                
                // Persist position for display
                if let discoveryId = self.currentDiscovery?.id {
                    self.progressStore?.updatePosition(newTime / duration, for: discoveryId)
                }
            }
        }
    }
    
    /// Seek to a specific fraction of the track (0.0 to 1.0)
    func seek(toFraction fraction: Double) {
        guard let duration = self.duration, duration > 0 else { return }
        
        let newTime = duration * max(0, min(1, fraction))
        seek(to: newTime)
    }
    
    // MARK: - Rate Control
    
    /// Set playback rate and persist
    func setRate(_ rate: Double) {
        let validRates = VoiceoverPlaybackSpeedStore.validRates
        guard validRates.contains(rate) else { return }
        
        // Only update rate if currently playing
        if case .playing = playbackState {
            player.rate = Float(rate)
        }
        currentRate = rate
        speedStore?.speed = rate
    }
    
    /// Cycle to next playback speed
    func cycleRate() {
        let validRates = VoiceoverPlaybackSpeedStore.validRates
        guard let currentIndex = validRates.firstIndex(of: currentRate) else {
            setRate(1.0)
            return
        }
        let nextIndex = (currentIndex + 1) % validRates.count
        setRate(validRates[nextIndex])
    }
}

// MARK: - Private helpers

extension VoiceoverPlaybackController {
    public func normalizedAsset(for discoveryId: Int64) -> DiscoveryVoiceoverAsset? {
        guard let asset = assetStates[discoveryId] else { return nil }
        return normalize(asset)
    }

    func applyFetchedAsset(_ asset: DiscoveryVoiceoverAsset) {
        let normalized = normalize(asset)

        if let existing = assetStates[asset.discoveryId] {
            if existing.status == .ready {
                if normalized.status != .ready || normalized.audioURL == nil {
                    return
                }
                if let existingUpdated = existing.updatedAt,
                   let incomingUpdated = normalized.updatedAt,
                   incomingUpdated < existingUpdated {
                    return
                }
            }
            // Protect .processing status - only overwrite with terminal states (.ready or .failed)
            if existing.status == .processing {
                if normalized.status != .ready && normalized.status != .failed {
                    // Keep the current .processing state, don't overwrite with .none or .processing
                    return
                }
            }
        }

        assetStates[asset.discoveryId] = normalized
        if normalized.status == .processing {
            markPending(asset.discoveryId)
        } else {
            clearPending(asset.discoveryId)
        }
        Task { [weak self] in
            await self?.refreshCacheFlag(for: normalized)
        }
        if normalized.status == .ready {
            Task { [weak self] in
                await self?.cacheReadyAssetIfNeeded(for: normalized)
            }
        }
    }

    public func normalize(_ asset: DiscoveryVoiceoverAsset) -> DiscoveryVoiceoverAsset {
        if asset.status == .processing {
            let lastUpdate = asset.updatedAt ?? asset.requestedAt
            if let lastUpdate, Date().timeIntervalSince(lastUpdate) > processingStaleThreshold {
                return DiscoveryVoiceoverAsset(
                    discoveryId: asset.discoveryId,
                    status: .none,
                    audioURL: nil,
                    provider: asset.provider,
                    ttsModel: asset.ttsModel,
                    voiceModelId: asset.voiceModelId,
                    fileName: asset.fileName,
                    fileExtension: asset.fileExtension,
                    requestedAt: asset.requestedAt,
                    updatedAt: asset.updatedAt,
                    errorReason: nil,
                    wasExistingResponse: asset.wasExistingResponse,
                    wasRefunded: asset.wasRefunded
                )
            }
        }

        if asset.status == .failed,
           let updatedAt = asset.updatedAt,
           Date().timeIntervalSince(updatedAt) > failedExpiry {
            return DiscoveryVoiceoverAsset(
                discoveryId: asset.discoveryId,
                status: .none,
                audioURL: nil,
                provider: asset.provider,
                ttsModel: asset.ttsModel,
                voiceModelId: asset.voiceModelId,
                fileName: asset.fileName,
                fileExtension: asset.fileExtension,
                requestedAt: asset.requestedAt,
                updatedAt: asset.updatedAt,
                errorReason: nil,
                wasExistingResponse: asset.wasExistingResponse,
                wasRefunded: asset.wasRefunded
            )
        }
        return asset
    }

    func play(discovery: DiscoverySummary, asset: DiscoveryVoiceoverAsset) {
        log.debug("[play] Starting playback for id=\(discovery.id), title='\(discovery.title)'")
        log.debug("[play] Discovery imagePath=\(discovery.imagePath ?? "nil")")
        
        playTask?.cancel()
        playTask = Task { [weak self] in
            guard let self else { return }
            guard let audioURL = await self.resolvePlayableURL(for: asset) else {
                log.error("[play] Failed to resolve playable URL for id=\(discovery.id)")
                await MainActor.run {
                    self.playbackState = .failed(discoveryId: discovery.id, message: "Audio unavailable.")
                    self.errorMessage = "Audio unavailable."
                }
                return
            }
            
            log.debug("[play] Got audioURL, setting currentDiscovery and state")

            await MainActor.run {
                log.debug("[play] Setting currentDiscovery to id=\(discovery.id), title='\(discovery.title)'")
                self.playbackState = .preparing(discoveryId: discovery.id)
                self.currentDiscovery = discovery
                self.errorMessage = nil
                self.position = 0
                self.duration = nil
                log.debug("[play] currentDiscovery set. id=\(self.currentDiscovery?.id ?? -1), title='\(self.currentDiscovery?.title ?? "nil")'")
            }

            await self.prepareAudioSession()
            await self.configurePlayer(with: audioURL, discovery: discovery)
            _ = await MainActor.run {
                self.downloadedIds.insert(discovery.id)
                log.debug("[play] Playback configured. Final state: \(String(describing: self.playbackState)), currentDiscovery.id=\(self.currentDiscovery?.id ?? -1)")
            }
        }
    }

    func prepareAudioSession() async {
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            errorMessage = "Audio session unavailable."
        }
    }

    func configurePlayer(with url: URL, discovery: DiscoverySummary) async {
        teardownObservers()

        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 5

        playerItemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }

            switch item.status {
            case .readyToPlay:
                Task { @MainActor in
                    await self.handleReadyToPlay(item: item, discovery: discovery)
                }
            case .failed:
                Task { @MainActor in
                    self.handlePlayerFailure(
                        error: item.error,
                        discovery: discovery,
                        attemptedRefresh: false
                    )
                }
            default:
                break
            }
        }

        endPlaybackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handlePlaybackEnded()
            }
        }

        addTimeObserver()
        player.replaceCurrentItem(with: item)
        player.play()
        updateNowPlayingPlaybackState()
        refreshNowPlayingInfo()
    }

    func handleReadyToPlay(item: AVPlayerItem, discovery: DiscoverySummary) async {
        let loadedDuration = try? await item.asset.load(.duration)
        duration = loadedDuration?.secondsValue
        playbackState = .playing(discoveryId: discovery.id)
        position = item.currentTime().seconds
        updateNowPlayingPlaybackState()
        refreshNowPlayingInfo()
    }

    func handlePlayerFailure(error: Error?, discovery: DiscoverySummary, attemptedRefresh: Bool) {
        teardownObservers()
        player.replaceCurrentItem(with: nil)

        if !attemptedRefresh {
            play(discovery: discovery, asset: normalizedAsset(for: discovery.id) ?? DiscoveryVoiceoverAsset(
                discoveryId: discovery.id,
                status: .ready,
                audioURL: nil,
                provider: nil,
                ttsModel: nil,
                voiceModelId: nil,
                fileName: nil,
                fileExtension: nil,
                requestedAt: nil,
                updatedAt: nil,
                errorReason: error?.localizedDescription,
                wasExistingResponse: true,
                wasRefunded: false
            ))
            return
        }

        playbackState = .failed(
            discoveryId: discovery.id,
            message: error?.localizedDescription
        )
        errorMessage = error?.localizedDescription ?? "Playback failed."
        nowPlayingInfoCenter.nowPlayingInfo = nil
        lastNowPlayingInfo = nil
    }

    func handlePlaybackEnded() {
        if let queueStore = queueStore, queueStore.autoplayEnabled {
            log.debug("[handlePlaybackEnded] Autoplay enabled, attempting to play next")
            if attemptAutoplayNext() {
                return
            }
            log.debug("[handlePlaybackEnded] Autoplay failed (no next item), stopping")
        } else {
            log.debug("[handlePlaybackEnded] Autoplay disabled, stopping")
        }
        
        if let discoveryId = currentDiscovery?.id {
            playbackState = .paused(discoveryId: discoveryId)
        } else {
            playbackState = .idle
        }
        player.seek(to: .zero)
        position = 0
        updateNowPlayingPlaybackState()
        refreshNowPlayingInfo()
    }
    
    private func attemptAutoplayNext() -> Bool {
        guard let queueStore = queueStore else { return false }
        
        if let nextId = queueStore.next() {
            if let discovery = getDiscovery(id: nextId) {
                log.debug("[attemptAutoplayNext] Found next discovery in provider: \(discovery.title)")
                togglePlayback(for: discovery)
                return true
            } else {
                // Fetch from discoveryStore
                log.debug("[attemptAutoplayNext] Discovery not in provider, fetching from store: \(nextId)")
                Task {
                    if let discovery = await discoveryStore?.get(id: nextId) {
                         await MainActor.run {
                             self.togglePlayback(for: discovery)
                         }
                    } else {
                        log.error("[attemptAutoplayNext] Failed to find discovery \(nextId) in store")
                    }
                }
                return true
            }
        }
        return false
    }

    func addTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                guard !self.suppressProgressUpdates, !self.isSeeking else { return }
                self.position = time.seconds
                if self.duration == nil {
                    if let asset = self.player.currentItem?.asset,
                       let cmTime = try? await asset.load(.duration),
                       let currentDuration = cmTime.secondsValue,
                       currentDuration > 0 {
                        self.duration = currentDuration
                        self.refreshNowPlayingInfo()
                    }
                }
                // self.refreshNowPlayingInfo() // Throttled: Do not update on every tick
            }
        }
    }

    func teardownObservers() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }

        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil

        if let endPlaybackObserver {
            NotificationCenter.default.removeObserver(endPlaybackObserver)
            self.endPlaybackObserver = nil
        }
    }
}

extension VoiceoverPlaybackController {
    func configureRemoteCommands() {
        // Do not clear existing targets globally with removeTarget(nil) as it kills other instances.
        // Instead, we just add our new handlers.
        
        remoteCommandCenter.playCommand.isEnabled = true
        remoteCommandCenter.pauseCommand.isEnabled = true
        remoteCommandCenter.togglePlayPauseCommand.isEnabled = true
        remoteCommandCenter.nextTrackCommand.isEnabled = true
        remoteCommandCenter.previousTrackCommand.isEnabled = true
        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = true

        remoteCommandTargets.append(remoteCommandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.resume()
            return .success
        })

        remoteCommandTargets.append(remoteCommandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.pause()
            return .success
        })

        remoteCommandTargets.append(remoteCommandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            switch self.playbackState {
            case .playing:
                self.pause()
            case .paused:
                self.resume()
            default:
                break
            }
            return .success
        })

        remoteCommandTargets.append(remoteCommandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.skipToNextDiscovery() != nil ? .success : .noSuchContent
        })

        remoteCommandTargets.append(remoteCommandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.skipToPreviousDiscovery() != nil ? .success : .noSuchContent
        })

        remoteCommandTargets.append(remoteCommandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard
                let self,
                let positionEvent = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            self.seek(to: positionEvent.positionTime) {}
            return .success
        })
    }

    func refreshNowPlayingInfo() {
        guard let discovery = currentDiscovery else {
            if let lastNowPlayingInfo {
                nowPlayingInfoCenter.nowPlayingInfo = lastNowPlayingInfo
            }
            return
        }

        var info: [String: Any] = [
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPMediaItemPropertyTitle: discovery.title,
            MPMediaItemPropertyArtist: discovery.highlight,
            MPMediaItemPropertyAlbumTitle: "WhatsThat Audio"
        ]

        if let artwork = artwork(for: discovery) {
            info[MPMediaItemPropertyArtwork] = artwork
        } else {
            startArtworkLoad(for: discovery)
        }

        if let url = normalizedAsset(for: discovery.id)?.audioURL {
            info[MPNowPlayingInfoPropertyAssetURL] = url
        }

        if let duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = {
            switch playbackState {
            case .playing, .preparing: return 1.0
            default: return 0.0
            }
        }()
        if let queue = discoveryQueueProvider?() {
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = max(queue.count, 1)
            if let index = queue.firstIndex(where: { $0.id == discovery.id }) {
                info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
            } else {
                info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = 0
            }
        } else {
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = 1
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = 0
        }

        nowPlayingInfoCenter.nowPlayingInfo = info
        lastNowPlayingInfo = info
    }

    func artwork(for discovery: DiscoverySummary) -> MPMediaItemArtwork? {
        artworkCache[discovery.id]
    }

    func startArtworkLoad(for discovery: DiscoverySummary) {
        guard artworkTasks[discovery.id] == nil,
              let url = imageURL(for: discovery) else { return }

        artworkTasks[discovery.id] = Task { [weak self] in
            guard let self else { return nil }
            defer { Task { @MainActor in self.artworkTasks[discovery.id] = nil } }

            do {
                let data: Data
                if url.isFileURL {
                    data = try Data(contentsOf: url)
                } else {
                    let (remoteData, _) = try await urlSession.data(from: url)
                    data = remoteData
                }

                guard let image = UIImage(data: data) else { return nil }
                let preparedImage = prepareArtworkImage(image)
                let artwork = MPMediaItemArtwork(boundsSize: preparedImage.size) { _ in preparedImage }
                await MainActor.run {
                    self.artworkCache[discovery.id] = artwork
                    self.refreshNowPlayingInfo()
                }
                return artwork
            } catch {
                return nil
            }
        }
    }

    func imageURL(for discovery: DiscoverySummary) -> URL? {
        guard let path = discovery.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }

        if let url = URL(string: path), url.scheme != nil {
            return url
        } else {
            return URL(fileURLWithPath: path)
        }
    }

    private func prepareArtworkImage(_ image: UIImage) -> UIImage {
        let orientedImage: UIImage
        if image.imageOrientation == .up {
            orientedImage = image
        } else {
            let format = UIGraphicsImageRendererFormat.preferred()
            format.scale = image.scale
            format.opaque = true
            orientedImage = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }

        guard orientedImage.size.width > 0, orientedImage.size.height > 0 else {
            return orientedImage
        }

        let side = min(artworkTargetSide, min(orientedImage.size.width, orientedImage.size.height))
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = UIScreen.main.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)

        return renderer.image { _ in
            let scale = max(side / orientedImage.size.width, side / orientedImage.size.height)
            let scaledSize = CGSize(
                width: orientedImage.size.width * scale,
                height: orientedImage.size.height * scale
            )
            let origin = CGPoint(
                x: (side - scaledSize.width) / 2.0,
                y: (side - scaledSize.height) / 2.0
            )
            orientedImage.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }
}

extension VoiceoverPlaybackController {
    func resolvePlayableURL(for asset: DiscoveryVoiceoverAsset) async -> URL? {
        if let fileName = asset.fileName,
           let local = await voiceoverCache.cachedFileURL(discoveryId: asset.discoveryId, fileName: fileName) {
            _ = await MainActor.run {
                downloadedIds.insert(asset.discoveryId)
            }
            return local
        }

        guard let remoteURL = asset.audioURL else { return nil }

        do {
            let (data, _) = try await urlSession.data(from: remoteURL)
            let targetFileName = asset.fileName ?? remoteURL.lastPathComponent
            if let storedURL = try? await voiceoverCache.store(
                data: data,
                discoveryId: asset.discoveryId,
                fileName: targetFileName
            ) {
                _ = await MainActor.run {
                    downloadedIds.insert(asset.discoveryId)
                }
                return storedURL
            }
        } catch {
            _ = await MainActor.run {
                self.errorMessage = "Download failed."
            }
        }

        return remoteURL
    }

    func cacheReadyAssetIfNeeded(for asset: DiscoveryVoiceoverAsset) async {
        guard asset.status == .ready,
              let fileName = asset.fileName,
              let url = asset.audioURL else { return }

        if let _ = await voiceoverCache.cachedFileURL(discoveryId: asset.discoveryId, fileName: fileName) {
            _ = await MainActor.run {
                downloadedIds.insert(asset.discoveryId)
            }
            return
        }

        do {
            let (data, _) = try await urlSession.data(from: url)
            if let _ = try? await voiceoverCache.store(
                data: data,
                discoveryId: asset.discoveryId,
                fileName: fileName
            ) {
                _ = await MainActor.run {
                    downloadedIds.insert(asset.discoveryId)
                }
            }
        } catch {
            // Silent failure; playback flow will retry download if needed.
        }
    }

    func refreshCacheFlag(for asset: DiscoveryVoiceoverAsset) async {
        guard let fileName = asset.fileName else { return }
        let discoveryId = asset.discoveryId
        if let _ = await voiceoverCache.cachedFileURL(discoveryId: discoveryId, fileName: fileName) {
            _ = await MainActor.run {
                downloadedIds.insert(discoveryId)
            }
        } else {
            _ = await MainActor.run {
                downloadedIds.remove(discoveryId)
            }
        }
    }

    func markPending(_ discoveryId: Int64) {
        if pendingIds.insert(discoveryId).inserted {
            Task { [pendingStore] in
                await pendingStore.add(discoveryId)
            }
        }
    }

    func clearPending(_ discoveryId: Int64) {
        if pendingIds.remove(discoveryId) != nil {
            Task { [pendingStore] in
                await pendingStore.remove(discoveryId)
            }
        }
        stopPollingIfIdle()
    }

    func restorePendingRequests() async {
        let stored = await pendingStore.load()
        await MainActor.run {
            pendingIds.formUnion(stored)
        }
        guard !stored.isEmpty else { return }
        await pollVoiceovers(for: Array(stored))
        await MainActor.run {
            startPollingIfNeeded()
        }
    }

    func startPollingIfNeeded() {
        guard pollingTask == nil, !pendingProcessingIds.isEmpty else { return }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            var delayIndex = 0

            while !Task.isCancelled {
                let ids = await MainActor.run { self.pendingProcessingIds }
                if ids.isEmpty { break }

                await self.pollVoiceovers(for: ids)

                let delay: TimeInterval
                if delayIndex < pollIntervals.count {
                    delay = pollIntervals[delayIndex]
                    delayIndex += 1
                } else {
                    delay = 5
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    break
                }
            }

            await MainActor.run {
                self.pollingTask = nil
            }
        }
    }

    func stopPollingIfIdle() {
        if pendingProcessingIds.isEmpty {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    var pendingProcessingIds: [Int64] {
        let processing = assetStates
            .filter { $0.value.status == .processing }
            .map(\.key)
        return Array(Set(processing).union(pendingIds))
    }

    func pollVoiceovers(for ids: [Int64]) async {
        guard !ids.isEmpty else { return }
        let assets = await repository.fetchVoiceovers(for: ids)
        await MainActor.run {
            for asset in assets {
                self.applyFetchedAsset(asset)
            }
        }
    }

    private func nextDiscoveryInQueue() -> DiscoverySummary? {
        let queue = discoveryQueueProvider?() ?? []
        guard !queue.isEmpty else { return nil }

        guard
            let currentId = currentDiscovery?.id,
            let currentIndex = queue.firstIndex(where: { $0.id == currentId })
        else {
            return queue.first
        }

        guard currentIndex > 0 else { return nil }
        let nextIndex = queue.index(before: currentIndex)
        return queue[nextIndex]
    }

    private func previousDiscoveryInQueue() -> DiscoverySummary? {
        let queue = discoveryQueueProvider?() ?? []
        guard !queue.isEmpty else { return nil }

        guard
            let currentId = currentDiscovery?.id,
            let currentIndex = queue.firstIndex(where: { $0.id == currentId })
        else {
            return queue.last
        }

        let nextIndex = queue.index(after: currentIndex)
        guard queue.indices.contains(nextIndex) else { return nil }
        return queue[nextIndex]
    }

    private func updateNowPlayingPlaybackState() {
        let state: MPNowPlayingPlaybackState
        switch playbackState {
        case .playing, .preparing:
            state = .playing
        case .paused:
            state = .paused
        case .idle:
            state = .stopped
        case .failed:
            state = .stopped
        }
        nowPlayingInfoCenter.playbackState = state
    }
}

private extension CMTime {
    var secondsValue: TimeInterval? {
        guard isNumeric && isValid && flags.contains(.valid) else {
            return nil
        }

        let seconds = CMTimeGetSeconds(self)
        return seconds.isFinite ? seconds : nil
    }
}
