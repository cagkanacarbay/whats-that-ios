import SwiftUI
import WhatsThatShared

struct OnboardingVoicePickerSlide: View {
    let title: String
    let message: String
    let titleColor: Color
    let bodyColor: Color
    let containerWidth: CGFloat
    let topInset: CGFloat
    @ObservedObject var viewModel: VoicePickerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Use a spacer to push content down a bit, matching the top area of other slides roughly
            // or maybe a smaller illustration if we had one. For now, just spacing.
            Spacer()
                .frame(height: topInset + 60)
            
            VStack(spacing: BrandSpacing.small) {
                Text(title)
                    .font(.adaptiveSystem(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, BrandSpacing.large)
                
                Text(message)
                    .font(.adaptiveSystem(size: 17, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(bodyColor)
                    .padding(.horizontal, BrandSpacing.large)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, BrandSpacing.medium)
            .padding(.bottom, BrandSpacing.large)
            
            VoicePickerView(
                viewModel: viewModel,
                showCreditNote: true
            )
            
            Spacer()
        }
        .frame(width: containerWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }
}
