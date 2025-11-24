import AVFoundation
import Foundation
import SwiftUI
import WhatsThatDomain

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

    private let repository: any DiscoveryVoiceoverRepository
    private let preferencesStore: VoiceoverPreferencesStore?
    private let audioSession: AVAudioSession
    private let player: AVPlayer
    private var timeObserverToken: Any?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var endPlaybackObserver: NSObjectProtocol?
    private var playTask: Task<Void, Never>?
    private var isSeeking = false
    private var downloadedIds: Set<Int64> = []
    private let failedExpiry: TimeInterval = 60 * 60
    private let processingStaleThreshold: TimeInterval = 60 * 5

    public init(
        repository: any DiscoveryVoiceoverRepository,
        preferences: VoiceoverPreferences = VoiceoverPreferences(
            autoEnabled: false,
            voiceModelId: "",
            ttsModel: "s1",
            prosody: VoiceoverProsody(speed: 1.0, volume: 0.0)
        ),
        preferencesStore: VoiceoverPreferencesStore? = nil,
        audioSession: AVAudioSession = .sharedInstance(),
        player: AVPlayer = AVPlayer()
    ) {
        self.repository = repository
        self.activePreferences = preferences
        self.preferencesStore = preferencesStore
        self.audioSession = audioSession
        self.player = player
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        playerItemStatusObservation?.invalidate()
        if let observer = endPlaybackObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
                    if let existing = self.assetStates[asset.discoveryId] {
                        // Keep a ready asset if the incoming one is older or not ready.
                        if existing.status == .ready {
                            if normalized.status != .ready || normalized.audioURL == nil {
                                continue
                            }
                            if let existingUpdated = existing.updatedAt,
                               let incomingUpdated = normalized.updatedAt,
                               incomingUpdated < existingUpdated {
                                continue
                            }
                        }
                    }
                    self.assetStates[asset.discoveryId] = normalized
                }
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

            let asset = await self.repository.requestVoiceover(
                for: discovery.id,
                voiceModelId: resolvedPreferences.voiceModelId,
                ttsModel: resolvedPreferences.ttsModel,
                prosody: resolvedPreferences.prosody
            )

            let normalized = normalize(asset)
            await MainActor.run {
                self.assetStates[discovery.id] = normalized
            }

            if normalized.status == .failed && normalized.wasExistingResponse {
                self.prefetch(for: [discovery.id])
            }

            if normalized.status == .ready, let audioURL = normalized.audioURL {
                await prepareAudioSession()
                await configurePlayer(with: audioURL, discovery: discovery)
            } else if normalized.status == .failed {
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

    public func normalize(_ asset: DiscoveryVoiceoverAsset) -> DiscoveryVoiceoverAsset {
        if asset.status == .processing {
            let lastUpdate = asset.updatedAt ?? asset.requestedAt
            if let lastUpdate {
                let age = Date().timeIntervalSince(lastUpdate)
                print("Voiceover normalize: processing age=\(age) discoveryId=\(asset.discoveryId)")
            } else {
                print("Voiceover normalize: processing with missing timestamps discoveryId=\(asset.discoveryId)")
            }
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
            guard let audioURL = asset.audioURL else {
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

private extension CMTime {
    var secondsValue: TimeInterval? {
        guard isNumeric && isValid && flags.contains(.valid) else {
            return nil
        }

        let seconds = CMTimeGetSeconds(self)
        return seconds.isFinite ? seconds : nil
    }
}
