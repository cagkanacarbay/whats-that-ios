import Foundation
import WhatsThatDomain
import WhatsThatShared

public actor NearbyPlacesCacheStore {
    private var snapshots: [NearbyPlacesSnapshot]
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(cacheDirectory: URL, fileName: String = "nearby-places-cache.json") {
        self.fileURL = cacheDirectory.appendingPathComponent(fileName)
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([NearbyPlacesSnapshot].self, from: data) {
            self.snapshots = decoded
        } else {
            self.snapshots = []
        }
    }

    public func bestSnapshot(
        for coordinate: GeoCoordinate,
        within distance: Double,
        ttl: TimeInterval,
        now: Date
    ) -> NearbyPlacesSnapshot? {
        snapshots = purgeExpiredSnapshots(ttl: ttl, now: now)

        var best: (snapshot: NearbyPlacesSnapshot, distance: Double)?

        for snapshot in snapshots {
            let age = now.timeIntervalSince(snapshot.fetchedAt)
            guard age <= ttl else { continue }

            // Selection is based strictly on reuse distance (ignore snapshot.radiusMeters)
            let delta = snapshot.origin.distance(to: coordinate)
            guard delta <= distance else { continue }

            if let currentBest = best {
                if delta < currentBest.distance {
                    best = (snapshot, delta)
                }
            } else {
                best = (snapshot, delta)
            }
        }

        return best?.snapshot
    }

    public func allSnapshots() -> [NearbyPlacesSnapshot] {
        snapshots
    }

    public func store(
        snapshot: NearbyPlacesSnapshot,
        maxEntries: Int
    ) async {
        snapshots.removeAll { $0.id == snapshot.id }
        snapshots.append(snapshot)
        snapshots.sort { $0.fetchedAt > $1.fetchedAt }

        if snapshots.count > maxEntries {
            snapshots = Array(snapshots.prefix(maxEntries))
        }

        await persist()
    }

    public func prune(ttl: TimeInterval, now: Date) async {
        snapshots = purgeExpiredSnapshots(ttl: ttl, now: now)
        await persist()
    }

    public func clearAll() async {
        snapshots.removeAll()
        await persist()
    }

    private func purgeExpiredSnapshots(ttl: TimeInterval, now: Date) -> [NearbyPlacesSnapshot] {
        snapshots.filter { now.timeIntervalSince($0.fetchedAt) <= ttl }
    }

    private func persist() async {
        do {
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }
            let data = try encoder.encode(snapshots)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Swallow persistence errors; cache misses are acceptable.
        }
    }
}

// MARK: - UserDataClearable

extension NearbyPlacesCacheStore: UserDataClearable {
    public func clearUserData() async {
        await clearAll()
    }
}
