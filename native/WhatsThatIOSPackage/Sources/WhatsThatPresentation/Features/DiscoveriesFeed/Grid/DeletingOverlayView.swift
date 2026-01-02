import SwiftUI
import WhatsThatShared

/// Overlay shown on a discovery card while deletion is in progress.
/// Displays a faded trash icon with an animated orange ring spinner.
struct DeletingOverlayView: View {
    @State private var isAnimating = false
    
    private let iconSize: CGFloat = 32
    private let ringSize: CGFloat = 56
    private let ringLineWidth: CGFloat = 3
    
    var body: some View {
        ZStack {
            // Semi-transparent dark overlay
            Color.black.opacity(0.5)
            
            // Trash icon with animated ring
            ZStack {
                // Animated ring
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        BrandColors.Light.tabSelected,
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(
                        .linear(duration: 1.0).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                
                // Faded trash icon
                Image(systemName: "trash.fill")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    DeletingOverlayView()
        .frame(width: 150, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16))
}
