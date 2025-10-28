import Foundation
import OSLog

private let discoveryAssetCacheLogger = Logger(
    subsystem: "com.example.whatsthatios",
    category: "DiscoveryAssetCache"
)

public actor DiscoveryAssetCache: Sendable {
    public static let shared = DiscoveryAssetCache()

    public struct Entry: Codable, Sendable {
        public let discoveryId: Int64
        public var storagePath: String
        public var signedURL: String
        public var expiresAt: Date
        public var imageFileName: String?
        public var lastAccessedAt: Date

        public init(
            discoveryId: Int64,
            storagePath: String,
            signedURL: String,
            expiresAt: Date,
            imageFileName: String?,
            lastAccessedAt: Date
        ) {
            self.discoveryId = discoveryId
            self.storagePath = storagePath
            self.signedURL = signedURL
            self.expiresAt = expiresAt
            self.imageFileName = imageFileName
            self.lastAccessedAt = lastAccessedAt
        }
    }

    private let fileManager: FileManager
    private let cacheDirectoryURL: URL
    private let metadataURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var entries: [Int64: Entry] = [:]

    public init() {
        // Create FileManager instance inside the actor to avoid passing a non-Sendable across isolation.
        self.fileManager = FileManager.default

        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectoryURL = cachesDirectory.appendingPathComponent("DiscoveryAssets", isDirectory: true)
        self.metadataURL = cacheDirectoryURL.appendingPathComponent("metadata.json")

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        // Inline setup to avoid calling actor-isolated methods from a nonisolated initializer context.
        do {
            if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
                try fileManager.createDirectory(
                    at: cacheDirectoryURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }

            if fileManager.fileExists(atPath: metadataURL.path) {
                let data = try Data(contentsOf: metadataURL)
                let decoded = try decoder.decode([Int64: Entry].self, from: data)
                entries = decoded
            }
        } catch {
            discoveryAssetCacheLogger.error("Failed to initialise cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    public init(cachesDirectory: URL) {
        // Create FileManager instance inside the actor to avoid passing a non-Sendable across isolation.
        self.fileManager = FileManager.default

        self.cacheDirectoryURL = cachesDirectory.appendingPathComponent("DiscoveryAssets", isDirectory: true)
        self.metadataURL = cacheDirectoryURL.appendingPathComponent("metadata.json")

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        // Inline setup to avoid calling actor-isolated methods from a nonisolated initializer context.
        do {
            if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
                try fileManager.createDirectory(
                    at: cacheDirectoryURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }

            if fileManager.fileExists(atPath: metadataURL.path) {
                let data = try Data(contentsOf: metadataURL)
                let decoded = try decoder.decode([Int64: Entry].self, from: data)
                entries = decoded
            }
        } catch {
            discoveryAssetCacheLogger.error("Failed to initialise cache: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Signed URL Caching

public extension DiscoveryAssetCache {
    func cachedSignedURL(
        for discoveryId: Int64,
        storagePath: String,
        tolerance: TimeInterval = 60
    ) -> URL? {
        guard var entry = entries[discoveryId] else {
            return nil
        }

        guard entry.storagePath == storagePath else {
            // Storage path changed; invalidate cached data.
            removeImageFile(for: entry)
            entries.removeValue(forKey: discoveryId)
            persistMetadata()
            return nil
        }

        let now = Date()
        guard entry.expiresAt.timeIntervalSince(now) > tolerance else {
            // Expired or about to expire.
            entries[discoveryId] = entry
            persistMetadata()
            return nil
        }

        entry.lastAccessedAt = now
        entries[discoveryId] = entry
        persistMetadata()

        return URL(string: entry.signedURL)
    }

    func storeSignedURL(
        _ url: URL,
        expiresAt: Date,
        discoveryId: Int64,
        storagePath: String
    ) {
        if var existing = entries[discoveryId] {
            if existing.storagePath != storagePath {
                removeImageFile(for: existing)
                existing.imageFileName = nil
            }

            existing.storagePath = storagePath
            existing.signedURL = url.absoluteString
            existing.expiresAt = expiresAt
            existing.lastAccessedAt = Date()
            entries[discoveryId] = existing
        } else {
            let newEntry = Entry(
                discoveryId: discoveryId,
                storagePath: storagePath,
                signedURL: url.absoluteString,
                expiresAt: expiresAt,
                imageFileName: nil,
                lastAccessedAt: Date()
            )
            entries[discoveryId] = newEntry
        }

        persistMetadata()
    }

    func invalidateSignedURL(for discoveryId: Int64) {
        guard let entry = entries[discoveryId] else {
            return
        }
        removeImageFile(for: entry)
        entries.removeValue(forKey: discoveryId)
        persistMetadata()
    }
}

// MARK: - Image Caching

public extension DiscoveryAssetCache {
    func cachedImageURL(for discoveryId: Int64) -> URL? {
        guard var entry = entries[discoveryId], let fileName = entry.imageFileName else {
            return nil
        }

        let fileURL = cacheDirectoryURL.appendingPathComponent(fileName)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            entry.imageFileName = nil
            entries[discoveryId] = entry
            persistMetadata()
            return nil
        }

        entry.lastAccessedAt = Date()
        entries[discoveryId] = entry
        persistMetadata()

        return fileURL
    }

    @discardableResult
    func storeImageData(_ data: Data, discoveryId: Int64) -> URL? {
        guard var entry = entries[discoveryId] else {
            discoveryAssetCacheLogger.warning("Attempted to store image for unknown discovery \(discoveryId, privacy: .public)")
            return nil
        }

        do {
            try makeDirectoriesIfNeeded()
            if let currentFileName = entry.imageFileName {
                let existingURL = cacheDirectoryURL.appendingPathComponent(currentFileName)
                try? fileManager.removeItem(at: existingURL)
            }

            let fileName = "\(discoveryId)-\(UUID().uuidString).img"
            let fileURL = cacheDirectoryURL.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: .atomic)

            entry.imageFileName = fileName
            entry.lastAccessedAt = Date()
            entries[discoveryId] = entry
            persistMetadata()
            return fileURL
        } catch {
            discoveryAssetCacheLogger.error("Failed to store image data: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func ensureImageCached(
        for discoveryId: Int64,
        signedURL: URL,
        session: URLSession = .shared
    ) async -> URL? {
        if let existing = cachedImageURL(for: discoveryId) {
            return existing
        }

        do {
            let (data, response) = try await session.data(from: signedURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode) else {
                discoveryAssetCacheLogger.error("Unexpected response while caching image for \(discoveryId, privacy: .public)")
                return nil
            }

            return storeImageData(data, discoveryId: discoveryId)
        } catch {
            discoveryAssetCacheLogger.error("Failed to download image for \(discoveryId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

// MARK: - Maintenance

public extension DiscoveryAssetCache {
    func purgeExpiredEntries(referenceDate: Date = .init()) {
        var didMutate = false
        for (key, entry) in entries {
            if entry.expiresAt <= referenceDate {
                removeImageFile(for: entry)
                entries.removeValue(forKey: key)
                didMutate = true
            }
        }

        if didMutate {
            persistMetadata()
        }
    }

    func clearAll() {
        for entry in entries.values {
            removeImageFile(for: entry)
        }
        entries.removeAll()
        persistMetadata()
    }
}

// MARK: - Private helpers

private extension DiscoveryAssetCache {
    func makeDirectoriesIfNeeded() throws {
        if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
            try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    func loadExistingMetadata() throws {
        guard fileManager.fileExists(atPath: metadataURL.path) else { return }
        let data = try Data(contentsOf: metadataURL)
        let decoded = try decoder.decode([Int64: Entry].self, from: data)
        entries = decoded
    }

    func persistMetadata() {
        do {
            try makeDirectoriesIfNeeded()
            let data = try encoder.encode(entries)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            discoveryAssetCacheLogger.error("Failed to persist metadata: \(error.localizedDescription, privacy: .public)")
        }
    }

    func removeImageFile(for entry: Entry) {
        guard let fileName = entry.imageFileName else { return }
        let fileURL = cacheDirectoryURL.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: fileURL)
    }
}
