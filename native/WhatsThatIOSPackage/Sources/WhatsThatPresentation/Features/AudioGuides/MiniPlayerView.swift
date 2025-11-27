import SwiftUI
import WhatsThatShared

struct MiniPlayerView: View {
    @ObservedObject var viewModel: AudioGuidesViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Mini Artwork & Progress
            ZStack {
                Circle()
                    .stroke(BrandColors.Light.secondaryAction.opacity(0.3), lineWidth: 2)
                    .frame(width: 40, height: 40)
                
                Circle()
                    .trim(from: 0.0, to: viewModel.progress)
                    .stroke(
                        BrandColors.logo,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: -90))
                    .frame(width: 40, height: 40)
                
                if let guide = viewModel.currentGuide {
                    Image(guide.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())
                }
            }
            
            // Title
            Text(viewModel.currentGuide?.title ?? "Select a guide")
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
            
            Spacer()
            
            // Controls
            HStack(spacing: 16) {
                Button(action: { viewModel.skipBackward5() }) {
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 20))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                }
                
                Button(action: { viewModel.togglePlayPause() }) {
                    Image(systemName: viewModel.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(BrandTheme.palette(for: colorScheme).surface.opacity(0.95))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BrandTheme.palette(for: colorScheme).border, lineWidth: 1)
        )
    }
}
