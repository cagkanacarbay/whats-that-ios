import SwiftUI
import WhatsThatShared
import UIKit

struct PreOnboardingCarousel: View {
    struct Slide: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let imageName: String
    }

    private let slides: [Slide] = [
        Slide(
            title: "See the world with new eyes.",
            message: "Point your camera and let the world share its stories.",
            imageName: "OnboardingIntro"
        ),
        Slide(
            title: "Stories tailored to you.",
            message: "Answers adapt to your interests and get smarter with every photo.",
            imageName: "OnboardingStories"
        )
    ]

    @State private var index: Int = 0
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let topInset: CGFloat = 0
            let bottomInset = proxy.safeAreaInsets.bottom
            content(width: width, topInset: topInset, bottomInset: bottomInset)
                .frame(width: width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func content(width: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        
        VStack(spacing: BrandSpacing.large) {

            TabView(selection: $index) {
                ForEach(slides.indices, id: \.self) { idx in
                    SlidePage(
                        slide: slides[idx],
                        titleColor: titleColor,
                        bodyColor: bodyColor,
                        containerWidth: width,
                        topInset: topInset
                    )
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Respect the safe area so the image aligns with the notch.
            // Do not extend under the status bar/notch for pre-onboarding visuals.
            .frame(width: width)
            .ignoresSafeArea(edges: .top)

            // Page indicator + actions tightly grouped
            Spacer(minLength: BrandSpacing.small)
            VStack(spacing: BrandSpacing.small) {
                PageIndicators(count: slides.count, currentIndex: index)

                if index == slides.count - 1 {
                    BrandPrimaryButton(title: "Get Started", action: onContinue)
                        .padding(.horizontal, BrandSpacing.large)
                } else {
                    HStack(spacing: BrandSpacing.medium) {
                        BrandSecondaryButton(title: "Skip") { onContinue() }
                        BrandPrimaryButton(title: "Next") { withAnimation { index += 1 } }
                    }
                    .padding(.horizontal, BrandSpacing.large)
                }
            }
            .padding(.bottom, bottomInset + BrandSpacing.small)
        }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }
}

// MARK: - Slide Page Subview (helps compiler type-check and keeps layout simple)

private struct SlidePage: View {
    let slide: PreOnboardingCarousel.Slide
    let titleColor: Color
    let bodyColor: Color
    let containerWidth: CGFloat
    let topInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {

            let imageHeight = containerWidth * 1.5 // 2:3 (w:h) -> h = w * 3/2
            let epsilon: CGFloat = 1.0 / max(UIScreen.main.scale, 1)
            // Expand the container slightly (topInset + epsilon) so the overlay isn't clipped
            // and offset upwards by the same amount to eliminate any top sliver at all scales.
            Color.clear
                .frame(width: containerWidth, height: imageHeight + topInset + epsilon)
                .overlay(alignment: .top) {
                    Image(slide.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: containerWidth, height: imageHeight + topInset + epsilon, alignment: .top)
                        .offset(y: -(topInset + epsilon))
                        .ignoresSafeArea(edges: .top)
                        .accessibilityHidden(false)
                }
                
            VStack(spacing: BrandSpacing.small) {
                Text(slide.title)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, BrandSpacing.large)
                Text(slide.message)
                    .font(.system(size: 17, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(bodyColor)
                    .padding(.horizontal, BrandSpacing.large)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // .padding(.top, BrandSpacing.small)
        }
        .frame(width: containerWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct PageIndicators: View {
    let count: Int
    let currentIndex: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { idx in
                Capsule()
                    .fill(idx == currentIndex ? activeColor : inactiveColor)
                    .frame(width: idx == currentIndex ? 24 : 8, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
        }
    }

    private var activeColor: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }

    private var inactiveColor: Color {
        colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
    }
}

// MARK: - Helpers

// Shifts content up by the safe-area top amount using APIs that integrate with layout rounding.
private struct TopSafeAreaShift: ViewModifier {
    let topInset: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.safeAreaPadding(.top, -topInset)
        } else {
            content.padding(.top, -topInset)
        }
    }
}
