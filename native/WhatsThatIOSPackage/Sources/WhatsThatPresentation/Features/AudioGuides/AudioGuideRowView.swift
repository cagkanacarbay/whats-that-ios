import SwiftUI
import WhatsThatShared

struct AudioGuideRowView: View {
    let guide: AudioGuide
    let isPlaying: Bool
    let onPlay: () -> Void
    let onOpenPlayer: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let doubleTap = TapGesture(count: 2)
            .onEnded {
                onOpenPlayer()
            }
        let singleTap = TapGesture()
            .onEnded {
                onPlay()
            }
        
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                Image(guide.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .cornerRadius(8)
                    .clipped()
                
                if isPlaying {
                    Color.black.opacity(0.3)
                        .cornerRadius(8)
                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            
            // Text Info
            VStack(alignment: .leading, spacing: 4) {
                Text(guide.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(isPlaying ? BrandColors.logo : BrandTheme.palette(for: colorScheme).textPrimary)
                    .lineLimit(2)
                
                HStack(spacing: 6) {
                    if guide.isAuto {
                        Text("AUTO")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(BrandColors.logo.opacity(0.2))
                            .foregroundColor(BrandColors.logo)
                            .cornerRadius(4)
                    }
                    
                    Text(guide.durationString)
                        .font(.caption)
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                }
            }
            
            Spacer()
            
            // More Action
            Image(systemName: "ellipsis")
                .rotationEffect(Angle(degrees: 90))
                .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isPlaying ? BrandColors.logo.opacity(0.08) : Color.clear)
                .cornerRadius(12)
        )
        .contentShape(Rectangle())
        .gesture(
            doubleTap.exclusively(before: singleTap)
        )
    }
}
