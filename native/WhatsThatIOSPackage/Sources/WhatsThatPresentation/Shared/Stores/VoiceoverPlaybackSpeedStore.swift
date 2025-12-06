import Foundation

/// Persists the user's global playback speed preference.
/// Valid presets: 0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 2x
@MainActor
public final class VoiceoverPlaybackSpeedStore: ObservableObject {
    private static let speedKey = "voiceover_playback_speed"
    
    public static let validRates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    
    @Published public var speed: Double {
        didSet {
            guard Self.validRates.contains(speed) else {
                speed = 1.0
                return
            }
            defaults.set(speed, forKey: Self.speedKey)
        }
    }
    
    private let defaults: UserDefaults
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: Self.speedKey)
        self.speed = Self.validRates.contains(stored) ? stored : 1.0
    }
    
    /// Cycles to the next playback speed in the preset list
    public func cycleSpeed() {
        guard let currentIndex = Self.validRates.firstIndex(of: speed) else {
            speed = 1.0
            return
        }
        let nextIndex = (currentIndex + 1) % Self.validRates.count
        speed = Self.validRates[nextIndex]
    }
    
    /// Returns a formatted string for display (e.g., "1.5x")
    public var displayString: String {
        if speed == floor(speed) {
            return String(format: "%.0fx", speed)
        } else {
            return String(format: "%.2gx", speed)
        }
    }
}
