import SwiftUI
import os
import WhatsThatShared
import WhatsThatDomain

struct HeroPlayerView: View {
    @Environment(\.audioServices) private var services
    @Environment(\.colorScheme) var colorScheme
    
    /// Whether to use compact sizing (for small screens like iPad compatibility mode)
    var isCompact: Bool = false
    
    /// Callback when user taps "Text" to open discovery detail
    var onTextSelected: (DiscoverySummary?) -> Void = { _ in }
    
    var body: some View {
        if let services {
            HeroPlayerContentView(
                controller: services.playbackController,
                queueStore: services.queueStore,
                audioServices: services,
                colorScheme: colorScheme,
                isCompact: isCompact,
                onTextSelected: onTextSelected
            )
        }
    }
}

/// Inner view that properly observes the playback controller
private struct HeroPlayerContentView: View {
    @ObservedObject var controller: VoiceoverPlaybackController
    @ObservedObject var queueStore: AudioGuidesQueueStore
    let audioServices: AudioServicesContainer
    let colorScheme: ColorScheme
    let isCompact: Bool
    var onTextSelected: (DiscoverySummary?) -> Void
    
    @State private var selectedMode = "Audio"
    
    // Responsive sizing for compact screens
    private var ringSize: CGFloat { isCompact ? 200 : 300 }
    private var artworkSize: CGFloat { isCompact ? 176 : 264 }
    private var timeLabelsWidth: CGFloat { isCompact ? 160 : 240 }
    
    // Accelerated seek state
    @State private var seekTimer: Timer?
    
    private let log = Logger(subsystem: "WhatsThat.AudioGuides", category: "HeroPlayerView")
    
    // MARK: - Computed Properties
    
    private var speedStore: VoiceoverPlaybackSpeedStore {
        audioServices.speedStore
    }
    
    private var discovery: DiscoverySummary? {
        controller.currentDiscovery
    }
    
    private var progress: Double {
        guard let duration = controller.duration, duration > 0 else { return 0 }
        return controller.position / duration
    }
    
    private var currentTimeString: String {
        let seconds = controller.position
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private var durationString: String {
        guard let duration = controller.duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private var isPlaying: Bool {
        if case .playing = controller.playbackState { return true }
        return false
    }
    
    private var autoplayEnabled: Bool {
        get { queueStore.autoplayEnabled }
    }
    
    private var canPlayNext: Bool {
        queueStore.hasNext
    }
    
    private var canPlayPrevious: Bool {
        // Always allow previous if playing (for restart functionality)
        controller.position > 3.0 || queueStore.hasPrevious
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: isCompact ? 12 : 24) {
            // Space reserved for pill (positioned by parent as fixed overlay)
            Spacer().frame(height: isCompact ? 24 : 36)
            
            // Main Circular Player
            circularPlayer
            
            // Meta Info (Title)
            VStack(spacing: isCompact ? 4 : 8) {
                Text(discovery?.title ?? "Select a guide")
                    .font(isCompact ? .headline : .title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                    .lineLimit(isCompact ? 1 : 2)
                    .padding(.horizontal)
                    .padding(.top, isCompact ? 2 : 5)
            }
            
            // Controls
            playbackControls
            
            // Autoplay and Speed Control Row
            bottomControlsRow
        }
    }
    
    // MARK: - Mode Switcher (exposed as internal for parent positioning)
    
    var modeSwitcher: some View {
        HStack(spacing: 0) {
            Button(action: {
                log.debug("Text pill tapped; requesting detail open")
                onTextSelected(discovery)
            }) {
                Text("Text")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(width: 80, height: 32)
                    .foregroundColor(selectedMode == "Text" ? BrandColors.logo : BrandTheme.palette(for: colorScheme).textSecondary)
                    .background(
                        ZStack {
                            if selectedMode == "Text" {
                                Capsule()
                                    .fill(BrandTheme.palette(for: colorScheme).surface)
                                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                            }
                        }
                    )
            }
            
            Button(action: { selectedMode = "Audio" }) {
                Text("Audio")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(width: 80, height: 32)
                    .foregroundColor(selectedMode == "Audio" ? BrandColors.logo : BrandTheme.palette(for: colorScheme).textSecondary)
                    .background(
                        ZStack {
                            if selectedMode == "Audio" {
                                Capsule()
                                    .fill(BrandTheme.palette(for: colorScheme).surface)
                                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                            }
                        }
                    )
            }
        }
        .padding(2)
        .background(Color.gray.opacity(0.1))
        .clipShape(Capsule())
    }
    
    // MARK: - Circular Player
    
    private var circularPlayer: some View {
        let strokeWidth: CGFloat = isCompact ? 10 : 14
        
        return ZStack {
            // Background Circle
            Circle()
                .trim(from: 0.0, to: 0.8)
                .stroke(BrandColors.Light.secondaryAction.opacity(0.3), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(126))
                .frame(width: ringSize, height: ringSize)
            
            // Progress Ring
            Circle()
                .trim(from: 0.0, to: progress * 0.8)
                .stroke(
                    BrandColors.logo,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(126))
                .frame(width: ringSize, height: ringSize)
            
            // Artwork
            artworkView
        }
        .shadow(color: Color.black.opacity(0.1), radius: isCompact ? 6 : 10, x: 0, y: isCompact ? 2 : 4)
        .overlay(alignment: .bottom) {
            // Time labels
            HStack {
                Text(currentTimeString)
                    .font(isCompact ? .caption2 : .caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                
                Spacer()
                
                Text(durationString)
                    .font(isCompact ? .caption2 : .caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
            }
            .frame(width: timeLabelsWidth)
            .offset(y: isCompact ? 2 : 5)
        }
    }
    
    @ViewBuilder
    private var artworkView: some View {
        if let discovery = discovery,
           let imagePath = discovery.imagePath,
           let imageURL = URL(string: imagePath) {
            DiscoveryCachedImage(
                discoveryId: discovery.id,
                remoteURL: imageURL
            ) { phase in
                switch phase {
                case .success(let platformImage):
                    Image(uiImage: platformImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(Circle())
                case .loading, .empty, .failure:
                    placeholderArtwork
                }
            }
            // Force view recreation when discovery changes to reload image
            .id("hero-artwork-\(discovery.id)-\(imagePath)")
        } else {
            placeholderArtwork
        }
    }
    
    private var placeholderArtwork: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: artworkSize, height: artworkSize)
    }
    
    // MARK: - Playback Controls
    
    private var playbackControls: some View {
        HStack(spacing: isCompact ? 16 : 24) {
            // Prev
            Button(action: playPrevious) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: isCompact ? 20 : 24))
                    .foregroundColor(canPlayPrevious
                        ? BrandTheme.palette(for: colorScheme).textPrimary
                        : BrandTheme.palette(for: colorScheme).textSecondary.opacity(0.4))
            }
            .disabled(!canPlayPrevious)
            
            // -5s with accelerated seek
            seekButton(direction: .backward)
            
            // Play/Pause
            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: isCompact ? 48 : 64))
                    .foregroundColor(BrandColors.logo)
                    .shadow(color: BrandColors.logo.opacity(0.3), radius: isCompact ? 6 : 10, x: 0, y: isCompact ? 2 : 4)
            }
            
            // +5s with accelerated seek
            seekButton(direction: .forward)
            
            // Next
            Button(action: playNext) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: isCompact ? 20 : 24))
                    .foregroundColor(canPlayNext
                        ? BrandTheme.palette(for: colorScheme).textPrimary
                        : BrandTheme.palette(for: colorScheme).textSecondary.opacity(0.4))
            }
            .disabled(!canPlayNext)
        }
        .padding(.bottom, isCompact ? 4 : 10)
    }
    
    @ViewBuilder
    private func seekButton(direction: SeekDirection) -> some View {
        let imageName = direction == .forward ? "goforward.5" : "gobackward.5"
        let seconds: TimeInterval = direction == .forward ? 5 : -5
        
        Button(action: { controller.seek(by: seconds) }) {
            Image(systemName: imageName)
                .font(.system(size: isCompact ? 20 : 24))
                .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in startAcceleratedSeek(direction: direction) }
        )
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            if !pressing { stopAcceleratedSeek() }
        }, perform: {})
    }
    
    // MARK: - Bottom Controls Row
    
    private var bottomControlsRow: some View {
        HStack {
            // Speed Control (Left)
            VStack(spacing: 2) {
                Menu {
                    ForEach(VoiceoverPlaybackSpeedStore.validRates, id: \.self) { speed in
                        Button {
                            controller.setRate(speed)
                        } label: {
                            if speedStore.speed == speed {
                                Label(formatSpeed(speed), systemImage: "checkmark")
                            } else {
                                Text(formatSpeed(speed))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(formatSpeed(speedStore.speed))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .monospacedDigit()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(BrandTheme.palette(for: colorScheme).surface)
                    .cornerRadius(8)
                }
                
                Text("Speed")
                    .font(.caption2)
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
            }
            
            Spacer()
            
            // Autoplay Toggle (Right)
            HStack(spacing: 8) {
                Text("Autoplay")
                    .font(.subheadline)
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                
                Toggle("", isOn: Binding(
                    get: { autoplayEnabled },
                    set: { queueStore.autoplayEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: BrandColors.logo))
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Actions
    
    private func togglePlayPause() {
        if let discovery {
            controller.togglePlayback(for: discovery)
        } else {
            // No discovery selected - play the first audio-ready discovery
            playFirstAudioReadyDiscovery()
        }
    }
    
    private func playFirstAudioReadyDiscovery() {
        // Find the first audio-ready discovery from the baseList
        let assetStates = controller.assetStates
        
        for discoveryId in queueStore.baseList {
            if let asset = assetStates[discoveryId], asset.status == .ready {
                // Found an audio-ready discovery, try to get it and play
                if let discovery = controller.getDiscovery(id: discoveryId) {
                    controller.togglePlayback(for: discovery)
                    return
                } else {
                    // Fall back to fetching from discovery store
                    Task {
                        if let discovery = await audioServices.discoveryStore.get(id: discoveryId) {
                            controller.togglePlayback(for: discovery)
                        }
                    }
                    return
                }
            }
        }
        
        // No audio-ready discovery found in baseList
        log.debug("[togglePlayPause] No audio-ready discovery found to play")
    }
    
    private func playNext() {
        if let nextId = queueStore.next() {
            // Try controller's queue provider first (has all discoveries), then fall back to store
            if let discovery = controller.getDiscovery(id: nextId) {
                controller.togglePlayback(for: discovery)
            } else {
                Task {
                    if let discovery = await audioServices.discoveryStore.get(id: nextId) {
                        controller.togglePlayback(for: discovery)
                    }
                }
            }
        }
    }
    
    private func playPrevious() {
        let currentPosition = controller.position
        let currentId = queueStore.current
        
        if let prevId = queueStore.previous(currentPosition: currentPosition) {
            // If previous() returns the same ID, it means "restart current"
            if prevId == currentId {
                controller.seek(to: 0) {}
            } else {
                // Try controller's queue provider first (has all discoveries), then fall back to store
                if let discovery = controller.getDiscovery(id: prevId) {
                    controller.togglePlayback(for: discovery)
                } else {
                    Task {
                        if let discovery = await audioServices.discoveryStore.get(id: prevId) {
                            controller.togglePlayback(for: discovery)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Accelerated Seek
    
    private func startAcceleratedSeek(direction: SeekDirection) {
        let seconds: TimeInterval = direction == .forward ? 5 : -5
        seekTimer?.invalidate()
        seekTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                controller.seek(by: seconds)
            }
        }
    }
    
    private func stopAcceleratedSeek() {
        seekTimer?.invalidate()
        seekTimer = nil
    }
    
    // MARK: - Helpers
    
    private func formatSpeed(_ speed: Double) -> String {
        if speed == floor(speed) {
            return String(format: "%.0fx", speed)
        } else {
            return String(format: "%.2gx", speed)
        }
    }
}

// MARK: - SeekDirection

private enum SeekDirection {
    case forward
    case backward
}
