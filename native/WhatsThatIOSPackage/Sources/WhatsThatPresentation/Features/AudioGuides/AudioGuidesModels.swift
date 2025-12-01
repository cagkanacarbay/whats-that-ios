import Foundation

enum AudioGuideStatus: Equatable {
    case ready
    case empty
    case generating
    case failed
}

struct AudioGuide: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let duration: TimeInterval
    let image: String // Placeholder image name
    let isAuto: Bool
    var status: AudioGuideStatus = .ready
    
    var durationString: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum AudioGuideListType {
    case upNext
    case discover
}

enum PlaybackState {
    case playing
    case paused
    case stopped
}
