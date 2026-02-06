import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// A compact thumbnail cell for an in-progress discovery session.
/// Shown in a horizontal strip above the discoveries grid.
struct InProgressDiscoveryRow: View {
    let item: InProgressItem
    let size: CGFloat
    let onTap: () -> Void
    let onDismissFailure: (() -> Void)?

    @State private var isSpinning = false
    @State private var showTick = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                thumbnailImage
                statusOverlay
            }
            .frame(width: size, height: size * 1.2)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.3)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: item.status) { _, newStatus in
            if case .completed = newStatus {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    showTick = true
                }
            }
        }
        .onAppear {
            if case .completed = item.status {
                showTick = true
            }
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailImage: some View {
        if let uiImage = UIImage(data: item.thumbnailData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size * 1.2)
                .saturation(isQueued ? 0.0 : 1.0)
                .opacity(isQueued ? 0.4 : 1.0)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: size, height: size * 1.2)
        }
    }

    // MARK: - Status Overlay

    @ViewBuilder
    private var statusOverlay: some View {
        switch item.status {
        case .processing:
            processingOverlay

        case .queued:
            EmptyView()

        case .completed:
            completedOverlay

        case .failed:
            failedOverlay
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)

            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            BrandColors.spinner.opacity(0.1),
                            BrandColors.spinner
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 22, height: 22)
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                    .linear(duration: 1.2).repeatForever(autoreverses: false),
                    value: isSpinning
                )
                .onAppear { isSpinning = true }
        }
    }

    private var completedOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)

            if showTick {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(BrandColors.logo)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var failedOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Helpers

    @Environment(\.colorScheme) private var colorScheme

    private var isQueued: Bool {
        if case .queued = item.status { return true }
        return false
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : BrandColors.Light.border
    }
}
