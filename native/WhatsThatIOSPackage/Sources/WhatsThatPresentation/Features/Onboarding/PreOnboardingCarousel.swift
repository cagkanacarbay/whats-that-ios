import SwiftUI
import WhatsThatShared
import WhatsThatDomain
import UIKit

/// Pre-onboarding view that showcases sample discoveries before sign-up.
/// Displays an interactive discovery gallery where users can:
/// - Browse sample discoveries in a grid
/// - Tap to see full discovery details with audio playback
/// - Proceed to authentication via the "Create Your Own" button
/// - Sign in via the "Account · Sign in" link
struct PreOnboardingCarousel: View {
    let discoveryService: SampleDiscoveryService?
    let makeVoiceoverController: (() -> VoiceoverPlaybackController)?
    let onContinue: () -> Void
    let onSignIn: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    /// Legacy initializer for backward compatibility (shows static slides if no discovery service)
    init(onContinue: @escaping () -> Void) {
        self.discoveryService = nil
        self.makeVoiceoverController = nil
        self.onContinue = onContinue
        self.onSignIn = nil
    }

    /// Full initializer with discovery service for interactive gallery
    init(
        discoveryService: SampleDiscoveryService,
        makeVoiceoverController: @escaping () -> VoiceoverPlaybackController,
        onContinue: @escaping () -> Void,
        onSignIn: @escaping () -> Void
    ) {
        self.discoveryService = discoveryService
        self.makeVoiceoverController = makeVoiceoverController
        self.onContinue = onContinue
        self.onSignIn = onSignIn
    }

    var body: some View {
        if let service = discoveryService, let factory = makeVoiceoverController {
            // New interactive discovery gallery with bottom sheet
            // The .id() ensures stable view identity to prevent StateObject recreation
            PreOnboardingDiscoveriesContainer(
                discoveryService: service,
                makeVoiceoverController: factory,
                onContinue: onContinue,
                onSignIn: onSignIn ?? onContinue
            )
            .id("preOnboardingContainer")
        } else {
            // Fallback to legacy static carousel
            LegacyPreOnboardingCarousel(onContinue: onContinue)
        }
    }
}

// MARK: - Legacy Carousel (Fallback)

/// The original static carousel implementation, kept for backward compatibility.
private struct LegacyPreOnboardingCarousel: View {
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
            let screenHeight = proxy.size.height
            let topInset: CGFloat = 0
            let bottomInset = proxy.safeAreaInsets.bottom
            content(width: width, topInset: topInset, bottomInset: bottomInset, containerHeight: screenHeight)
                .frame(width: width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func content(width: CGFloat, topInset: CGFloat, bottomInset: CGFloat, containerHeight: CGFloat) -> some View {
        TabView(selection: $index) {
            ForEach(slides.indices, id: \.self) { idx in
                OnboardingSlidePage(
                    imageName: slides[idx].imageName,
                    title: slides[idx].title,
                    message: slides[idx].message,
                    titleColor: titleColor,
                    bodyColor: bodyColor,
                    containerWidth: width,
                    topInset: topInset,
                    containerHeight: containerHeight
                )
                .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
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
