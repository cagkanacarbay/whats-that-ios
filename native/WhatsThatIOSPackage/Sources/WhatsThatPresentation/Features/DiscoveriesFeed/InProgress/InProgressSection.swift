import SwiftUI
import WhatsThatShared

/// Horizontal strip of compact thumbnails for in-progress discovery sessions.
/// Sits above the discoveries grid, fitting 5-6 items per row.
struct InProgressSection: View {
    let items: [InProgressItem]
    let onTap: (InProgressItem) -> Void
    let onDismissFailure: (InProgressItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In Progress")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)

            GeometryReader { proxy in
                let spacing: CGFloat = 4
                let columns: CGFloat = 6
                let totalSpacing = spacing * (columns - 1)
                let cellWidth = (proxy.size.width - totalSpacing) / columns

                HStack(spacing: spacing) {
                    ForEach(items.prefix(6)) { item in
                        InProgressDiscoveryRow(
                            item: item,
                            size: cellWidth,
                            onTap: { onTap(item) },
                            onDismissFailure: { onDismissFailure(item) }
                        )
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
            }
            .frame(height: thumbnailHeight)
        }
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.3), value: items.map(\.id))
    }

    /// Height = cell width / 6 of available space * 1.2 aspect ratio.
    /// Approximate: screen width ~ 390pt → cell ~62pt → height ~74pt.
    private var thumbnailHeight: CGFloat {
        let screenWidth = UIScreen.main.bounds.width - 18 // padding estimate
        let cellWidth = (screenWidth - 4 * 5) / 6
        return cellWidth * 1.2
    }
}
