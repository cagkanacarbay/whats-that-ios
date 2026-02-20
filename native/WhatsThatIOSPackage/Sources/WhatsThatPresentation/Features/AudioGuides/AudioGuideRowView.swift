import SwiftUI
import WhatsThatShared
import WhatsThatDomain

/// Row view for an audio guide, using DiscoverySummary and AudioGuideRowState
struct AudioGuideRowView<MenuContent: View>: View {
    let discovery: DiscoverySummary
    let state: AudioGuideRowState
    var showMenu: Bool = true
    var isRecentlyQueued: Bool = false
    
    /// Tap on ready guide to play
    let onPlay: () -> Void
    /// Long-press on ready guide to open hero player (accessibility replacement for double-tap)
    let onOpenPlayer: () -> Void
    /// Tap on empty/failed state to trigger generation
    var onCreate: (() -> Void)? = nil
    /// Menu content builder
    @ViewBuilder let menuContent: () -> MenuContent
    
    @Environment(\.colorScheme) var colorScheme
    @State private var streamingRotation = Angle.zero

    // MARK: - Computed Properties
    
    private var isReady: Bool {
        state.voiceoverStatus.isPlayable
    }
    
    private var backgroundColor: Color {
        if state.isPlaying {
            return BrandColors.logo.opacity(0.08)
        } else {
            return Color.clear
        }
    }

    private var contentOpacity: Double {
        switch state.voiceoverStatus {
        case .empty, .failed, .generating, .generationQueued, .checking:
            return 0.5
        case .ready, .streamingReady:
            return 1.0
        }
    }
    
    private var durationString: String? {
        if case .ready(let duration) = state.voiceoverStatus, let duration {
            let minutes = Int(duration) / 60
            let secs = Int(duration) % 60
            return String(format: "%d:%02d", minutes, secs)
        }
        return nil
    }
    
    // MARK: - Body
    
    var body: some View {
        let thumbnailSize: CGFloat = UIDevice.isIPad ? 80 : 56
        
        HStack(spacing: 12) {
            // Thumbnail with overlay for status
            thumbnailView(size: thumbnailSize)
            
            // Text Info
            VStack(alignment: .leading, spacing: 4) {
                Text(discovery.title)
                    .font(.adaptiveSystem(size: 16, weight: .medium))
                    .foregroundColor(state.isPlaying ? BrandColors.logo : BrandTheme.palette(for: colorScheme).textPrimary)
                    .lineLimit(2)
                
                statusLabel
                
                // Progress bar for ready items with progress
                if isReady, let progress = state.progress, progress > 0 {
                    progressBar(progress: progress)
                }
            }
            
            Spacer()
            
            // Trailing action
            trailingAction
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            backgroundColor.cornerRadius(12)
        )
        .overlay(alignment: .leading) {
            if state.isFreshlyReady {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(BrandColors.logo)
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    .transition(.opacity)
            }
        }
        .opacity(contentOpacity)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            if isReady {
                onOpenPlayer()
            }
        }
        .onAppear {
            if case .streamingReady = state.voiceoverStatus {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    streamingRotation = .degrees(360)
                }
            }
        }
        .onChange(of: state.voiceoverStatus) { newStatus in
            if case .streamingReady = newStatus {
                streamingRotation = .zero
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    streamingRotation = .degrees(360)
                }
            }
        }
    }
    
    // MARK: - Thumbnail View
    
    @ViewBuilder
    private func thumbnailView(size: CGFloat) -> some View {
        ZStack {
            // Image from discovery with caching
            if let imagePath = discovery.imagePath,
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
                    case .loading, .empty, .failure:
                        placeholderImage(size: size)
                    }
                }
            } else {
                placeholderImage(size: size)
            }
            
            // Status overlay
            statusOverlay
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func placeholderImage(size: CGFloat) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: size, height: size)
    }
    
    @ViewBuilder
    private var statusOverlay: some View {
        if state.isPlaying {
            Color.black.opacity(0.3)
            Image(systemName: "waveform")
                .font(UIDevice.isIPad ? .title : .title3)
                .foregroundColor(.white)
        } else {
            switch state.voiceoverStatus {
            case .generating, .generationQueued:
                Color.black.opacity(0.4)
                ProgressView()
                    .tint(BrandColors.spinner)
                    .scaleEffect(0.85)
            case .checking:
                Color.black.opacity(0.3)
                ProgressView()
                    .tint(BrandColors.spinner)
                    .controlSize(.small)
            case .failed:
                Color.black.opacity(0.4)
                Image(systemName: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(.white)
            case .empty:
                Color.black.opacity(0.2)
                Image(systemName: "sparkles")
                    .font(.headline)
                    .foregroundColor(.white)
            case .streamingReady:
                Color.black.opacity(0.3)
                ZStack {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(BrandColors.logo, lineWidth: 2)
                        .frame(width: 28, height: 28)
                        .rotationEffect(streamingRotation)
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .offset(x: 1)
                }
            case .ready:
                EmptyView()
            }
        }
    }
    
    // MARK: - Status Label
    
    @ViewBuilder
    private var statusLabel: some View {
        HStack(spacing: 6) {
            switch state.voiceoverStatus {
            case .ready:
                if state.isFreshlyReady {
                    Text("Ready")
                        .font(.adaptiveSystem(size: 14, weight: .medium))
                        .foregroundColor(BrandColors.logo)
                } else if let duration = durationString {
                    Text(duration)
                        .font(.adaptiveSystem(size: 14))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                }

                // Show "Queued" chip if in queue but not playing
                if state.isQueued && !state.isPlaying {
                    Text("Queued")
                        .font(.adaptiveSystem(size: 14))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BrandColors.logo.opacity(0.15))
                        .foregroundColor(BrandColors.logo)
                        .clipShape(Capsule())
                }
                
            case .streamingReady:
                Text("Ready")
                    .font(.adaptiveSystem(size: 14, weight: .medium))
                    .foregroundColor(BrandColors.logo)

            case .generating:
                Text("Generating...")
                    .font(.adaptiveSystem(size: 14))
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                    
            case .generationQueued:
                Text("Generation queued")
                    .font(.adaptiveSystem(size: 14))
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                    
            case .checking:
                HStack(spacing: 4) {
                    ProgressView()
                        .tint(BrandColors.spinner)
                        .controlSize(.mini)
                    Text("Checking...")
                        .font(.adaptiveSystem(size: 14))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                }
                    
            case .empty:
                Text("No audio guide")
                    .font(.adaptiveSystem(size: 14))
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                    
            case .failed:
                Text("Failed to generate")
                    .font(.adaptiveSystem(size: 14))
                    .foregroundColor(.red.opacity(0.8))
            }
        }
    }
    
    // MARK: - Progress Bar
    
    private func progressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 3)
                Capsule()
                    .fill(BrandColors.logo)
                    .frame(width: geo.size.width * progress, height: 3)
            }
        }
        .frame(height: 3)
        .padding(.top, 2)
    }
    
    // MARK: - Trailing Action
    
    @ViewBuilder
    private var trailingAction: some View {
        if isRecentlyQueued {
            Image(systemName: "checkmark.circle.fill")
                .font(UIDevice.isIPad ? .adaptiveSystem(size: 28) : .system(size: 22))
                .foregroundColor(BrandColors.logo)
                .padding(8)
                .transition(.scale.combined(with: .opacity))
        } else if showMenu && isReady {
            Menu {
                menuContent()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.adaptiveSystem(size: 20))
                    .rotationEffect(Angle(degrees: 90))
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleTap() {
        switch state.voiceoverStatus {
        case .ready, .streamingReady:
            onPlay()
        case .empty, .failed:
            onCreate?()
        case .generating, .generationQueued, .checking:
            break
        }
    }
}

// MARK: - Convenience Initializer (no menu)

extension AudioGuideRowView where MenuContent == EmptyView {
    init(
        discovery: DiscoverySummary,
        state: AudioGuideRowState,
        showMenu: Bool = false,
        isRecentlyQueued: Bool = false,
        onPlay: @escaping () -> Void,
        onOpenPlayer: @escaping () -> Void,
        onCreate: (() -> Void)? = nil
    ) {
        self.discovery = discovery
        self.state = state
        self.showMenu = showMenu
        self.isRecentlyQueued = isRecentlyQueued
        self.onPlay = onPlay
        self.onOpenPlayer = onOpenPlayer
        self.onCreate = onCreate
        self.menuContent = { EmptyView() }
    }
}
