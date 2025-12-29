import SwiftUI
import os
import WhatsThatShared
import WhatsThatDomain

struct HeroPlayerView: View {
    @Environment(\.audioServices) private var services
    @Environment(\.colorScheme) var colorScheme
    
    /// Whether to use compact sizing (for small screens like iPad compatibility mode)
    var isCompact: Bool = false
    
    /// Whether the voiceover status is currently being checked for all discoveries
    var isCheckingVoiceoverStatus: Bool = false
    
    /// Whether the user has any discoveries at all
    var hasAnyDiscoveries: Bool = false
    
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
                hasAnyDiscoveries: hasAnyDiscoveries,
                isCheckingVoiceoverStatus: isCheckingVoiceoverStatus,
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
    let hasAnyDiscoveries: Bool
    let isCheckingVoiceoverStatus: Bool
    var onTextSelected: (DiscoverySummary?) -> Void
    
    @State private var selectedMode = "Audio"
    @State private var didAttemptAutoLoad = false
    @State private var generatingDiscovery: DiscoverySummary? = nil
    
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
    
    /// Returns the first audio-ready discovery ID from assetStates
    /// Since baseList may be empty on first load, we check assetStates directly
    private var firstAudioReadyId: Int64? {
        let assetStates = controller.assetStates
        
        log.debug("[firstAudioReadyId] Checking assetStates.count=\(assetStates.count)")
        
        // Find all ready discovery IDs
        let readyIds = assetStates.compactMap { id, asset -> Int64? in
            if asset.status == .ready {
                log.debug("[firstAudioReadyId] id=\(id) is READY")
                return id
            } else {
                log.debug("[firstAudioReadyId] id=\(id) status=\(String(describing: asset.status))")
                return nil
            }
        }
        
        if let firstId = readyIds.first {
            log.debug("[firstAudioReadyId] FOUND ready audio guide: id=\(firstId)")
            return firstId
        }
        
        log.debug("[firstAudioReadyId] No audio-ready discovery found")
        return nil
    }
    
    /// Whether any audio guides are available
    private var hasAnyAudioGuides: Bool {
        firstAudioReadyId != nil
    }
    
    /// Returns the first generating discovery ID (only when no ready audio guides exist)
    private var firstGeneratingId: Int64? {
        // Only show generating state when no audio is ready yet
        guard firstAudioReadyId == nil else { return nil }
        
        let assetStates = controller.assetStates
        return assetStates.compactMap { id, asset -> Int64? in
            if asset.status == .processing {
                return id
            }
            return nil
        }.first
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: isCompact ? 12 : 24) {
            // Space reserved for pill (positioned by parent as fixed overlay)
            Spacer().frame(height: isCompact ? 24 : 36)
            
            // Main Circular Player
            circularPlayer
            
            // Meta Info (Title or Empty State)
            VStack(spacing: isCompact ? 4 : 8) {
                if discovery != nil {
                    // Show discovery title when loaded
                    Text(discovery!.title)
                        .font(isCompact ? .headline : .title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                        .lineLimit(isCompact ? 1 : 2)
                        .padding(.horizontal)
                        .padding(.top, isCompact ? 2 : 5)
                } else if isCheckingVoiceoverStatus {
                    // Still checking for audio guides - show loading message
                    Text("Loading your audio guides")
                        .font(isCompact ? .subheadline : .body)
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                        .padding(.horizontal)
                        .padding(.top, isCompact ? 2 : 5)
                } else if generatingDiscovery != nil {
                    // Audio guide is being generated
                    VStack(spacing: 4) {
                        Text("Generating audio guide...")
                            .font(isCompact ? .subheadline : .body)
                            .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                        if let generating = generatingDiscovery {
                            Text(generating.title)
                                .font(isCompact ? .caption : .subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, isCompact ? 2 : 5)
                } else if hasAnyDiscoveries {
                    // Has discoveries but no audio guides yet
                    (Text("Create an audio guide from ") + 
                     Text("My Discoveries").fontWeight(.bold) + 
                     Text(" to start"))
                        .font(isCompact ? .subheadline : .body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                        .padding(.horizontal)
                        .padding(.top, isCompact ? 2 : 5)
                } else {
                    // No discoveries at all - guide user to create their first one
                    (Text("To listen to audio guides first create a discovery using ") + 
                     Text("Camera").fontWeight(.bold) + 
                     Text(" or ") +
                     Text("Gallery").fontWeight(.bold))
                        .font(isCompact ? .subheadline : .body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                        .padding(.horizontal)
                        .padding(.top, isCompact ? 2 : 5)
                }
            }
            
            // Controls
            playbackControls
            
            // Autoplay and Speed Control Row
            bottomControlsRow
        }
        .onAppear {
            attemptAutoLoadFirstGuide()
            fetchGeneratingDiscoveryIfNeeded()
        }
        .onChange(of: controller.assetStates) { _, _ in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                // When asset states change, check if we can auto-load
                attemptAutoLoadFirstGuide()
                fetchGeneratingDiscoveryIfNeeded()
            }
        }
        .onChange(of: isCheckingVoiceoverStatus) { _, isChecking in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                // When checking completes, try to auto-load
                if !isChecking {
                    attemptAutoLoadFirstGuide()
                    fetchGeneratingDiscoveryIfNeeded()
                }
            }
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
                    placeholderArtworkContent
                }
            }
            // Force view recreation when discovery changes to reload image
            .id("hero-artwork-\(discovery.id)-\(imagePath)")
        } else if let generating = generatingDiscovery,
                  let imagePath = generating.imagePath,
                  let imageURL = URL(string: imagePath) {
            // Audio guide is generating - show faded image with spinner
            ZStack {
                DiscoveryCachedImage(
                    discoveryId: generating.id,
                    remoteURL: imageURL
                ) { phase in
                    switch phase {
                    case .success(let platformImage):
                        Image(uiImage: platformImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: artworkSize, height: artworkSize)
                            .clipShape(Circle())
                            .opacity(0.4)  // Faded appearance
                    case .loading, .empty, .failure:
                        placeholderArtworkContent
                            .opacity(0.4)
                    }
                }
                .id("hero-generating-\(generating.id)-\(imagePath)")
                
                // Spinner overlay for generating state
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: BrandColors.logo))
                    .scaleEffect(isCompact ? 1.5 : 2.0)
            }
        } else {
            // No discovery loaded - show placeholder with optional spinner
            ZStack {
                placeholderArtworkContent
                
                // Show spinner while checking for audio guides
                if isCheckingVoiceoverStatus {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: BrandColors.logo))
                        .scaleEffect(isCompact ? 1.5 : 2.0)
                }
            }
        }
    }
    
    private var placeholderArtworkContent: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: artworkSize, height: artworkSize)
    }
    
    private var placeholderArtwork: some View {
        placeholderArtworkContent
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
    
    /// Attempts to auto-load the first audio guide when the view appears
    private func attemptAutoLoadFirstGuide() {
        log.debug("[attemptAutoLoadFirstGuide] Called. discovery=\(discovery?.id ?? -1), didAttemptAutoLoad=\(didAttemptAutoLoad)")
        log.debug("[attemptAutoLoadFirstGuide] isCheckingVoiceoverStatus=\(isCheckingVoiceoverStatus)")
        
        // Don't auto-load if we already have a discovery loaded
        guard discovery == nil else {
            log.debug("[attemptAutoLoadFirstGuide] SKIP: discovery already loaded")
            return
        }
        
        // Don't attempt more than once (after we've successfully loaded one)
        guard !didAttemptAutoLoad else {
            log.debug("[attemptAutoLoadFirstGuide] SKIP: already attempted")
            return
        }
        
        // Check if there's an audio-ready discovery
        if let firstReadyId = firstAudioReadyId {
            log.debug("[attemptAutoLoadFirstGuide] Found firstReadyId=\(firstReadyId), attempting to load")
            // Auto-load the first available audio guide
            if let discovery = controller.getDiscovery(id: firstReadyId) {
                log.debug("[attemptAutoLoadFirstGuide] Got discovery from provider: '\(discovery.title)'")
                didAttemptAutoLoad = true  // Only mark as attempted when we actually load
                // Just set it as current without playing - user can press play
                controller.setCurrentDiscovery(discovery)
            } else {
                log.debug("[attemptAutoLoadFirstGuide] Discovery not in provider, fetching from store...")
                Task {
                    if let discovery = await audioServices.discoveryStore.get(id: firstReadyId) {
                        log.debug("[attemptAutoLoadFirstGuide] Got discovery from store: '\(discovery.title)'")
                        await MainActor.run {
                            didAttemptAutoLoad = true  // Only mark as attempted when we actually load
                        }
                        controller.setCurrentDiscovery(discovery)
                    } else {
                        log.debug("[attemptAutoLoadFirstGuide] FAILED: Could not find discovery in store")
                    }
                }
            }
        } else {
            log.debug("[attemptAutoLoadFirstGuide] No firstReadyId found")
        }
    }
    
    /// Fetches the generating discovery info when we detect one is being created
    private func fetchGeneratingDiscoveryIfNeeded() {
        // Clear if we now have a ready audio guide (generating is complete)
        if firstAudioReadyId != nil {
            if generatingDiscovery != nil {
                generatingDiscovery = nil
                log.debug("[fetchGeneratingDiscovery] Cleared generating discovery - audio is now ready")
            }
            return
        }
        
        // Check if there's a generating discovery
        guard let generatingId = firstGeneratingId else {
            if generatingDiscovery != nil {
                generatingDiscovery = nil
                log.debug("[fetchGeneratingDiscovery] Cleared generating discovery - no longer generating")
            }
            return
        }
        
        // Don't re-fetch if already tracking this one
        if generatingDiscovery?.id == generatingId {
            return
        }
        
        log.debug("[fetchGeneratingDiscovery] Found generating id=\(generatingId), fetching discovery info")
        
        // Try to get from controller's cache first
        if let discovery = controller.getDiscovery(id: generatingId) {
            generatingDiscovery = discovery
            log.debug("[fetchGeneratingDiscovery] Got from controller: '\(discovery.title)'")
        } else {
            // Fetch from discovery store
            Task {
                if let discovery = await audioServices.discoveryStore.get(id: generatingId) {
                    await MainActor.run {
                        generatingDiscovery = discovery
                    }
                    log.debug("[fetchGeneratingDiscovery] Got from store: '\(discovery.title)'")
                }
            }
        }
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
