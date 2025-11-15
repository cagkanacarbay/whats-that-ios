import SwiftUI
import WhatsThatShared
import WhatsThatDomain

struct RootContentPaddingModifier: ViewModifier {
    let flowState: AppFlowState

    func body(content: Content) -> some View {
        switch flowState {
        case .main:
            content
        case .authentication:
            // Auth screens manage their own internal padding to avoid edge clipping.
            content
        case .preOnboarding:
            // Pre-onboarding should be edge-to-edge for the hero image; keep only a small bottom breathing room.
            content
                .padding(.bottom, BrandSpacing.small)
        case .postOnboarding:
            content
                .padding(.horizontal, BrandSpacing.large)
                .padding(.top, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.xLarge)
        case .loading:
            content
        }
    }
}
