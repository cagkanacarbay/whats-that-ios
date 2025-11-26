import Foundation
import SwiftUI
import AVFoundation
import WhatsThatDomain

public enum VoiceSampleState: Equatable {
    case idle
    case loading
    case ready
    case failed
    
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
    
    var isLoading: Bool {
        if case .loading = self { return true }
        if case .idle = self { return true }
        return false
    }
}

@MainActor
public class VoicePickerViewModel: ObservableObject {
    @Published public var voices: [VoiceModelOption] = []
    @Published public var selectedVoiceId: String?
    @Published public var isAutoEnabled: Bool = true
    @Published public var isPlaying: Bool = false
    @Published public private(set) var sampleStates: [String: VoiceSampleState] = [:]
    @Published public private(set) var playingVoiceId: String?
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: Any?
    
    private var hasLoadedVoices = false
    private var hasStartedPrefetch = false
    private var cachedSampleURLs: [String: URL] = [:]
    private var downloadTasks: [String: Task<URL?, Never>] = [:]
    
    private let loadVoiceoverPreferences: () async -> VoiceoverPreferences
    private let saveVoiceoverPreferences: (VoiceoverPreferences) async -> Void
    private let fetchVoiceOptions: () async -> [VoiceModelOption]
    private let fetchVoiceSampleURL: (String) async -> URL?
    private let urlSession: URLSession
    private let fileManager: FileManager
    
    public init(
        loadVoiceoverPreferences: @escaping () async -> VoiceoverPreferences,
        saveVoiceoverPreferences: @escaping (VoiceoverPreferences) async -> Void,
        fetchVoiceOptions: @escaping () async -> [VoiceModelOption],
        fetchVoiceSampleURL: @escaping (String) async -> URL?,
        urlSession: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.loadVoiceoverPreferences = loadVoiceoverPreferences
        self.saveVoiceoverPreferences = saveVoiceoverPreferences
        self.fetchVoiceOptions = fetchVoiceOptions
        self.fetchVoiceSampleURL = fetchVoiceSampleURL
        self.urlSession = urlSession
        self.fileManager = fileManager
    }
    
    /// Kept for existing call sites; ensures voices are loaded and samples start prefetching.
    public func load() async {
        await ensureLoadedForDisplay()
    }
    
    public func ensureLoadedForDisplay() async {
        await loadVoicesIfNeeded()
        await prefetchSamplesIfNeeded()
    }
    
    public func prepareForOnboardingPrefetch() async {
        await loadVoicesIfNeeded()
        await prefetchSamplesIfNeeded()
    }
    
    public func autoplaySelectedVoice() async {
        guard let selectedVoiceId else { return }
        await startPlaybackFlow(for: selectedVoiceId)
    }
    
    public func handleVoiceTap(id: String) {
        if selectedVoiceId == id {
            if isPlaying {
                stop()
            } else {
                Task { await startPlaybackFlow(for: id) }
            }
            return
        }
        
        selectedVoiceId = id
        Task {
            await saveCurrentPreferences()
            await startPlaybackFlow(for: id)
        }
    }
    
    public func toggleAutoPlay() {
        isAutoEnabled.toggle()
        Task {
            await saveCurrentPreferences()
        }
    }
    
    public func stop() {
        player?.pause()
        player = nil
        playerItem = nil
        statusObserver?.invalidate()
        statusObserver = nil
        
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        
        isPlaying = false
        playingVoiceId = nil
    }
    
    // MARK: - Private helpers
    
    private func loadVoicesIfNeeded() async {
        guard !hasLoadedVoices else { return }
        
        let options = await fetchVoiceOptions()
        
        let sortOrder = ["Adrian", "Laura", "Ethan", "Sarah"]
        voices = options.sorted { v1, v2 in
            let index1 = sortOrder.firstIndex(of: v1.displayName) ?? Int.max
            let index2 = sortOrder.firstIndex(of: v2.displayName) ?? Int.max
            
            if index1 != index2 {
                return index1 < index2
            }
            return v1.displayName < v2.displayName
        }
        
        sampleStates = voices.reduce(into: [:]) { partialResult, voice in
            partialResult[voice.voiceModelId] = .idle
        }
        
        let prefs = await loadVoiceoverPreferences()
        isAutoEnabled = prefs.autoEnabled
        
        if !prefs.voiceModelId.isEmpty, voices.contains(where: { $0.voiceModelId == prefs.voiceModelId }) {
            selectedVoiceId = prefs.voiceModelId
        } else if let first = voices.first {
            selectedVoiceId = first.voiceModelId
            await saveCurrentPreferences()
        }
        
        hasLoadedVoices = true
    }
    
    private func prefetchSamplesIfNeeded() async {
        guard !hasStartedPrefetch else { return }
        hasStartedPrefetch = true
        
        await withTaskGroup(of: Void.self) { group in
            for voice in voices {
                group.addTask { [weak self] in
                    guard let self else { return }
                    _ = await self.ensureSample(for: voice.voiceModelId)
                }
            }
        }
    }
    
    private func startPlaybackFlow(for voiceId: String) async {
        guard let url = await ensureSample(for: voiceId) else { return }
        
        // Avoid restarting if already playing the same voice
        if isPlaying, playingVoiceId == voiceId {
            return
        }
        
        play(url: url, voiceId: voiceId)
    }
    
    private func ensureSample(for voiceId: String) async -> URL? {
        if let existing = cachedSampleURLs[voiceId], fileManager.fileExists(atPath: existing.path) {
            sampleStates[voiceId] = .ready
            return existing
        }
        
        if let existingTask = downloadTasks[voiceId] {
            return await existingTask.value
        }
        
        guard let voice = voices.first(where: { $0.voiceModelId == voiceId }) else {
            return nil
        }
        
        sampleStates[voiceId] = .loading
        
        let task = Task { [weak self] () -> URL? in
            guard let self else { return nil }
            return await self.downloadSample(for: voice)
        }
        downloadTasks[voiceId] = task
        
        let url = await task.value
        downloadTasks[voiceId] = nil
        
        if let url {
            cachedSampleURLs[voiceId] = url
            sampleStates[voiceId] = .ready
        } else {
            sampleStates[voiceId] = .failed
        }
        
        return url
    }
    
    private func downloadSample(for voice: VoiceModelOption) async -> URL? {
        let cacheURL = sampleCacheURL(for: voice)
        if fileManager.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }
        
        guard let remoteURL = await fetchVoiceSampleURL(voice.displayName) else {
            return nil
        }
        
        do {
            let (data, _) = try await urlSession.data(from: remoteURL)
            try fileManager.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
            return cacheURL
        } catch {
            return nil
        }
    }
    
    private func play(url: URL, voiceId: String) {
        stop()
        
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        playerItem = item
        
        statusObserver = item.observe(\.status, options: [.new, .old]) { [weak self] item, _ in
            guard let self else { return }
            if item.status == .failed {
                Task { @MainActor in
                    self.isPlaying = false
                    self.playingVoiceId = nil
                }
            }
        }
        
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.playingVoiceId = nil
            }
        }
        
        player?.play()
        isPlaying = true
        playingVoiceId = voiceId
    }
    
    private func sampleCacheURL(for voice: VoiceModelOption) -> URL {
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let sanitizedName = voice.displayName.replacingOccurrences(of: " ", with: "_")
        return cachesDir
            .appendingPathComponent("voice_samples", isDirectory: true)
            .appendingPathComponent("\(sanitizedName).mp3")
    }
    
    private func saveCurrentPreferences() async {
        guard let selectedVoiceId,
              let voice = voices.first(where: { $0.voiceModelId == selectedVoiceId }) else { return }
        
        let prefs = VoiceoverPreferences(
            autoEnabled: isAutoEnabled,
            voiceModelId: voice.voiceModelId,
            ttsModel: voice.ttsModel
        )
        await saveVoiceoverPreferences(prefs)
    }
}
