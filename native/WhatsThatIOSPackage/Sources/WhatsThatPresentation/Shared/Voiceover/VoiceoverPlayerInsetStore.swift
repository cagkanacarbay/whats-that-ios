import Foundation
import SwiftUI

@MainActor
final class VoiceoverPlayerInsetStore: ObservableObject {
    @Published var height: CGFloat = 0

    func update(height: CGFloat) {
        let clamped = max(height, 0)
        if abs(clamped - self.height) > 0.5 {
            self.height = clamped
        }
    }
}

struct VoiceoverPlayerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

