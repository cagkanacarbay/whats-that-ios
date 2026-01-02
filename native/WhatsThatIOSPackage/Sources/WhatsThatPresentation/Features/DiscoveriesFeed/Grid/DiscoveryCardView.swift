import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct DiscoveryCardView: View {
    let discovery: DiscoverySummary
    let width: CGFloat
    let height: CGFloat
    let isHidden: Bool
    let isDeleting: Bool
    let onSelect: (DiscoverySummary, URL?) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let cardCornerRadius: CGFloat = BrandCornerRadius.large

    init(
        discovery: DiscoverySummary,
        width: CGFloat,
        height: CGFloat,
        isHidden: Bool,
        isDeleting: Bool = false,
        onSelect: @escaping (DiscoverySummary, URL?) -> Void
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
            guard !isDeleting else { return }
            onSelect(discovery, imageURL)
        } label: {
            ZStack(alignment: .bottom) {
                DiscoveryCardImageView(
                    discoveryId: discovery.id,
                    url: imageURL,
                    width: width,
                    height: height
                )
                .opacity(isDeleting ? 0.5 : 1.0)
                
                DiscoveryCardChrome(discovery: discovery)
                    .opacity(isDeleting ? 0.3 : 1.0)
                
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
        }
        .buttonStyle(.plain)
        .opacity(isHidden ? 0 : 1)
        .disabled(isDeleting)
        .animation(.easeInOut(duration: 0.25), value: isDeleting)
    }

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
                .font(.system(size: 13, weight: .semibold))
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
