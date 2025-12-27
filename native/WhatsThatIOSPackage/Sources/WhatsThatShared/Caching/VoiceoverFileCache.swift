import Foundation
import OSLog

private let voiceoverFileCacheLogger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "VoiceoverFileCache"
)

public actor VoiceoverFileCache: Sendable {
    public static let shared = VoiceoverFileCache()

    private struct Entry: Codable, Sendable {
        let discoveryId: Int64
        var fileName: String
        var fileSize: Int64
        var lastAccessedAt: Date
    }

    public struct VoiceoverCacheEntry: Identifiable, Sendable {
        public var id: Int64 { discoveryId }
        public let discoveryId: Int64
        public let fileName: String
        public let fileSize: Int64
        public let lastAccessedAt: Date
    }

    private let fileManager: FileManager
    private let cacheDirectoryURL: URL
    private let metadataURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let maxBytes: Int64

    private var entries: [Int64: Entry] = [:]
    private let log = voiceoverFileCacheLogger
    
    /// Tracks in-flight download tasks to prevent duplicate downloads for the same discoveryId
    private var inFlightDownloads: [Int64: Task<URL?, Error>] = [:]

    public init(
        cachesDirectory: URL? = nil,
        maxBytes: Int64 = 150 * 1024 * 1024
    ) {
        let fm = FileManager.default
        let cachesDirectory = cachesDirectory ??
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory())

        let cacheDirURL = cachesDirectory.appendingPathComponent("Voiceovers", isDirectory: true)
        let metadataURL = cacheDirURL.appendingPathComponent("metadata.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self.fileManager = fm
        self.cacheDirectoryURL = cacheDirURL
        self.metadataURL = metadataURL
        self.encoder = encoder
        self.decoder = decoder
        self.maxBytes = maxBytes

        do {
            if !fm.fileExists(atPath: cacheDirURL.path) {
                try fm.createDirectory(at: cacheDirURL, withIntermediateDirectories: true, attributes: nil)
                log.info("Created voiceover cache directory at \(cacheDirURL.path, privacy: .public)")
            } else {
                log.debug("Voiceover cache directory exists at \(cacheDirURL.path, privacy: .public)")
            }

            if fm.fileExists(atPath: metadataURL.path) {
                let data = try Data(contentsOf: metadataURL)
                let decoded = try decoder.decode([Int64: Entry].self, from: data)
                entries = decoded
                log.info("Loaded voiceover cache metadata with \(decoded.count, privacy: .public) entries")
            } else {
                entries = [:]
                log.debug("No cache metadata found; starting empty cache")
            }
        } catch {
            log.error("Failed to initialise cache: \(error.localizedDescription, privacy: .public)")
            self.entries = [:]
        }
    }
}

// MARK: - Public API

public extension VoiceoverFileCache {
    func cachedFileURL(discoveryId: Int64, fileName: String) async -> URL? {
        let expectedPath = "\(discoveryId)/\(fileName)"
        let fileURL = cacheDirectoryURL.appendingPathComponent(expectedPath)

        // If entry exists and matches expected path, verify existence.
        if var entry = entries[discoveryId], entry.fileName == expectedPath {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                log.notice("Cache miss: file missing on disk for discovery \(discoveryId, privacy: .public) at \(fileURL.path, privacy: .public)")
                entries.removeValue(forKey: discoveryId)
                persistMetadata()
                return nil
            }
            entry.lastAccessedAt = Date()
            entries[discoveryId] = entry
            persistMetadata()
            log.debug("Cache hit for discovery \(discoveryId, privacy: .public) at \(fileURL.lastPathComponent, privacy: .public)")
            return fileURL
        }

        // If entry missing or path mismatch and no file on disk, treat as a miss.
        log.debug("Cache miss: no entry for discovery \(discoveryId, privacy: .public) expected \(expectedPath, privacy: .public)")
        return nil
    }

    func store(
        data: Data,
        discoveryId: Int64,
        fileName: String
    ) async throws -> URL {
        let dirURL = cacheDirectoryURL.appendingPathComponent("\(discoveryId)", isDirectory: true)
        if !fileManager.fileExists(atPath: dirURL.path) {
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        }

        let relativePath = "\(discoveryId)/\(fileName)"
        let fileURL = cacheDirectoryURL.appendingPathComponent(relativePath)

        // Remove existing file for this discovery to avoid stale bytes.
        if let existing = entries[discoveryId] {
            let existingURL = cacheDirectoryURL.appendingPathComponent(existing.fileName)
            try? fileManager.removeItem(at: existingURL)
            log.debug("Removed existing cached file for discovery \(discoveryId, privacy: .public) at \(existingURL.lastPathComponent, privacy: .public)")
        }

        try data.write(to: fileURL, options: .atomic)
        log.info("Stored voiceover for discovery \(discoveryId, privacy: .public) as \(fileName, privacy: .public) size=\(data.count, privacy: .public) bytes")

        let entry = Entry(
            discoveryId: discoveryId,
            fileName: relativePath,
            fileSize: Int64(data.count),
            lastAccessedAt: Date()
        )
        entries[discoveryId] = entry
        persistMetadata()
        try evictIfNeeded()
        return fileURL
    }

    func listEntries() -> [VoiceoverCacheEntry] {
        entries.values
            .map {
                VoiceoverCacheEntry(
                    discoveryId: $0.discoveryId,
                    fileName: $0.fileName,
                    fileSize: $0.fileSize,
                    lastAccessedAt: $0.lastAccessedAt
                )
            }
            .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
    }

    func remove(discoveryId: Int64) {
        guard let entry = entries[discoveryId] else { return }
        let fileURL = cacheDirectoryURL.appendingPathComponent(entry.fileName)
        try? fileManager.removeItem(at: fileURL)
        entries.removeValue(forKey: discoveryId)
        persistMetadata()
        log.debug("Removed cached voiceover for discovery \(discoveryId, privacy: .public)")
    }

    func clearAll() {
        for entry in entries.values {
            let fileURL = cacheDirectoryURL.appendingPathComponent(entry.fileName)
            try? fileManager.removeItem(at: fileURL)
        }
        entries.removeAll()
        persistMetadata()
        log.notice("Cleared all cached voiceovers")
    }
    
    // MARK: - In-Flight Download Tracking
    
    /// Downloads and caches a voiceover file, coalescing concurrent requests.
    /// If a download is already in flight for this discoveryId, returns the existing task's result.
    func downloadAndCache(
        discoveryId: Int64,
        fileName: String,
        downloadURL: URL,
        urlSession: URLSession = .shared
    ) async throws -> URL? {
        // Return existing in-flight task if present
        if let existingTask = inFlightDownloads[discoveryId] {
            log.debug("Coalescing download for discovery \(discoveryId, privacy: .public)")
            return try await existingTask.value
        }
        
        // Check cache first
        if let cached = await cachedFileURL(discoveryId: discoveryId, fileName: fileName) {
            return cached
        }
        
        // Create new download task
        let task = Task<URL?, Error> { [weak self] in
            guard let self else { return nil }
            defer { 
                Task { await self.removeInFlightDownload(for: discoveryId) }
            }
            
            let (data, response) = try await urlSession.data(from: downloadURL)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            return try await self.store(data: data, discoveryId: discoveryId, fileName: fileName)
        }
        
        inFlightDownloads[discoveryId] = task
        return try await task.value
    }
    
    private func removeInFlightDownload(for discoveryId: Int64) {
        inFlightDownloads.removeValue(forKey: discoveryId)
    }
    
    /// Cancels an in-flight download if one exists
    func cancelDownload(for discoveryId: Int64) {
        inFlightDownloads[discoveryId]?.cancel()
        inFlightDownloads.removeValue(forKey: discoveryId)
        log.debug("Cancelled download for discovery \(discoveryId, privacy: .public)")
    }
    
    /// Returns true if a download is in progress for this discoveryId
    func isDownloading(_ discoveryId: Int64) -> Bool {
        inFlightDownloads[discoveryId] != nil
    }
}

// MARK: - Internal helpers

private extension VoiceoverFileCache {
    func totalBytes() -> Int64 {
        entries.values.reduce(0) { $0 + $1.fileSize }
    }

    func evictIfNeeded() throws {
        var currentSize = totalBytes()
        guard currentSize > maxBytes else { return }

        let sorted = entries.values.sorted { $0.lastAccessedAt < $1.lastAccessedAt }
        for entry in sorted {
            let fileURL = cacheDirectoryURL.appendingPathComponent(entry.fileName)
            try? fileManager.removeItem(at: fileURL)
            entries.removeValue(forKey: entry.discoveryId)
            log.notice("Evicted cached voiceover for discovery \(entry.discoveryId, privacy: .public)")
            currentSize = totalBytes()
            if currentSize <= maxBytes {
                break
            }
        }
        persistMetadata()
    }

    func persistMetadata() {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            voiceoverFileCacheLogger.error("Failed to persist cache metadata: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - UserDataClearable

extension VoiceoverFileCache: UserDataClearable {
    public func clearUserData() async {
        clearAll()
    }
}
