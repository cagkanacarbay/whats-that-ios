import CoreGraphics
import WhatsThatShared

struct DiscoveriesHeaderMetrics {
    let headerSpacerHeight: CGFloat
    let headerTopPadding: CGFloat
    let headerStackSpacing: CGFloat
    let gridTopPadding: CGFloat
    let collapseDistance: CGFloat

    init(headerHeight: CGFloat, safeAreaTopInset: CGFloat) {
        let headerContentHeight = max(headerHeight - safeAreaTopInset, 0)
        // Slightly tighter header spacing overall
        headerSpacerHeight = max(headerContentHeight - BrandSpacing.small, 0)
        headerTopPadding = BrandSpacing.small * 0.5
        headerStackSpacing = BrandSpacing.small * 0.25

        // Bring the grid closer to the header for a tighter feel
        // Halved from previous value (~16pt → ~8pt)
        gridTopPadding = BrandSpacing.small

        collapseDistance = max(headerContentHeight, 1)
    }

    func headerOpacity(for scrollOffset: CGFloat) -> Double {
        let offset = max(0, -scrollOffset)
        let progress = min(offset / collapseDistance, 1)
        return 1 - Double(progress)
    }
}
