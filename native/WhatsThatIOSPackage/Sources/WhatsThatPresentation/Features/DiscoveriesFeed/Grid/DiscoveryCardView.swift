import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct DiscoveryCardView: View {
    let discovery: DiscoverySummary
    let width: CGFloat
    let height: CGFloat
    let isHidden: Bool
    let onSelect: (DiscoverySummary, URL?) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let cardCornerRadius: CGFloat = BrandCornerRadius.large

    var body: some View {
        Button {
            onSelect(discovery, imageURL)
        } label: {
            ZStack(alignment: .bottom) {
                DiscoveryCardImageView(
                    discoveryId: discovery.id,
                    url: imageURL,
                    width: width,
                    height: height
                )
                DiscoveryCardChrome(discovery: discovery)
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
