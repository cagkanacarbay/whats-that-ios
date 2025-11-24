import AVFoundation
import Foundation
import SwiftUI
import WhatsThatDomain
import WhatsThatShared

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
    private let pendingStore: VoiceoverPendingStore
    private var timeObserverToken: Any?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var endPlaybackObserver: NSObjectProtocol?
    private var playTask: Task<Void, Never>?
    private var isSeeking = false
    private let failedExpiry: TimeInterval = 60 * 60
    private let processingStaleThreshold: TimeInterval = 60 * 5

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
        pendingStore: VoiceoverPendingStore = .shared
    ) {
        self.repository = repository
        self.voiceoverCache = voiceoverCache
        self.activePreferences = preferences
        self.preferencesStore = preferencesStore
        self.audioSession = audioSession
        self.player = player
        self.urlSession = urlSession
        self.pendingStore = pendingStore

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
        pollingTask?.cancel()
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

    func togglePlayback(for discovery: DiscoverySummary, preferences: VoiceoverPreferences? = nil) {
        let asset = normalizedAsset(for: discovery.id)
        let resolvedPreferences = preferences ?? activePreferences

        switch asset?.status {
        case .ready?:
            if case let .playing(id) = playbackState, id == discovery.id {
                pause()
                return
            }
            if case let .paused(id) = playbackState, id == discovery.id {
                resume()
                return
            }
            guard let readyAsset = asset else { return }
            play(discovery: discovery, asset: readyAsset)
        case .processing?:
            playbackState = .preparing(discoveryId: discovery.id)
        case .failed?, .none?, .missing?:
            requestVoiceover(for: discovery, preferences: resolvedPreferences)
        case nil:
            requestVoiceover(for: discovery, preferences: resolvedPreferences)
        }
    }

    func setCurrentDiscovery(_ discovery: DiscoverySummary) {
        currentDiscovery = discovery
    }

    func requestVoiceover(for discovery: DiscoverySummary, preferences: VoiceoverPreferences? = nil) {
        Task { [weak self] in
            guard let self else { return }
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

            guard !resolvedPreferences.voiceModelId.isEmpty else {
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
                self.currentDiscovery = discovery
                self.playbackState = .preparing(discoveryId: discovery.id)
            }
            markPending(discovery.id)
            startPollingIfNeeded()

            let asset = await self.repository.requestVoiceover(
                for: discovery.id,
                voiceModelId: resolvedPreferences.voiceModelId,
                ttsModel: resolvedPreferences.ttsModel
            )

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

            if normalized.status == .ready, let audioURL = normalized.audioURL {
                clearPending(discovery.id)
                await prepareAudioSession()
                await configurePlayer(with: audioURL, discovery: discovery)
            } else if normalized.status == .failed {
                clearPending(discovery.id)
                await MainActor.run {
                    self.playbackState = .failed(discoveryId: discovery.id, message: normalized.errorReason)
                    self.errorMessage = normalized.errorReason
                }
            } else {
                await MainActor.run {
                    self.playbackState = .idle
                }
            }
        }
    }

    func pause() {
        player.pause()
        if case let .playing(id) = playbackState {
            playbackState = .paused(discoveryId: id)
        }
    }

    func resume() {
        guard case let .paused(id) = playbackState else { return }
        player.play()
        playbackState = .playing(discoveryId: id)
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
    }

    func seek(to seconds: TimeInterval, completion: (() -> Void)? = nil) {
        guard let duration, duration > 0 else {
            completion?()
            return
        }

        let clamped = max(0, min(seconds, duration))
        let time = CMTime(seconds: clamped, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        isSeeking = true
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
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
        playTask?.cancel()
        playTask = Task { [weak self] in
            guard let self else { return }
            guard let audioURL = await self.resolvePlayableURL(for: asset) else {
                await MainActor.run {
                    self.playbackState = .failed(discoveryId: discovery.id, message: "Audio unavailable.")
                    self.errorMessage = "Audio unavailable."
                }
                return
            }

            await MainActor.run {
                self.playbackState = .preparing(discoveryId: discovery.id)
                self.currentDiscovery = discovery
                self.errorMessage = nil
                self.position = 0
                self.duration = nil
            }

            await self.prepareAudioSession()
            await self.configurePlayer(with: audioURL, discovery: discovery)
            _ = await MainActor.run {
                self.downloadedIds.insert(discovery.id)
            }
        }
    }

    func prepareAudioSession() async {
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.interruptSpokenAudioAndMixWithOthers])
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
    }

    func handleReadyToPlay(item: AVPlayerItem, discovery: DiscoverySummary) async {
        let loadedDuration = try? await item.asset.load(.duration)
        duration = loadedDuration?.secondsValue
        playbackState = .playing(discoveryId: discovery.id)
        position = item.currentTime().seconds
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
    }

    func handlePlaybackEnded() {
        if let discoveryId = currentDiscovery?.id {
            playbackState = .paused(discoveryId: discoveryId)
        } else {
            playbackState = .idle
        }
        player.seek(to: .zero)
        position = 0
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
                    }
                }
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
