import Foundation
import SwiftUI

/// Tracks mini player visibility and height for scroll content insets.
/// This replaces VoiceoverPlayerInsetStore with a more complete API.
@MainActor
public final class MiniPlayerPresenceStore: ObservableObject {
    @Published public var height: CGFloat = 0
    @Published public var isVisible: Bool = true
    
    public init() {}
    
    /// The effective bottom inset that scroll views should apply
    public var effectiveInset: CGFloat {
        isVisible ? height : 0
    }
    
    /// Updates the height with debouncing to avoid frequent updates
    public func update(height: CGFloat) {
        let clamped = max(height, 0)
        if abs(clamped - self.height) > 0.5 {
            self.height = clamped
        }
    }
    
    /// Convenience alias for update(height:)
    public func updateHeight(_ height: CGFloat) {
        update(height: height)
    }
    
    /// Updates visibility state
    public func setVisible(_ visible: Bool) {
        if self.isVisible != visible {
            self.isVisible = visible
        }
    }
    
    /// Convenience alias for setVisible(_:)
    public func updateVisibility(_ visible: Bool) {
        setVisible(visible)
    }
}

// MARK: - Preference Key

public struct MiniPlayerHeightPreferenceKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
