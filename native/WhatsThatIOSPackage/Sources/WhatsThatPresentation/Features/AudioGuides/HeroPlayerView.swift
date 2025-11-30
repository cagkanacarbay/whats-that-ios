import SwiftUI
import WhatsThatShared

struct HeroPlayerView: View {
    @ObservedObject var viewModel: AudioGuidesViewModel
    @State private var showAutoplayInfo = false
    @State private var selectedMode = "Audio"
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            // Mode Switcher Pill
            HStack(spacing: 0) {
                Button(action: { selectedMode = "Text" }) {
                    Text("Text")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(width: 80, height: 32)
                        .foregroundColor(selectedMode == "Text" ? BrandTheme.palette(for: colorScheme).textPrimary : BrandTheme.palette(for: colorScheme).textSecondary)
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
                        .foregroundColor(selectedMode == "Audio" ? BrandTheme.palette(for: colorScheme).textPrimary : BrandTheme.palette(for: colorScheme).textSecondary)
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
            
            // Main Circular Player
            ZStack {
                // Background Circle
                Circle()
                    .trim(from: 0.0, to: 0.8)
                    .stroke(BrandColors.Light.secondaryAction.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(126))
                    .frame(width: 300, height: 300)
                
                // Progress Ring
                Circle()
                    .trim(from: 0.0, to: viewModel.progress * 0.8)
                    .stroke(
                        BrandColors.logo,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(126))
                    .frame(width: 300, height: 300)
                
                // Artwork
                if let guide = viewModel.currentGuide {
                    Image(guide.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 264, height: 264)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 264, height: 264)
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
                .frame(width: 240)
                .offset(y: 5)
            }
            
            // Meta Info
            VStack(spacing: 8) {
                Text(viewModel.currentGuide?.title ?? "Select a guide")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                    .padding(.horizontal)
                    .padding(.top, 5) // Add padding to account for time labels
            }
            
            // Controls
            HStack(spacing: 24) {
                // Prev
                Button(action: { viewModel.playPrevious() }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 24))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                }
                
                // -5s
                Button(action: { viewModel.skipBackward5() }) {
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 24))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                }
                
                // Play/Pause
                Button(action: { viewModel.togglePlayPause() }) {
                    Image(systemName: viewModel.playbackState == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(BrandColors.logo)
                        .shadow(color: BrandColors.logo.opacity(0.3), radius: 10, x: 0, y: 4)
                }
                
                // +5s
                Button(action: { viewModel.skipForward5() }) {
                    Image(systemName: "goforward.5")
                        .font(.system(size: 24))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                }
                
                // Next
                Button(action: { viewModel.playNext() }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 24))
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                }
            }
            .padding(.bottom, 10)
            
            // Autoplay and Speed Control Row
            HStack {
                // Autoplay Toggle (Left)
                HStack(spacing: 8) {
                    Toggle("", isOn: $viewModel.autoplayEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: BrandColors.logo))
                    
                    Text("Autoplay next discovery")
                        .font(.subheadline)
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                    
                    Button(action: { showAutoplayInfo = true }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                            .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                    }
                }
                
                Spacer()
                
                // Speed Control (Right)
                VStack(spacing: 2) {
                    Menu {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                            Button {
                                viewModel.playbackSpeed = speed
                            } label: {
                                if viewModel.playbackSpeed == speed {
                                    Label("\(speed.formatted())x", systemImage: "checkmark")
                                } else {
                                    Text("\(speed.formatted())x")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(viewModel.playbackSpeed.formatted())x")
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
            }
            .padding(.horizontal, 16) // Ensure it doesn't touch the edges
            .alert("Autoplay", isPresented: $showAutoplayInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("It will play the next made discovery unless there is something else in the queue.")
            }
        }
    }
}
