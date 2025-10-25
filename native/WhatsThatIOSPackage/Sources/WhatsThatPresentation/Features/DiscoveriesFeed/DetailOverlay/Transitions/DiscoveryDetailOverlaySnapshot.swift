import CoreGraphics
import SwiftUI

struct DiscoveryDetailOverlaySnapshot {
    enum Phase: Equatable {
        case idle
        case preparing
        case animatingIn
        case presented
        case interactiveDismiss
        case closing
        case resetting

        var isActive: Bool {
            switch self {
            case .idle:
                return false
            default:
                return true
            }
        }
    }

    struct AccessibilityState {
        var isVoiceoverActive: Bool = false
    }

    var phase: Phase = .idle
    var context: DiscoveryDetailContext?
    var progress: CGFloat = 0
    var dismissProgress: CGFloat = 0
    var contentOpacity: Double = 0
    var isContentReady: Bool = false
    var isClosing: Bool = false
    var isInteracting: Bool = false
    var gestureTranslation: CGSize = .zero
    var gestureScale: CGFloat = 1
    var gestureRotation: Double = 0
    var gestureShadowOpacity: Double = 0
    var gestureCornerRadius: CGFloat = 0
    var closeStartTranslation: CGSize = .zero
    var closeStartScale: CGFloat = 1
    var closeStartRotation: Double = 0
    var activeDiscoveryId: Int64?
    var accessibility: AccessibilityState = .init()

    var hasActiveOverlay: Bool {
        phase.isActive && context != nil
    }
}
