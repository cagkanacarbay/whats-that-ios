import SwiftUI
import WhatsThatShared
import UIKit

struct OnboardingSlidePage: View {
    let imageName: String
    let title: String
    let message: String
    let titleColor: Color
    let bodyColor: Color
    let containerWidth: CGFloat
    let topInset: CGFloat
    var containerHeight: CGFloat? = nil

    var body: some View {
        VStack(spacing: 0) {
            if UIDevice.isIPad {
                // iPad Layout: Constrained image, fit aspect ratio, centered
                // Add extra top spacing on top of the safe area inset
                Color.clear
                    .frame(height: topInset + BrandSpacing.large) 
                
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, BrandSpacing.medium)
                    .accessibilityHidden(true)
            } else {
                // iPhone Layout: Existing full-width logic
                // Detect compact screens (iPad compatibility mode, small screen devices)
                // Only apply height constraint on compact screens to preserve full-width images on normal devices
                let isCompactScreen = (containerHeight ?? .infinity) < 700
                
                // On compact screens: constrain image height and use scaledToFill with clipping
                // On normal screens: use original behavior with idealImageHeight
                let idealImageHeight = containerWidth * 1.5
                let reservedForContent: CGFloat = 220
                let maxImageHeight = max((containerHeight ?? .infinity) - reservedForContent, 200)
                let imageHeight = isCompactScreen ? min(idealImageHeight, maxImageHeight) : idealImageHeight
                
                let epsilon: CGFloat = 1.0 / max(UIScreen.main.scale, 1)
                Color.clear
                    .frame(width: containerWidth, height: imageHeight + topInset + epsilon)
                    .overlay(alignment: .top) {
                        Image(imageName)
                            .resizable()
                            // Use scaledToFill on compact screens to maintain full width while cropping height
                            // Use scaledToFit on normal screens for original behavior
                            .aspectRatio(contentMode: isCompactScreen ? .fill : .fit)
                            .frame(width: containerWidth, height: imageHeight + topInset + epsilon, alignment: .top)
                            .clipped()
                            .offset(y: -(topInset + epsilon))
                            .accessibilityHidden(false)
                    }
            }

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
            .layoutPriority(1) // Ensure text gets space first before image expands
            // Cap Dynamic Type scaling to prevent text overflow on accessibility font sizes
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.top, BrandSpacing.medium)
            .padding(.bottom, BrandSpacing.medium)
        }
        .frame(width: containerWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }
}
