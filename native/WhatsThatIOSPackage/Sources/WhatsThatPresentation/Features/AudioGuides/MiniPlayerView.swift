import SwiftUI
import WhatsThatShared
import WhatsThatDomain
import os

private let log = Logger(subsystem: "WhatsThat.AudioGuides", category: "MiniPlayerView")

struct MiniPlayerView: View {
    @Environment(\.audioServices) private var services
    @Environment(\.colorScheme) var colorScheme
    
    /// Callback to switch to Audio Guides tab in hero mode
    var onExpand: () -> Void = {}
    
    // Layout Constants
    private var artworkDiameter: CGFloat {
        UIDevice.isIPad ? 168 : 110
    }
    
    private var backgroundHeight: CGFloat {
        UIDevice.isIPad ? 136 : 84
    }
    
    private let progressLineWidth: CGFloat = 3
    
    // MARK: - Body
    
    var body: some View {
        // Wrap in inner view that can properly observe the controller
        if let services {
            MiniPlayerContentView(
                controller: services.playbackController,
                queueStore: services.queueStore,
                audioServices: services,
                colorScheme: colorScheme,
                artworkDiameter: artworkDiameter,
                backgroundHeight: backgroundHeight,
                progressLineWidth: progressLineWidth,
                onExpand: onExpand,
                onHeightChange: { height in
                    services.miniPlayerPresence.updateHeight(height)
                }
            )
        }
    }
}

/// Inner view that properly observes the playback controller
private struct MiniPlayerContentView: View {
    @ObservedObject var controller: VoiceoverPlaybackController
    @ObservedObject var queueStore: AudioGuidesQueueStore
    let audioServices: AudioServicesContainer
    let colorScheme: ColorScheme
    let artworkDiameter: CGFloat
    let backgroundHeight: CGFloat
    let progressLineWidth: CGFloat
    var onExpand: () -> Void
    var onHeightChange: (CGFloat) -> Void
    
    // Swipe to dismiss state
    @State private var dragOffset: CGFloat = 0
    @State private var streamingRingRotation = Angle.zero
    private let dismissThreshold: CGFloat = 50
    
    // MARK: - Computed Properties
    
    private var discovery: DiscoverySummary? {
        controller.currentDiscovery
    }
    
    private var progress: Double {
        guard let duration = controller.duration, duration > 0 else { return 0 }
        return controller.position / duration
    }
    
    private var isPlaying: Bool {
        if case .playing = controller.playbackState { return true }
        return false
    }
    
    private var isCurrentStreamingReady: Bool {
        guard let id = controller.currentDiscovery?.id else { return false }
        return controller.assetStates[id]?.status == .streamingReady
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
        ZStack(alignment: .leading) {
            // 1. Background "Pill" Panel
            backgroundPill
            
            // 2. Content Area (Text & Controls)
            contentArea
            
            // 3. Hero Artwork & Progress Ring (Top Layer)
            artworkWithProgressRing
        }

        .frame(height: artworkDiameter)
        // iPad: Constrain width and center
        .frame(maxWidth: UIDevice.isIPad ? IPadLayout.miniPlayerMaxWidth : .infinity)
        .frame(maxWidth: .infinity, alignment: .center)
        // Swipe-to-dismiss gesture and animation
        .offset(y: dragOffset)
        .opacity(Double(1 - (dragOffset / (dismissThreshold * 2))))
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only allow downward drag
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > dismissThreshold {
                        // Dismiss with animation
                        pauseAndDismiss()
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MiniPlayerHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        )
        .onPreferenceChange(MiniPlayerHeightPreferenceKey.self) { height in
            onHeightChange(height)
        }
        .onChange(of: controller.currentDiscovery?.id) { oldId, newId in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                log.debug("[MiniPlayer] Discovery changed: \(oldId ?? -1) → \(newId ?? -1)")
                if let discovery = discovery {
                    log.debug("[MiniPlayer] New discovery: '\(discovery.title)', imagePath: \(discovery.imagePath ?? "nil")")
                }
            }
        }
        .onChange(of: controller.playbackState) { oldState, newState in
            // Defer to next runloop to prevent "update multiple times per frame" error
            DispatchQueue.main.async {
                log.debug("[MiniPlayer] Playback state: \(String(describing: oldState)) → \(String(describing: newState))")
            }
        }
        .onAppear {
            log.debug("[MiniPlayer] onAppear - discovery: \(discovery?.title ?? "nil"), state: \(String(describing: controller.playbackState))")
            if isCurrentStreamingReady {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    streamingRingRotation = .degrees(360)
                }
            }
        }
        .onChange(of: isCurrentStreamingReady) { _, isStreaming in
            if isStreaming {
                streamingRingRotation = .zero
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    streamingRingRotation = .degrees(360)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var backgroundPill: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(BrandTheme.palette(for: colorScheme).surface.opacity(0.95))
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(BrandTheme.palette(for: colorScheme).border, lineWidth: 0.5)
            )
            .frame(height: backgroundHeight)
            .padding(.leading, 20)
    }
    
    private var contentArea: some View {
        HStack(spacing: 0) {
            // Spacer to push content right of artwork
            Spacer()
                .frame(width: UIDevice.isIPad ? 170 : 108)
            
            if UIDevice.isIPad {
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Title (Marquee)
                HStack {
                    MarqueeText(
                        text: discovery?.title ?? "Select a guide",
                        font: .adaptiveSystem(size: 16, weight: .bold)
                    )
                    .frame(height: 26)
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                    Spacer(minLength: 0)
                }
                
                // Controls Row
                controlsRow
            }
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            
            if UIDevice.isIPad {
                Spacer()
            }
        }
        .frame(height: backgroundHeight)
        .padding(.leading, 20)
    }
    
    private var controlsRow: some View {
        HStack(spacing: 16) {
            // Back 5s
            Button(action: { controller.seek(by: -5) }) {
                Image(systemName: "gobackward.5")
                    .font(.adaptiveSystem(size: 18))
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
            }
            
            // Prev Track
            Button(action: playPrevious) {
                Image(systemName: "backward.end.fill")
                    .font(.adaptiveSystem(size: 20))
                    .foregroundColor(canPlayPrevious
                        ? BrandTheme.palette(for: colorScheme).textPrimary
                        : BrandTheme.palette(for: colorScheme).textSecondary.opacity(0.4))
            }
            .disabled(!canPlayPrevious)
            
            // Play/Pause Hero Button
            Button(action: togglePlayPause) {
                ZStack {
                    Circle()
                        .fill(BrandColors.logo)
                        .frame(width: UIDevice.isIPad ? 56 : 40, height: UIDevice.isIPad ? 56 : 40)
                        .shadow(color: BrandColors.logo.opacity(0.4), radius: 4, y: 2)
                    
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.adaptiveSystem(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            // Next Track
            Button(action: playNext) {
                Image(systemName: "forward.end.fill")
                    .font(.adaptiveSystem(size: 20))
                    .foregroundColor(canPlayNext
                        ? BrandTheme.palette(for: colorScheme).textPrimary
                        : BrandTheme.palette(for: colorScheme).textSecondary.opacity(0.4))
            }
            .disabled(!canPlayNext)
            
            // Fwd 5s (disabled during streaming)
            Button(action: { controller.seek(by: 5) }) {
                Image(systemName: "goforward.5")
                    .font(.adaptiveSystem(size: 18))
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
            }
            .opacity(isCurrentStreamingReady ? 0.3 : 1.0)
            .disabled(isCurrentStreamingReady)
        }
    }
    
    private var artworkWithProgressRing: some View {
        ZStack {
            // Background for ring to hide pill border line
            Circle()
                .fill(BrandTheme.palette(for: colorScheme).background)
                .frame(width: artworkDiameter, height: artworkDiameter)
            
            // Track Ring (Open Arc)
            Circle()
                .trim(from: 0.0, to: 0.8)
                .stroke(Color.black.opacity(0.3), style: StrokeStyle(lineWidth: progressLineWidth, lineCap: .round))
                .rotationEffect(Angle(degrees: 126))
                .frame(width: artworkDiameter, height: artworkDiameter)
            
            // Progress Ring (Open Arc) — indeterminate during streaming
            if isCurrentStreamingReady {
                Circle()
                    .trim(from: 0.0, to: 0.3)
                    .stroke(
                        BrandColors.logo,
                        style: StrokeStyle(lineWidth: progressLineWidth, lineCap: .round)
                    )
                    .rotationEffect(streamingRingRotation)
                    .frame(width: artworkDiameter, height: artworkDiameter)
            } else {
                Circle()
                    .trim(from: 0.0, to: progress * 0.8)
                    .stroke(
                        BrandColors.logo,
                        style: StrokeStyle(lineWidth: progressLineWidth, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: 126))
                    .frame(width: artworkDiameter, height: artworkDiameter)
            }

            // Artwork Image
            artworkImage
        }
        .padding(.leading, 0)
        .onTapGesture {
            onExpand()
        }
        .zIndex(1) // Explicitly force on top
    }
    
    @ViewBuilder
    private var artworkImage: some View {
        let size = artworkDiameter - (progressLineWidth * 3)
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
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                case .loading, .empty, .failure:
                    placeholderArtwork
                }
            }
            // Force view recreation when discovery changes to reload image
            .id("artwork-\(discovery.id)-\(imagePath)")
        } else {
            placeholderArtwork
        }
    }
    
    private var placeholderArtwork: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(
                width: artworkDiameter - (progressLineWidth * 3),
                height: artworkDiameter - (progressLineWidth * 3)
            )
    }
    
    // MARK: - Actions
    
    private func togglePlayPause() {
        guard let discovery else { return }
        controller.togglePlayback(for: discovery)
    }
    
    private func playNext() {
        let queueStore = audioServices.queueStore
        if let nextId = queueStore.next() {
            // Try controller's queue provider first (has all discoveries), then fall back to store
            if let discovery = controller.getDiscovery(id: nextId) {
                controller.togglePlayback(for: discovery)
            } else {
                Task {
                    if let discovery = await audioServices.discoveryStore.get(id: nextId) {
                        controller.togglePlayback(for: discovery)
                    } else {
                        print("[MiniPlayer.playNext] Could not find discovery for id=\(nextId)")
                    }
                }
            }
        }
    }
    
    private func playPrevious() {
        let queueStore = audioServices.queueStore
        let currentPosition = controller.position
        let currentId = queueStore.current
        
        print("[MiniPlayer.playPrevious] Called. Position=\(currentPosition), current=\(currentId ?? -1)")
        print("[MiniPlayer.playPrevious] baseList.count=\(queueStore.baseList.count), baseIndex=\(queueStore.baseIndex), history.count=\(queueStore.history.count)")
        print("[MiniPlayer.playPrevious] hasPrevious=\(queueStore.hasPrevious)")
        
        if let prevId = queueStore.previous(currentPosition: currentPosition) {
            print("[MiniPlayer.playPrevious] Got prevId=\(prevId)")
            // If previous() returns the same ID, it means "restart current"
            if prevId == currentId {
                print("[MiniPlayer.playPrevious] Same ID - seeking to 0")
                controller.seek(to: 0) {}
            } else {
                print("[MiniPlayer.playPrevious] Different ID - switching track")
                // Try controller's queue provider first (has all discoveries), then fall back to store
                if let discovery = controller.getDiscovery(id: prevId) {
                    print("[MiniPlayer.playPrevious] Found discovery from provider: \(discovery.title)")
                    controller.togglePlayback(for: discovery)
                } else {
                    Task {
                        if let discovery = await audioServices.discoveryStore.get(id: prevId) {
                            print("[MiniPlayer.playPrevious] Found discovery from store: \(discovery.title)")
                            controller.togglePlayback(for: discovery)
                        } else {
                            print("[MiniPlayer.playPrevious] Could not find discovery for id=\(prevId)")
                        }
                    }
                }
            }
        } else {
            print("[MiniPlayer.playPrevious] previous() returned nil!")
        }
    }
    
    private func pauseAndDismiss() {
        // Haptic feedback for dismissal
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        log.debug("[MiniPlayer] Swipe-to-dismiss triggered - pausing and hiding")
        
        // Animate off-screen first
        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = 200
        }
        
        // Pause playback and dismiss (preserves position and queue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            controller.pause()
            audioServices.miniPlayerPresence.dismiss()
            
            // Reset drag offset for next appearance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                dragOffset = 0
            }
        }
    }
}

// MARK: - Marquee Text (unchanged from original)

struct MarqueeText: View {
    let text: String
    let font: Font
    @State private var animate = false
    
    var body: some View {
        GeometryReader { geometry in
            let textWidth = text.width(usingFont: font)
            let parentWidth = geometry.size.width
            
            ZStack(alignment: .leading) {
                if textWidth > parentWidth {
                    Text(text)
                        .font(font)
                        .fixedSize()
                        .offset(x: animate ? -textWidth - 20 : 0)
                        .animation(
                            Animation.linear(duration: Double(textWidth) / 30)
                                .repeatForever(autoreverses: false)
                                .delay(1.0),
                            value: animate
                        )
                        .onAppear {
                            animate = true
                        }
                    
                     Text(text)
                        .font(font)
                        .fixedSize()
                        .offset(x: animate ? 0 : textWidth + 20)
                        .animation(
                            Animation.linear(duration: Double(textWidth) / 30)
                                .repeatForever(autoreverses: false)
                                .delay(1.0),
                            value: animate
                        )
                 } else {
                    Text(text)
                        .font(font)
                        .lineLimit(1)
                }
            }
        }
        .clipped()
    }
}

// Helper for text width calculation
extension String {
    func width(usingFont font: Font) -> CGFloat {
        let fontMultiplier: CGFloat = 10
        return CGFloat(self.count) * fontMultiplier
    }
}
