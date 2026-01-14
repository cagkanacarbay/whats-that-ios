import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// Toast notification shown when audio guide generation completes
struct GenerationCompleteToastView: View {
    let toast: GenerationCompleteToast
    let onPlayNow: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 10) {
            // Header row with title and close button
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail - larger to use available space
                thumbnailView
                
                // Title section - fixed sizes, larger heading
                VStack(alignment: .leading, spacing: 3) {
                    Text("Audio guide ready!")
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
            
            // Action buttons row
            HStack(spacing: 12) {
                // Main Action Button (Play Now) - Discovery Detail style
                Button(action: onPlayNow) {
                    HStack(spacing: 8) {
                        // Icon Circle - matches Discovery Detail controls
                        ZStack {
                            Circle()
                                .fill(BrandColors.logo)
                                .frame(width: UIDevice.isIPad ? 44 : 36, height: UIDevice.isIPad ? 44 : 36)
                            
                            Image(systemName: "play.fill")
                                .font(.adaptiveSystem(size: 16, weight: .bold))
                                .offset(x: 1)
                                .foregroundColor(.white)
                        }
                        
                        Text("Play Now")
                            .font(.adaptiveSystem(size: 16, weight: .semibold))
                            .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                    }
                }
                .buttonStyle(ScaleToastButtonStyle())
                
                Spacer()
                
                // Queue Buttons - Right side
                HStack(spacing: 16) {
                    // Play Next Button
                    Button(action: onPlayNext) {
                        VStack(spacing: 4) {
                            Image(systemName: "text.insert")
                                .font(.adaptiveSystem(size: 18, weight: .semibold))
                                .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                            
                            Text("Next")
                                .font(.adaptiveSystem(size: 10, weight: .medium))
                                .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                        }
                        .frame(width: 50)
                    }
                    .buttonStyle(ScaleToastButtonStyle())
                    
                    // Add to End Button
                    Button(action: onAddToQueue) {
                        VStack(spacing: 4) {
                            Image(systemName: "text.append")
                                .font(.adaptiveSystem(size: 18, weight: .semibold))
                                .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                            
                            Text("Queue")
                                .font(.adaptiveSystem(size: 10, weight: .medium))
                                .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                        }
                        .frame(width: 50)
                    }
                    .buttonStyle(ScaleToastButtonStyle())
                }
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
                Image(systemName: "waveform")
                    .foregroundColor(.gray)
            )
    }
}

// Private button style for toast actions
private struct ScaleToastButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

