import SwiftUI
import WhatsThatShared

struct OnboardingSlidePage: View {
    let imageName: String
    let title: String
    let message: String
    let titleColor: Color
    let bodyColor: Color
    let containerWidth: CGFloat
    let topInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            let imageHeight = containerWidth * 1.5
            let epsilon: CGFloat = 1.0 / max(UIScreen.main.scale, 1)
            Color.clear
                .frame(width: containerWidth, height: imageHeight + topInset + epsilon)
                .overlay(alignment: .top) {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: containerWidth, height: imageHeight + topInset + epsilon, alignment: .top)
                        .offset(y: -(topInset + epsilon))
                        .accessibilityHidden(false)
                }

            VStack(spacing: BrandSpacing.small) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, BrandSpacing.large)
                Text(message)
                    .font(.system(size: 17, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(bodyColor)
                    .padding(.horizontal, BrandSpacing.large)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, BrandSpacing.medium)
            .padding(.bottom, BrandSpacing.medium)
        }
        .frame(width: containerWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }
}
