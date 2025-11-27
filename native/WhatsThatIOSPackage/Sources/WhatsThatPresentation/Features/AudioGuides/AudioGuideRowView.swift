import SwiftUI
import WhatsThatShared

struct AudioGuideRowView: View {
    let guide: AudioGuide
    let isPlaying: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
