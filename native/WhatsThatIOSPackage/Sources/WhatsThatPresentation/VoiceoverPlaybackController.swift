import AVFoundation
import Foundation
import SwiftUI
import WhatsThatDomain

@MainActor
public final class VoiceoverPlaybackController: ObservableObject {
    public enum PlaybackState: Equatable {
        case idle
        case loading(discoveryId: Int64)
        case playing(discoveryId: Int64)
        case paused(discoveryId: Int64)
        case unavailable(discoveryId: Int64)
        case failed(discoveryId: Int64, message: String?)

        public var discoveryId: Int64? {
            switch self {
            case .idle:
                return nil
            case let .loading(id),
                 let .playing(id),
                 let .paused(id),
                 let .unavailable(id):
                return id
            case let .failed(id, _):
                return id
            }
        }

        public var isActive: Bool {
            switch self {
            case .playing, .paused:
                return true
            case .loading, .unavailable, .failed, .idle:
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
    @Published public var isDetailOverlayActive: Bool = false

    private let repository: any DiscoveryVoiceoverRepository
    private let audioSession: AVAudioSession
    private let player: AVPlayer
    private var timeObserverToken: Any?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var endPlaybackObserver: NSObjectProtocol?
    private var playTask: Task<Void, Never>?

    public init(
        repository: any DiscoveryVoiceoverRepository,
        audioSession: AVAudioSession = .sharedInstance(),
        player: AVPlayer = AVPlayer()
    ) {
        self.repository = repository
        self.audioSession = audioSession
        self.player = player
    }

    deinit {
        let player = player
        let token = timeObserverToken
        let observation = playerItemStatusObservation
        let observer = endPlaybackObserver

        let cleanup = {
            if let token {
                player.removeTimeObserver(token)
            }
            observation?.invalidate()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        if Thread.isMainThread {
            cleanup()
        } else {
            DispatchQueue.main.async(execute: cleanup)
        }
    }
}

// MARK: - Public API

public extension VoiceoverPlaybackController {
    func ensureMetadata(for discovery: DiscoverySummary, force: Bool = false) {
        Task { [weak self] in
            guard let self else { return }
            let asset = await self.repository.ensureVoiceoverAsset(
                for: discovery.id,
                options: DiscoveryVoiceoverRequestOptions(forceRefresh: force)
            )
            await MainActor.run {
                self.assetStates[discovery.id] = asset
            }
        }
    }

    func togglePlayback(for discovery: DiscoverySummary) {
        switch playbackState {
        case let .playing(currentId) where currentId == discovery.id:
            pause()
        case let .paused(currentId) where currentId == discovery.id:
            resume()
        default:
            play(discovery: discovery, forceRefresh: false)
        }
    }

    func play(discovery: DiscoverySummary, forceRefresh: Bool) {
        playTask?.cancel()
        playTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.playbackState = .loading(discoveryId: discovery.id)
                self.currentDiscovery = discovery
                self.errorMessage = nil
                self.position = 0
                self.duration = nil
            }

            if forceRefresh {
                await MainActor.run {
                    self.assetStates[discovery.id] = nil
                }
            }

            let asset = await self.repository.ensureVoiceoverAsset(
                for: discovery.id,
                options: DiscoveryVoiceoverRequestOptions(forceRefresh: forceRefresh)
            )

            await MainActor.run {
                self.assetStates[discovery.id] = asset
            }

            guard asset.status == .available, let audioURL = asset.audioURL else {
                await MainActor.run {
                    switch asset.status {
                    case .missing:
                        self.playbackState = .unavailable(discoveryId: discovery.id)
                        self.errorMessage = "Narration is not available yet."
                    case .error:
                        self.playbackState = .failed(discoveryId: discovery.id, message: asset.errorDescription)
                        self.errorMessage = asset.errorDescription ?? "Failed to load narration."
                    default:
                        self.playbackState = .unavailable(discoveryId: discovery.id)
                    }
                }
                return
            }

            await self.prepareAudioSession()
            await self.configurePlayer(with: audioURL, discovery: discovery)
        }
    }

    func pause() {
        player.pause()
        if case let .playing(id) = playbackState {
            playbackState = .paused(discoveryId: id)
        }
    }

    func resume() {
        guard case let .paused(id) = playbackState else {
            return
        }

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

    func seek(to seconds: TimeInterval) {
        guard let duration, duration > 0 else {
            return
        }

        let clamped = max(0, min(seconds, duration))
        let time = CMTime(seconds: clamped, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        position = clamped
    }

    func isLoading(discoveryId: Int64) -> Bool {
        if case let .loading(id) = playbackState, id == discoveryId {
            return true
        }
        return false
    }

    func isActive(discoveryId: Int64) -> Bool {
        if case let .playing(id) = playbackState, id == discoveryId {
            return true
        }
        if case let .paused(id) = playbackState, id == discoveryId {
            return true
        }
        return false
    }
}

// MARK: - Private helpers

private extension VoiceoverPlaybackController {
    func prepareAudioSession() async {
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.interruptSpokenAudioAndMixWithOthers])
            try audioSession.setActive(true)
        } catch {
            // Session failures should not block playback; surface as warning.
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
                    self.handleReadyToPlay(item: item, discovery: discovery)
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

    func handleReadyToPlay(item: AVPlayerItem, discovery: DiscoverySummary) {
        duration = item.asset.duration.secondsValue
        playbackState = .playing(discoveryId: discovery.id)
        position = item.currentTime().seconds
    }

    func handlePlayerFailure(error: Error?, discovery: DiscoverySummary, attemptedRefresh: Bool) {
        teardownObservers()
        player.replaceCurrentItem(with: nil)

        if !attemptedRefresh {
            play(discovery: discovery, forceRefresh: true)
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
                self.position = time.seconds
                if self.duration == nil {
                    if let currentDuration = self.player.currentItem?.duration.secondsValue, currentDuration > 0 {
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

    public func seek(to _: TimeInterval) {}
    public func isLoading(discoveryId _: Int64) -> Bool { false }
    public func isActive(discoveryId _: Int64) -> Bool { false }

    public struct StubRepository: DiscoveryVoiceoverRepository {
        public init() {}

        public func ensureVoiceoverAsset(
            for discoveryId: Int64,
            options _: DiscoveryVoiceoverRequestOptions
        ) async -> DiscoveryVoiceoverAsset {
            DiscoveryVoiceoverAsset(
                discoveryId: discoveryId,
                status: .missing,
                audioURL: nil,
                modelIdentifier: nil,
                fetchedAt: Date()
            )
        }
    }

