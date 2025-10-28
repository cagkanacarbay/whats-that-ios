import SwiftUI
import WhatsThatShared

struct PreOnboardingCarousel: View {
    struct Slide: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let imageName: String
    }

    private let slides: [Slide] = [
        Slide(
            title: "We give the world a voice.",
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
        VStack(spacing: BrandSpacing.large) {
            Spacer()

            TabView(selection: $index) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { offset, slide in
                    VStack(spacing: BrandSpacing.large) {
                        Image(slide.imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .accessibilityHidden(false)

                        VStack(spacing: BrandSpacing.small) {
                            Text(slide.title)
                                .font(.system(size: 28, weight: .bold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(titleColor)
                            Text(slide.message)
                                .font(.system(size: 17, weight: .medium))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(bodyColor)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 420)

            PageIndicators(count: slides.count, currentIndex: index)

            if index == slides.count - 1 {
                BrandPrimaryButton(title: "Get Started", action: onContinue)
            } else {
                HStack(spacing: BrandSpacing.medium) {
                    BrandSecondaryButton(title: "Skip") {
                        onContinue()
                    }
                    BrandPrimaryButton(title: "Next") {
                        withAnimation { index += 1 }
                    }
                }
            }
            Spacer()
        }
        .padding(.top, BrandSpacing.large)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
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

