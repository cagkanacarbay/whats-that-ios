import Foundation

public enum IPoPDimension: String, CaseIterable, Codable, Sendable {
    case ideas = "Ideas"
    case people = "People"
    case objects = "Objects"
    case physical = "Physical"

    public var displayName: String { rawValue }
}

public struct IPoPPreferences: Codable, Equatable, Sendable {
    public let ordered: [IPoPDimension]

    public init?(ordered: [IPoPDimension]) {
        guard IPoPPreferences.isValid(order: ordered) else { return nil }
        self.ordered = ordered
    }

    private static func isValid(order: [IPoPDimension]) -> Bool {
        let expectedCount = IPoPDimension.allCases.count
        return order.count == expectedCount && Set(order).count == expectedCount
    }
}

public actor IPoPPreferencesStore: Sendable {
    private enum Keys {
        static let preferences = "ipop.preferences"
    }

    private let defaults: UserDefaults

    public init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func load() -> IPoPPreferences? {
        guard let raw = defaults.array(forKey: Keys.preferences) as? [String] else {
            return nil
        }
        let dimensions = raw.compactMap { IPoPDimension(rawValue: $0) }
        return IPoPPreferences(ordered: dimensions)
    }

    public func save(_ preferences: IPoPPreferences) {
        defaults.set(preferences.ordered.map(\.rawValue), forKey: Keys.preferences)
    }

    public func reset() {
        defaults.removeObject(forKey: Keys.preferences)
    }
}
