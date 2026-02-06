import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct DiscoveryCardView: View {
    let discovery: DiscoverySummary
    let width: CGFloat
    let height: CGFloat
    let isHidden: Bool
    let isDeleting: Bool
    let onSelect: (DiscoverySummary, URL?, CGRect) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let cardCornerRadius: CGFloat = BrandCornerRadius.large

    /// Whether this card appeared recently enough to show the intro spinner.
    @State private var showIntroSpinner = false
    @State private var isSpinning = false
    @State private var lastFrame: CGRect = .zero

    init(
        discovery: DiscoverySummary,
        width: CGFloat,
        height: CGFloat,
        isHidden: Bool,
        isDeleting: Bool = false,
        onSelect: @escaping (DiscoverySummary, URL?, CGRect) -> Void
    ) {
        self.discovery = discovery
        self.width = width
        self.height = height
        self.isHidden = isHidden
        self.isDeleting = isDeleting
        self.onSelect = onSelect
    }

    var body: some View {
        Button {
            guard !isDeleting, !showIntroSpinner else { return }
            onSelect(discovery, imageURL, self.lastFrame)
        } label: {
            ZStack(alignment: .bottom) {
                DiscoveryCardImageView(
                    discoveryId: discovery.id,
                    url: imageURL,
                    width: width,
                    height: height
                )
                .opacity(isDeleting ? 0.5 : (showIntroSpinner ? 0 : 1.0))

                if showIntroSpinner {
                    introSpinnerOverlay
                } else {
                    DiscoveryCardChrome(discovery: discovery)
                        .opacity(isDeleting ? 0.3 : 1.0)
                }

                if isDeleting {
                    DeletingOverlayView()
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.3)
            }
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .background(
                GeometryReader { proxy in
                     Color.clear
                        .onAppear { self.lastFrame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                            self.lastFrame = newFrame
                        }
                }
            )
        }
        .buttonStyle(.plain)
        .opacity(isHidden ? 0 : 1)
        .disabled(isDeleting)
        .animation(.easeInOut(duration: 0.25), value: isDeleting)
        .onAppear {
            // Show intro spinner for discoveries created in the last 15 seconds
            let age = Date().timeIntervalSince(discovery.capturedAt)
            if age < 15 {
                showIntroSpinner = true
                isSpinning = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showIntroSpinner = false
                    }
                }
            }
        }
    }

    // MARK: - Intro Spinner

    private var introSpinnerOverlay: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#20293A"),
                    Color(hex: "#141927")
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ZStack {
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
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        .linear(duration: 1.2).repeatForever(autoreverses: false),
                        value: isSpinning
                    )

                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Helpers

    private var imageURL: URL? {
        guard let path = discovery.imagePath else { return nil }
        return URL(string: path)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : BrandColors.Light.border
    }
}

private struct DiscoveryCardChrome: View {
    let discovery: DiscoverySummary

    var body: some View {
        VStack(spacing: 4) {
            Text(discovery.title)
                .font(.adaptiveSystem(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .shadow(color: Color.black.opacity(0.6), radius: 3, x: 0, y: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.25),
                    Color.black.opacity(0.4)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
