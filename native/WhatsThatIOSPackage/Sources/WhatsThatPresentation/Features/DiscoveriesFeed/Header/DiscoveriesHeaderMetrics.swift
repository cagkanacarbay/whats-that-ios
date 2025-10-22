import CoreGraphics
import WhatsThatShared

struct DiscoveriesHeaderMetrics {
    let headerSpacerHeight: CGFloat
    let headerTopPadding: CGFloat
    let headerStackSpacing: CGFloat
    let headerDividerBottomPadding: CGFloat
    let gridTopPadding: CGFloat
    let collapseDistance: CGFloat

    init(headerHeight: CGFloat, safeAreaTopInset: CGFloat) {
        let headerContentHeight = max(headerHeight - safeAreaTopInset, 0)
        let headerDesiredSpacing = BrandSpacing.small
        headerSpacerHeight = max(headerContentHeight - headerDesiredSpacing, 0)
        headerTopPadding = BrandSpacing.small * 0.5
        headerStackSpacing = headerTopPadding
        headerDividerBottomPadding = BrandSpacing.small * 0.25

        let approximateTitleToNotch = safeAreaTopInset + headerTopPadding
        let desiredGap = approximateTitleToNotch * 0.35
        gridTopPadding = max(desiredGap, BrandSpacing.small * 0.75)

        collapseDistance = max(headerContentHeight, 1)
    }

    func headerOpacity(for scrollOffset: CGFloat) -> Double {
        let offset = max(0, -scrollOffset)
        let progress = min(offset / collapseDistance, 1)
        return 1 - Double(progress)
    }
}
