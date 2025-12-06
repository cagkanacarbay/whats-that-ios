import Foundation

/// Persists per-discovery playback positions for display purposes.
/// Playback always starts from position 0, but this store tracks progress
/// for showing "you listened until here" indicators.
@MainActor
public final class VoiceoverProgressStore: ObservableObject {
    private static let positionsKey = "voiceover_positions"
    private static let lastPlayedKey = "voiceover_last_played"
    private static let maxEntries = 500  // ~2KB per entry = ~1MB max
    
    @Published private(set) var positions: [Int64: Double] = [:]
    @Published private(set) var lastPlayed: [Int64: Date] = [:]
    
    private let defaults: UserDefaults
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }
    
    // MARK: - Public API
    
    /// Returns the stored position for a discovery (0.0 to 1.0), or nil if not tracked
    public func position(for discoveryId: Int64) -> Double? {
        positions[discoveryId]
    }
    
    /// Returns the last played date for a discovery, or nil if not tracked
    public func lastPlayedDate(for discoveryId: Int64) -> Date? {
        lastPlayed[discoveryId]
    }
    
    /// Updates the playback position for a discovery
    public func updatePosition(_ position: Double, for discoveryId: Int64) {
        positions[discoveryId] = position
        lastPlayed[discoveryId] = Date()
        save()
    }
    
    /// Clears position data for a discovery (e.g., when discovery is deleted)
    public func clearPosition(for discoveryId: Int64) {
        positions.removeValue(forKey: discoveryId)
        lastPlayed.removeValue(forKey: discoveryId)
        save()
    }
    
    /// Clears all stored progress data
    public func clearAll() {
        positions.removeAll()
        lastPlayed.removeAll()
        save()
    }
    
    // MARK: - Pruning
    
    private func pruneIfNeeded() {
        guard positions.count > Self.maxEntries else { return }
        
        // Sort by lastPlayed date (oldest first) and remove oldest entries
        let sortedIds = lastPlayed.sorted { $0.value < $1.value }.map(\.key)
        let toRemove = sortedIds.prefix(positions.count - Self.maxEntries)
        
        for id in toRemove {
            positions.removeValue(forKey: id)
            lastPlayed.removeValue(forKey: id)
        }
    }
    
    // MARK: - Persistence
    
    private func load() {
        // Load positions
        if let data = defaults.data(forKey: Self.positionsKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            positions = decoded.reduce(into: [:]) { result, pair in
                if let id = Int64(pair.key) {
                    result[id] = pair.value
                }
            }
        }
        
        // Load lastPlayed dates
        if let data = defaults.data(forKey: Self.lastPlayedKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            lastPlayed = decoded.reduce(into: [:]) { result, pair in
                if let id = Int64(pair.key) {
                    result[id] = pair.value
                }
            }
        }
    }
    
    private func save() {
        pruneIfNeeded()
        
        // Convert Int64 keys to String for JSON encoding
        let positionsDict = positions.reduce(into: [String: Double]()) { result, pair in
            result[String(pair.key)] = pair.value
        }
        let lastPlayedDict = lastPlayed.reduce(into: [String: Date]()) { result, pair in
            result[String(pair.key)] = pair.value
        }
        
        if let positionsData = try? JSONEncoder().encode(positionsDict) {
            defaults.set(positionsData, forKey: Self.positionsKey)
        }
        if let lastPlayedData = try? JSONEncoder().encode(lastPlayedDict) {
            defaults.set(lastPlayedData, forKey: Self.lastPlayedKey)
        }
    }
}
