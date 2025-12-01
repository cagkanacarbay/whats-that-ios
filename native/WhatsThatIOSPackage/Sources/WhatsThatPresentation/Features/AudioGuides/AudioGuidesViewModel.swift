import SwiftUI
import Combine

class AudioGuidesViewModel: ObservableObject {
    @Published var currentGuide: AudioGuide?
    @Published var playbackState: PlaybackState = .paused
    @Published var progress: Double = 0.35 // 0.0 to 1.0
    @Published var autoplayEnabled: Bool = false
    @Published var playbackSpeed: Double = 1.0
    
    @Published var selectedList: AudioGuideListType = .upNext
    
    @Published var upNextQueue: [AudioGuide] = []
    @Published var discoverList: [AudioGuide] = []
    
    // Persisted progress for each guide (0.0 to 1.0)
    @Published var playbackProgress: [UUID: Double] = [:]
    
    @Published var userCredits: Int = 5
    @Published var guideForAlert: AudioGuide?
    @Published var showCreateAlert: Bool = false
    
    @Published var recentlyQueuedGuideId: UUID?
    
    // Filter toggle
    @Published var showWithoutAudioGuide: Bool = true
    
    private let backDoubleTapInterval: TimeInterval = 0.4
    private let earlyPreviousWindow: TimeInterval = 1.5
    private var lastBackTapDate: Date?
    
    init() {
        setupMockData()
    }
    
    var filteredDiscoverList: [AudioGuide] {
        if showWithoutAudioGuide {
            return discoverList
        } else {
            return discoverList.filter { $0.status != .empty }
        }
    }
    
    func setupMockData() {
        currentGuide = AudioGuide(title: "Architectural History of the Colosseum", duration: 425, image: "post1", isAuto: false)
        
        let upNext = [
            AudioGuide(title: "Roman Forum Highlights", duration: 180, image: "post2", isAuto: true),
            AudioGuide(title: "Palatine Hill Myths", duration: 320, image: "post3", isAuto: false),
            AudioGuide(title: "The Pantheon's Dome", duration: 245, image: "post4", isAuto: false),
            // Dummy generating item
            AudioGuide(title: "Circus Maximus History", duration: 0, image: "post1", isAuto: false, status: .generating)
        ]
        upNextQueue = upNext
        
        discoverList = [
            AudioGuide(title: "Vatican City Secrets", duration: 600, image: "post2", isAuto: false),
            AudioGuide(title: "Trevi Fountain Legends", duration: 150, image: "post3", isAuto: false),
            AudioGuide(title: "Spanish Steps Guide", duration: 200, image: "post4", isAuto: false),
            AudioGuide(title: "Castle of the Holy Angel", duration: 400, image: "post1", isAuto: false),
            AudioGuide(title: "Piazza Navona Art", duration: 300, image: "post2", isAuto: false),
            AudioGuide(title: "Villa Borghese Gardens", duration: 500, image: "post3", isAuto: false),
            // New states
            AudioGuide(title: "Pantheon Exterior", duration: 0, image: "post1", isAuto: false, status: .empty),
            AudioGuide(title: "Colosseum Underground", duration: 0, image: "post2", isAuto: false, status: .failed)
        ]
        
        // Mock some progress
        if let first = upNext.first {
            playbackProgress[first.id] = 0.45
        }
        if let last = discoverList.first(where: { $0.status == .ready }) {
            playbackProgress[last.id] = 0.15
        }
    }
    
    func togglePlayPause() {
        if playbackState == .playing {
            playbackState = .paused
        } else {
            playbackState = .playing
        }
    }
    
    func requestCreation(for guide: AudioGuide) {
        if guide.status == .empty {
            guideForAlert = guide
            showCreateAlert = true
        } else if guide.status == .failed {
            createAudioGuide(for: guide)
        }
    }
    
    func confirmCreation() {
        guard let guide = guideForAlert else { return }
        createAudioGuide(for: guide)
        guideForAlert = nil
    }
    
    func addToQueue(_ guide: AudioGuide) {
        if !upNextQueue.contains(where: { $0.id == guide.id }) {
            upNextQueue.append(guide)
            showQueueConfirmation(for: guide.id)
        }
    }
    
    func showQueueConfirmation(for id: UUID) {
        withAnimation {
            recentlyQueuedGuideId = id
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            if self.recentlyQueuedGuideId == id {
                withAnimation {
                    self.recentlyQueuedGuideId = nil
                }
            }
        }
    }
    
    func createAudioGuide(for guide: AudioGuide) {
        guard let index = discoverList.firstIndex(where: { $0.id == guide.id }) else { return }
        
        // Set to generating
        withAnimation {
            discoverList[index].status = .generating
        }
        
        // Simulate API call
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self else { return }
            guard let currentIndex = self.discoverList.firstIndex(where: { $0.id == guide.id }) else { return }
            
            withAnimation {
                // 80% chance of success
                let success = Bool.random() && Bool.random() == false ? false : true // Bias towards success
                if success {
                    var updatedGuide = self.discoverList[currentIndex]
                    updatedGuide.status = .ready
                    // Mock a duration
                    updatedGuide = AudioGuide(
                        title: updatedGuide.title,
                        duration: Double.random(in: 120...600),
                        image: updatedGuide.image,
                        isAuto: true,
                        status: .ready
                    )
                    self.discoverList[currentIndex] = updatedGuide
                    
                    // Deduct credit on success (mock)
                    if self.userCredits > 0 {
                        self.userCredits -= 1
                    }
                } else {
                    self.discoverList[currentIndex].status = .failed
                }
            }
        }
    }
    
    func skipForward5() {
        progress = min(progress + (5.0 / (currentGuide?.duration ?? 1.0)), 1.0)
        if let current = currentGuide {
            playbackProgress[current.id] = progress
        }
    }
    
    func skipBackward5() {
        progress = max(progress - (5.0 / (currentGuide?.duration ?? 1.0)), 0.0)
        if let current = currentGuide {
            playbackProgress[current.id] = progress
        }
    }
    
    func handleBackButtonTap() {
        guard let tappedGuide = currentGuide else { return }
        
        let now = Date()
        if let lastTapDate = lastBackTapDate, now.timeIntervalSince(lastTapDate) <= backDoubleTapInterval {
            lastBackTapDate = nil
            playPrevious()
            return
        }
        
        lastBackTapDate = now
        
        DispatchQueue.main.asyncAfter(deadline: .now() + backDoubleTapInterval) { [weak self] in
            guard let self else { return }
            guard self.lastBackTapDate == now else { return }
            self.lastBackTapDate = nil
            guard let activeGuide = self.currentGuide, activeGuide.id == tappedGuide.id else { return }
            
            let positionSeconds = self.playbackPositionSeconds(for: activeGuide)
            if positionSeconds <= self.earlyPreviousWindow {
                self.playPrevious()
            } else {
                self.restartCurrentGuide(activeGuide)
            }
        }
    }
    
    func playGuide(_ guide: AudioGuide) {
        guard guide.status == .ready else { return }
        
        // Save progress of currently playing guide
        if let current = currentGuide {
            playbackProgress[current.id] = progress
        }
        
        currentGuide = guide
        playbackState = .playing
        
        // Restore progress or start from 0
        progress = playbackProgress[guide.id] ?? 0.0
    }
    
    func playNextInQueue(_ guide: AudioGuide) {
        if let index = upNextQueue.firstIndex(where: { $0.id == guide.id }) {
            // If already in queue, move to top
            upNextQueue.remove(at: index)
        }
        upNextQueue.insert(guide, at: 0)
    }
    
    private func restartCurrentGuide(_ guide: AudioGuide) {
        progress = 0.0
        playbackProgress[guide.id] = 0.0
    }
    
    private func playbackPositionSeconds(for guide: AudioGuide) -> TimeInterval {
        let guideProgress = guide.id == currentGuide?.id ? progress : playbackProgress[guide.id] ?? 0.0
        return guide.duration * guideProgress
    }
    
    func reorderQueue(from source: IndexSet, to destination: Int) {
        upNextQueue.move(fromOffsets: source, toOffset: destination)
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
