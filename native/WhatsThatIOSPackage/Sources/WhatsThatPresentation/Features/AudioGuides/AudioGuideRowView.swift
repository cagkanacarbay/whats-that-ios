import SwiftUI
import WhatsThatShared

struct AudioGuideRowView<MenuContent: View>: View {
    let guide: AudioGuide
    let isPlaying: Bool
    let progress: Double?
    var showMenu: Bool = true
    var isRecentlyQueued: Bool = false
    let onPlay: () -> Void
    let onOpenPlayer: () -> Void
    var onCreate: (() -> Void)? = nil
    @ViewBuilder let menuContent: () -> MenuContent
    
    @Environment(\.colorScheme) var colorScheme
    
    private var backgroundColor: Color {
        if isPlaying {
            return BrandColors.logo.opacity(0.08)
        } else {
            return Color.clear
        }
    }

    private var contentOpacity: Double {
        (guide.status == .empty || guide.status == .failed || guide.status == .generating) ? 0.5 : 1.0
    }
    
    var body: some View {
        let thumbnailSize: CGFloat = 56
        let isReady = guide.status == .ready
        
        // Gestures for Ready state
        let doubleTap = TapGesture(count: 2)
            .onEnded { if isReady { onOpenPlayer() } }
        let singleTap = TapGesture()
            .onEnded { if isReady { onPlay() } }
        
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                Image(guide.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: thumbnailSize, height: thumbnailSize)
                
                if isPlaying {
                    Color.black.opacity(0.3)
                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundColor(.white)
                } else if guide.status == .generating {
                    Color.black.opacity(0.4)
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                } else if guide.status == .failed {
                    Color.black.opacity(0.4)
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                } else if guide.status == .empty {
                    Color.black.opacity(0.2)
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Text Info
            VStack(alignment: .leading, spacing: 4) {
                Text(guide.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(isPlaying ? BrandColors.logo : BrandTheme.palette(for: colorScheme).textPrimary)
                    .lineLimit(2)
                
                HStack(spacing: 6) {
                    if isReady {
                        Text(guide.durationString)
                            .font(.caption)
                            .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                    } else if guide.status == .generating {
                        Text("Generating...")
                             .font(.caption)
                             .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                    } else if guide.status == .empty {
                        Text("No audio guide")
                             .font(.caption)
                             .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                    } else if guide.status == .failed {
                         Text("Failed to generate")
                             .font(.caption)
                             .foregroundColor(.red.opacity(0.8))
                    }
                }
                
                if isReady, let progress = progress, progress > 0 {
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
            }
            
            Spacer()
            
            // More Action
            if isRecentlyQueued {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(BrandColors.logo)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
            } else if showMenu && isReady {
                Menu {
                    menuContent()
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(Angle(degrees: 90))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            backgroundColor.cornerRadius(12)
        )
        .opacity(contentOpacity)
        .contentShape(Rectangle())
        .onTapGesture {
            if guide.status == .empty || guide.status == .failed {
                onCreate?()
            }
        }
        .gesture(
            isReady ? doubleTap.exclusively(before: singleTap) : nil
        )
    }
}
