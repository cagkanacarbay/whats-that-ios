import SwiftUI
import Combine

class AudioGuidesViewModel: ObservableObject {
    @Published var currentGuide: AudioGuide?
    @Published var playbackState: PlaybackState = .paused
    @Published var progress: Double = 0.35 // 0.0 to 1.0
    
    @Published var selectedList: AudioGuideListType = .upNext
    
    @Published var upNextQueue: [AudioGuide] = []
    @Published var discoverList: [AudioGuide] = []
    
    init() {
        setupMockData()
    }
    
    func setupMockData() {
        currentGuide = AudioGuide(title: "Architectural History of the Colosseum", duration: 425, image: "post1", isAuto: false)
        
        upNextQueue = [
            AudioGuide(title: "Roman Forum Highlights", duration: 180, image: "post2", isAuto: true),
            AudioGuide(title: "Palatine Hill Myths", duration: 320, image: "post3", isAuto: false),
            AudioGuide(title: "The Pantheon's Dome", duration: 245, image: "post4", isAuto: false)
        ]
        
        discoverList = [
            AudioGuide(title: "Vatican City Secrets", duration: 600, image: "post2", isAuto: false),
            AudioGuide(title: "Trevi Fountain Legends", duration: 150, image: "post3", isAuto: false),
            AudioGuide(title: "Spanish Steps Guide", duration: 200, image: "post4", isAuto: false),
            AudioGuide(title: "Castle of the Holy Angel", duration: 400, image: "post1", isAuto: false),
            AudioGuide(title: "Piazza Navona Art", duration: 300, image: "post2", isAuto: false),
            AudioGuide(title: "Villa Borghese Gardens", duration: 500, image: "post3", isAuto: false)
        ]
    }
    
    func togglePlayPause() {
        if playbackState == .playing {
            playbackState = .paused
        } else {
            playbackState = .playing
        }
    }
    
    func skipForward5() {
        progress = min(progress + (5.0 / (currentGuide?.duration ?? 1.0)), 1.0)
    }
    
    func skipBackward5() {
        progress = max(progress - (5.0 / (currentGuide?.duration ?? 1.0)), 0.0)
    }
    
    func playGuide(_ guide: AudioGuide) {
        currentGuide = guide
        playbackState = .playing
        progress = 0.0
    }
    
    var currentTimeString: String {
        guard let duration = currentGuide?.duration else { return "0:00" }
        let currentSeconds = duration * progress
        let minutes = Int(currentSeconds) / 60
        let seconds = Int(currentSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    func playNext() {
        // Mock: Cycle through discover list or up next
        if let current = currentGuide, let index = discoverList.firstIndex(where: { $0.id == current.id }) {
             let nextIndex = (index + 1) % discoverList.count
             playGuide(discoverList[nextIndex])
        } else if let first = discoverList.first {
            playGuide(first)
        }
    }
    
    func playPrevious() {
        if let current = currentGuide, let index = discoverList.firstIndex(where: { $0.id == current.id }) {
             let prevIndex = (index - 1 + discoverList.count) % discoverList.count
             playGuide(discoverList[prevIndex])
        } else if let first = discoverList.first {
            playGuide(first)
        }
    }
}
