import SwiftUI
import WhatsThatShared
import WhatsThatDomain

/// Shows a "sneak peek" of the next item in queue above the hero player
struct SneakPeekView: View {
    let discovery: DiscoverySummary?
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        if let discovery {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UP NEXT")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(BrandColors.logo)
                    
                    Text(discovery.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Use DiscoveryCachedImage for proper caching
                if let imagePath = discovery.imagePath,
                   let imageURL = URL(string: imagePath) {
                    DiscoveryCachedImage(
                        discoveryId: discovery.id,
                        remoteURL: imageURL
                    ) { phase in
                        switch phase {
                        case .success(let platformImage):
                            Image(uiImage: platformImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .cornerRadius(6)
                        case .loading, .empty, .failure:
                            placeholderImage
                        }
                    }
                } else {
                    placeholderImage
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(BrandTheme.palette(for: colorScheme).surface.opacity(0.5))
            .cornerRadius(12)
            .padding(.horizontal, 16)
        } else {
            EmptyView()
        }
    }
    
    private var placeholderImage: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 40, height: 40)
            .cornerRadius(6)
    }
}
