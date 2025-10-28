import SwiftUI
import WhatsThatShared
import WhatsThatDomain

struct RootContentPaddingModifier: ViewModifier {
    let flowState: AppFlowState

    func body(content: Content) -> some View {
        if case .main = flowState {
            content
        } else {
            content
                .padding(.horizontal, BrandSpacing.large)
                .padding(.top, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.xLarge)
        }
    }
}
