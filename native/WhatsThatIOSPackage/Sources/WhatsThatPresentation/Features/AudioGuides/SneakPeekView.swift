import SwiftUI
import WhatsThatShared

struct SneakPeekView: View {
    let guide: AudioGuide?
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        if let guide = guide {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UP NEXT")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(BrandColors.logo)
                    
                    Text(guide.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(BrandTheme.palette(for: colorScheme).textPrimary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(guide.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
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
}
