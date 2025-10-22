#if os(macOS)
import Foundation

extension VoiceoverPlaybackController.PlaybackState {
    var discoveryId: Int64? {
        switch self {
        case let .loading(discoveryId),
             let .playing(discoveryId),
             let .paused(discoveryId),
             let .unavailable(discoveryId),
             let .failed(discoveryId, _):
            return discoveryId
        case .idle:
            return nil
        }
    }
}
#endif
