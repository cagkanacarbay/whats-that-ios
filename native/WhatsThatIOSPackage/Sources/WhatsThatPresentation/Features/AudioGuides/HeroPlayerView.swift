import SwiftUI
import WhatsThatShared

struct HeroPlayerView: View {
    @ObservedObject var viewModel: AudioGuidesViewModel
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            // Main Circular Player
            ZStack {
                // Background Circle
                Circle()
                    .stroke(BrandColors.Light.secondaryAction.opacity(0.3), lineWidth: 4)
                    .frame(width: 240, height: 240)
                
                // Progress Ring
                Circle()
                    .trim(from: 0.0, to: viewModel.progress)
                    .stroke(
                        BrandColors.logo,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: -90))
                    .frame(width: 240, height: 240)
                
                // Artwork
                if let guide = viewModel.currentGuide {
                    Image(guide.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 220, height: 220)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 220, height: 220)
                }
            }
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
            .overlay(alignment: .bottom) {
                HStack {
                    Text(viewModel.currentTimeString)
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                    
                    Spacer()
                    
                    Text(viewModel.currentGuide?.durationString ?? "--:--")
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                }
                .frame(width: 280) // Slightly wider than the circle
                .offset(y: 40)
            }
            
            // Meta Info
            VStack(spacing: 8) {
                Text(viewModel.currentGuide?.title ?? "Select a guide")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                    .padding(.horizontal)
                    .padding(.top, 20) // Add padding to account for time labels
            }
            
            // Controls
            HStack(spacing: 24) {
                // -5s
                Button(action: { viewModel.skipBackward5() }) {
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 20))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                }
                
                // Prev
                Button(action: { viewModel.playPrevious() }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 24))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                }
                
                // Play/Pause
                Button(action: { viewModel.togglePlayPause() }) {
                    Image(systemName: viewModel.playbackState == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(BrandColors.logo)
                        .shadow(color: BrandColors.logo.opacity(0.3), radius: 10, x: 0, y: 4)
                }
                
                // Next
                Button(action: { viewModel.playNext() }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 24))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                }
                
                // +5s
                Button(action: { viewModel.skipForward5() }) {
                    Image(systemName: "goforward.5")
                        .font(.system(size: 20))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                }
            }
            .padding(.bottom, 20)
        }
    }
}
