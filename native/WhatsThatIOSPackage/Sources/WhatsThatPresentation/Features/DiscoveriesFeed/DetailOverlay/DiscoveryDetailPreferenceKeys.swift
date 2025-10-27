import SwiftUI

struct HeroScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// HeaderContainerBottomPreferenceKey was removed; overlay offset is now
// computed analytically from overlay geometry, avoiding 1-frame lag.
