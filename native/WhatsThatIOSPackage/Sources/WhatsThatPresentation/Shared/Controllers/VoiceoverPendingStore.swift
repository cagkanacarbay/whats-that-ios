import Foundation

// Lightweight persistence for in-flight voiceover requests so polling can
// resume across view lifecycles and app relaunches.
public actor VoiceoverPendingStore {
    // Wrap UserDefaults to satisfy Sendable checks; UserDefaults is documented
    // as thread-safe.
    private struct SendableDefaults: @unchecked Sendable {
        let value: UserDefaults
    }

    public static let shared = VoiceoverPendingStore()

    private let defaults: SendableDefaults
    private let key = "voiceover.pending.ids"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = SendableDefaults(value: defaults)
    }

    public func load() -> Set<Int64> {
        let raw = defaults.value.array(forKey: key) as? [NSNumber] ?? []
        return Set(raw.map { $0.int64Value })
    }

    public func save(_ ids: Set<Int64>) {
        let numbers = ids.map { NSNumber(value: $0) }
        defaults.value.set(numbers, forKey: key)
    }

    public func add(_ id: Int64) {
        var current = load()
        current.insert(id)
        save(current)
    }

    public func remove(_ id: Int64) {
        var current = load()
        current.remove(id)
        save(current)
    }
}
