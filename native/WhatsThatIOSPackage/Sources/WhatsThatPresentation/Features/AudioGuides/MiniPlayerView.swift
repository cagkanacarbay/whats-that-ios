import SwiftUI
import WhatsThatShared

struct MiniPlayerView: View {
    @ObservedObject var viewModel: AudioGuidesViewModel
    @Environment(\.colorScheme) var colorScheme
    var onExpand: () -> Void = {}
    
    // Layout Constants
    private let artworkDiameter: CGFloat = 110
    private let backgroundHeight: CGFloat = 84
    private let progressLineWidth: CGFloat = 3
    
    var body: some View {
        ZStack(alignment: .leading) {
            // 1. Background "Pill" Panel
            RoundedRectangle(cornerRadius: 20)
                .fill(BrandTheme.palette(for: colorScheme).surface.opacity(0.95))
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(BrandTheme.palette(for: colorScheme).border, lineWidth: 0.5)
                )
                .frame(height: backgroundHeight)
                .padding(.leading, 20)
            
            // 2. Content Area (Text & Controls)
            HStack(spacing: 0) {
                // Rigid spacer to push content right, aligning title start with the first control button
                // Artwork is 110, pill starts at 20. Overhang is ~35.
                // We want the text to start aligned with the -5s button.
                // Increasing this spacer ensures the text doesn't start too close to the artwork.
                Spacer()
                    .frame(width: 108) 
                
                VStack(alignment: .leading, spacing: 6) {
                    // Title (Marquee)
                    // Wrapped in GeometryReader to ensure it respects the available width
                    HStack {
                        MarqueeText(text: viewModel.currentGuide?.title ?? "Select a guide", font: .system(size: 16, weight: .bold))
                            .frame(height: 22)
                            .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                            // Critical: Clip to prevent sliding under artwork
                            .clipped() 
                        Spacer(minLength: 0)
                    }
                    
                    // Controls Row (Left-aligned to match title start)
                    HStack(spacing: 16) {
                        // Back 5s
                        Button(action: { viewModel.skipBackward5() }) {
                            Image(systemName: "gobackward.5")
                                .font(.system(size: 18))
                                .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                        }
                        
                        // Prev Track
                        Button(action: { viewModel.handleBackButtonTap() }) {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: 20))
                                .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                        }
                        
                        // Play/Pause Hero Button
                        Button(action: { viewModel.togglePlayPause() }) {
                            ZStack {
                                Circle()
                                    .fill(BrandColors.logo)
                                    .frame(width: 40, height: 40)
                                    .shadow(color: BrandColors.logo.opacity(0.4), radius: 4, y: 2)
                                
                                Image(systemName: viewModel.playbackState == .playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Next Track
                        Button(action: { viewModel.playNext() }) {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 20))
                                .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                        }
                        
                        // Fwd 5s
                        Button(action: { viewModel.skipForward5() }) {
                            Image(systemName: "goforward.5")
                                .font(.system(size: 18))
                                .foregroundColor(BrandTheme.palette(for: colorScheme).textSecondary)
                        }
                    }
                }
                .padding(.trailing, 16)
                .padding(.vertical, 8)
            }
            .frame(height: backgroundHeight)
            .padding(.leading, 20)
            
            // 3. Hero Artwork & Progress Ring (Top Layer)
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
                
                // Progress Ring (Open Arc)
                Circle()
                    .trim(from: 0.0, to: viewModel.progress * 0.8)
                    .stroke(
                        BrandColors.logo,
                        style: StrokeStyle(lineWidth: progressLineWidth, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: 126))
                    .frame(width: artworkDiameter, height: artworkDiameter)
                
                // Artwork Image
                if let guide = viewModel.currentGuide {
                    Image(guide.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: artworkDiameter - (progressLineWidth * 3), height: artworkDiameter - (progressLineWidth * 3))
                        .clipShape(Circle())
                }
            }
            .padding(.leading, 0) 
            .onTapGesture {
                onExpand()
            }
            .zIndex(1) // Explicitly force on top
        }
        .frame(height: artworkDiameter) 
    }
}

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
        .clipped() // Ensure the marquee itself doesn't bleed
    }
}

// Helper for text width calculation
extension String {
    func width(usingFont font: Font) -> CGFloat {
        let fontMultiplier: CGFloat = 10 
        return CGFloat(self.count) * fontMultiplier 
    }
}
