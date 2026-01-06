import Foundation

/// Persists user preference for automatically saving camera captures to the Photos library.
public actor PhotoSavePreferencesStore: Sendable {
    private static let key = "settings.autoPhotoSaveEnabled"
    private let defaults: UserDefaults
    
    public init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
    
    // MARK: - Load / Save
    
    /// Returns whether auto-save is enabled. Defaults to `true` when no value is stored.
    public func isEnabled() -> Bool {
        // object(forKey:) returns nil if key doesn't exist, allowing us to default to true
        return defaults.object(forKey: Self.key) as? Bool ?? true
    }
    
    /// Sets the auto-save preference.
    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
    }
    
    /// Resets the preference to default (removes the stored value).
    public func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}
