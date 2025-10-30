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
        default:
            content
                .padding(.horizontal, BrandSpacing.large)
                .padding(.top, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.xLarge)
        }
    }
}
