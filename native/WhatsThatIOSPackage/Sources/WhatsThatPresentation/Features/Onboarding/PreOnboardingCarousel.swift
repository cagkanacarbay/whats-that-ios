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
        TabView(selection: $index) {
            ForEach(slides.indices, id: \.self) { idx in
                OnboardingSlidePage(
                    imageName: slides[idx].imageName,
                    title: slides[idx].title,
                    message: slides[idx].message,
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
        .safeAreaInset(edge: .bottom) {
            callToAction(bottomInset: bottomInset)
        }
    }

    @ViewBuilder
    private func callToAction(bottomInset: CGFloat) -> some View {
        VStack(spacing: BrandSpacing.small) {
            OnboardingPageIndicators(count: slides.count, currentIndex: index)

            if index == slides.count - 1 {
                BrandPrimaryButton(title: "Get Started", action: onContinue)
            } else {
                HStack(spacing: BrandSpacing.medium) {
                    BrandSecondaryButton(title: "Skip") { onContinue() }
                    BrandPrimaryButton(title: "Next") { withAnimation { index += 1 } }
                }
            }
        }
        // .padding(.top, BrandSpacing.small)
        .padding(.horizontal, BrandSpacing.large)
        .padding(.bottom, min(bottomInset, BrandSpacing.small))
        .background(backgroundColor)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }
}

// MARK: - Helpers
