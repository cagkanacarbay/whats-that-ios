import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// Toast notification shown when a discovery completes in the background.
/// Always shows View button + a compact audio pill (matching DiscoveryAudioControls design).
struct DiscoveryCompletionToastView: View {
    let toast: DiscoveryCompletionToast
    let onViewDiscovery: () -> Void
    let onPlayNow: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    let onGenerateAudio: () -> Void
    let onDismiss: () -> Void
    
    /// Observed audio state for this discovery
    let audioState: AudioButtonState
    
    @Environment(\.colorScheme) var colorScheme
    
    /// Represents the audio button state based on voiceover asset status
    enum AudioButtonState: Equatable {
        case generating
        case ready
        case notGenerated
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // Header row with title and close button
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail
                thumbnailView
                
                // Title section
                VStack(alignment: .leading, spacing: 3) {
                    Text("Discovery ready!")
                        .font(.adaptiveSystem(size: 17, weight: .semibold))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                    
                    Text(toast.discovery.title)
                        .font(.adaptiveSystem(size: 14, weight: .regular))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Close button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.adaptiveSystem(size: 14, weight: .medium))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                        .padding(8)
                        .background(Circle().fill(Color.gray.opacity(0.15)))
                }
            }
            
            // Action buttons row - View button + Audio pill
            HStack(spacing: 12) {
                // View Discovery Button (always shown)
                Button(action: onViewDiscovery) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(BrandColors.logo)
                                .frame(width: UIDevice.isIPad ? 44 : 36, height: UIDevice.isIPad ? 44 : 36)
                            
                            Image(systemName: "eye.fill")
                                .font(.adaptiveSystem(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text("View")
                            .font(.adaptiveSystem(size: 16, weight: .semibold))
                            .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                    }
                }
                .buttonStyle(ScaleDiscoveryToastButtonStyle())
                
                Spacer()
                
                // Compact Audio Pill (matches DiscoveryAudioControls design)
                compactAudioPill
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(BrandTheme.palette(for: colorScheme).surface)
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: -4)
        )
        .padding(.horizontal, 16)
    }
    
    /// Compact audio pill that matches DiscoveryAudioControls design
    @ViewBuilder
    private var compactAudioPill: some View {
        HStack(spacing: 12) {
            // Left side: Icon + text based on state
            audioPillMainContent
            
            // Right side: Queue buttons (only when ready)
            if audioState == .ready {
                HStack(spacing: 4) {
                    queueButton(iconName: "text.insert", label: "Next", action: onPlayNext)
                    queueButton(iconName: "text.append", label: "Queue", action: onAddToQueue)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: UIDevice.isIPad ? 52 : 44)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(BrandTheme.palette(for: colorScheme).surface.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(BrandTheme.palette(for: colorScheme).border.opacity(0.3), lineWidth: 0.5)
                )
        )
    }
    
    @ViewBuilder
    private var audioPillMainContent: some View {
        Button(action: handleAudioMainAction) {
            HStack(spacing: 8) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(BrandColors.logo)
                        .frame(width: UIDevice.isIPad ? 44 : 36, height: UIDevice.isIPad ? 44 : 36)
                    
                    audioPillIcon
                        .foregroundColor(.white)
                }
                
                // Label text
                Text(audioPillLabel)
                    .font(.adaptiveSystem(size: UIDevice.isIPad ? 18 : 16, weight: .semibold))
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(audioState == .generating)
    }
    
    @ViewBuilder
    private var audioPillIcon: some View {
        switch audioState {
        case .generating:
            ProgressView()
                .tint(.white)
                .scaleEffect(0.7)
        case .ready:
            Image(systemName: "play.fill")
                .font(.adaptiveSystem(size: UIDevice.isIPad ? 20 : 16, weight: .bold))
                .offset(x: 1)
        case .notGenerated:
            Image(systemName: "sparkles")
                .font(.adaptiveSystem(size: UIDevice.isIPad ? 20 : 16, weight: .bold))
        }
    }
    
    private var audioPillLabel: String {
        switch audioState {
        case .generating:
            return "Generating..."
        case .ready:
            return "Play"
        case .notGenerated:
            return "Generate Audio"
        }
    }
    
    private func handleAudioMainAction() {
        switch audioState {
        case .ready:
            onPlayNow()
        case .notGenerated:
            onGenerateAudio()
        case .generating:
            break // Disabled
        }
    }
    
    @ViewBuilder
    private func queueButton(iconName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: iconName)
                    .font(.adaptiveSystem(size: 14, weight: .semibold))
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                
                Text(label)
                    .font(.adaptiveSystem(size: 9, weight: .medium))
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
            }
            .frame(width: 40, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var thumbnailView: some View {
        if let imagePath = toast.discovery.imagePath,
           let imageURL = URL(string: imagePath) {
            DiscoveryCachedImage(
                discoveryId: toast.discovery.id,
                remoteURL: imageURL
            ) { phase in
                switch phase {
                case .success(let platformImage):
                    Image(uiImage: platformImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: UIDevice.isIPad ? 80 : 60, height: UIDevice.isIPad ? 80 : 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                case .loading, .empty, .failure:
                    placeholderThumbnail
                }
            }
        } else {
            placeholderThumbnail
        }
    }
    
    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.gray.opacity(0.3))
            .frame(width: UIDevice.isIPad ? 80 : 60, height: UIDevice.isIPad ? 80 : 60)
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(.gray)
            )
    }
}

// Private button style for toast actions
private struct ScaleDiscoveryToastButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
