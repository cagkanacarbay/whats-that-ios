import SwiftUI

/// A view modifier that adds bottom safe area inset for the mini player.
/// Apply this to ScrollView or List to create extra scroll room when the mini player is visible.
public struct MiniPlayerScrollInsetModifier: ViewModifier {
    @Environment(\.audioServices) private var audioServices
    
    public init() {}
    
    public func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let services = audioServices, services.miniPlayerPresence.isVisible {
                    Color.clear
                        .frame(height: services.miniPlayerPresence.effectiveInset)
                }
            }
    }
}

public extension View {
    /// Adds bottom scroll inset for the mini player when it's visible.
    /// Apply this to ScrollView or List that need extra scroll room.
    func miniPlayerScrollInset() -> some View {
        modifier(MiniPlayerScrollInsetModifier())
    }
}
