import SwiftUI
import UIKit
import WhatsThatShared
import WhatsThatDomain

/// Post-onboarding view shown after authentication.
/// Presents two equally-weighted discovery paths: camera for on-location exploration
/// and gallery for exploring photos the user already has.
struct PostOnboardingCarousel: View {
    let onComplete: () -> Void
    let onLaunchCamera: () -> Void
    let onLaunchUpload: () -> Void

    /// If true, shows "Welcome back" instead of "Now it's your turn" for returning users
    /// who saw this screen before but haven't created their first discovery yet.
    let isReturningUser: Bool

    // Legacy parameters kept for backward compatibility but not used in simplified flow
    private let loadVoiceoverPreferences: () async -> VoiceoverPreferences
    private let saveVoiceoverPreferences: (VoiceoverPreferences) async -> Void
    private let fetchVoiceOptions: () async -> [VoiceModelOption]
    private let fetchVoiceSampleURL: (String) async -> URL?
    private let loadIPoPPreferences: () async -> IPoPPreferences?
    private let saveIPoPPreferences: (IPoPPreferences) async -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        onComplete: @escaping () -> Void,
        onLaunchCamera: @escaping () -> Void,
        onLaunchUpload: @escaping () -> Void,
        isReturningUser: Bool = false,
        loadVoiceoverPreferences: @escaping () async -> VoiceoverPreferences,
        saveVoiceoverPreferences: @escaping (VoiceoverPreferences) async -> Void,
        fetchVoiceOptions: @escaping () async -> [VoiceModelOption],
        fetchVoiceSampleURL: @escaping (String) async -> URL?,
        loadIPoPPreferences: @escaping () async -> IPoPPreferences?,
        saveIPoPPreferences: @escaping (IPoPPreferences) async -> Void
    ) {
        self.onComplete = onComplete
        self.onLaunchCamera = onLaunchCamera
        self.onLaunchUpload = onLaunchUpload
        self.isReturningUser = isReturningUser
        self.loadVoiceoverPreferences = loadVoiceoverPreferences
        self.saveVoiceoverPreferences = saveVoiceoverPreferences
        self.fetchVoiceOptions = fetchVoiceOptions
        self.fetchVoiceSampleURL = fetchVoiceSampleURL
        self.loadIPoPPreferences = loadIPoPPreferences
        self.saveIPoPPreferences = saveIPoPPreferences
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let screenHeight = proxy.size.height
            let bottomInset = proxy.safeAreaInsets.bottom

            welcomeContent(width: width, containerHeight: screenHeight, bottomInset: bottomInset)
                .frame(width: width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func welcomeContent(width: CGFloat, containerHeight: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: containerHeight * 0.12)

            // Header
            Text(isReturningUser ? "Welcome back." : "Now it's your turn.")
                .font(.adaptiveSystem(size: 34, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(titleColor)
                .padding(.horizontal, BrandSpacing.large)

            Spacer()
                .frame(height: BrandSpacing.xLarge)

            // Two option cards
            VStack(spacing: BrandSpacing.medium) {
                // Camera option
                DiscoveryOptionCard(
                    icon: "camera.fill",
                    title: "Somewhere interesting?",
                    description: "Point your camera. Find the stories hiding just beneath the surface.",
                    buttonTitle: "Open Camera",
                    isPrimary: true,
                    action: onLaunchCamera
                )

                // Divider with "or"
                HStack(spacing: BrandSpacing.medium) {
                    Rectangle()
                        .fill(dividerColor)
                        .frame(height: 1)
                    Text("or")
                        .font(.adaptiveSystem(size: 14, weight: .medium))
                        .foregroundStyle(mutedTextColor)
                    Rectangle()
                        .fill(dividerColor)
                        .frame(height: 1)
                }
                .padding(.horizontal, BrandSpacing.medium)

                // Gallery option
                DiscoveryOptionCard(
                    icon: "photo.on.rectangle",
                    title: "Not out exploring right now?",
                    description: "Your photos are full of places you've been and stories you never heard.",
                    buttonTitle: "Choose a Photo",
                    isPrimary: false,
                    action: onLaunchUpload
                )
            }
            .padding(.horizontal, BrandSpacing.large)
            .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)

            Spacer()
        }
        .frame(width: width)
        .background(backgroundColor)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var mutedTextColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText.opacity(0.6) : BrandColors.Light.bodyText.opacity(0.6)
    }

    private var dividerColor: Color {
        colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }
}

// MARK: - Discovery Option Card

private struct DiscoveryOptionCard: View {
    let icon: String
    let title: String
    let description: String
    let buttonTitle: String
    let isPrimary: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            // Icon and title row
            HStack(spacing: BrandSpacing.medium) {
                // Icon with branded styling (matches Credits view)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BrandColors.Light.tabSelected.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BrandColors.Light.tabSelected.opacity(0.3), lineWidth: 1.5)
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(BrandColors.Light.tabSelected)
                }

                Text(title)
                    .font(.adaptiveSystem(size: 18, weight: .semibold))
                    .foregroundStyle(titleColor)
            }

            // Description
            Text(description)
                .font(.adaptiveSystem(size: 15, weight: .regular))
                .foregroundStyle(bodyColor)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // Action button
            Button(action: action) {
                Text(buttonTitle)
                    .font(.adaptiveSystem(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(buttonForeground)
            .background(buttonBackground)
            .cornerRadius(BrandCornerRadius.medium)
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: BrandCornerRadius.medium)
                    .stroke(buttonBorder, lineWidth: 1)
            }
        }
        .padding(BrandSpacing.medium)
        .background(cardBackground)
        .cornerRadius(BrandCornerRadius.large)
        .overlay {
            RoundedRectangle(cornerRadius: BrandCornerRadius.large)
                .stroke(cardBorder, lineWidth: 1)
        }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? BrandColors.Dark.secondaryAction.opacity(0.5)
            : BrandColors.Light.secondaryAction.opacity(0.5)
    }

    private var cardBorder: Color {
        colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
    }

    private var buttonBackground: Color {
        if isPrimary {
            return colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
        } else {
            return colorScheme == .dark ? BrandColors.Dark.secondaryAction : BrandColors.Light.secondaryAction
        }
    }

    private var buttonForeground: Color {
        if isPrimary {
            return .white
        } else {
            return colorScheme == .dark ? Color.white : BrandColors.Light.accentText
        }
    }

    private var buttonBorder: Color {
        if isPrimary {
            return colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
        } else {
            return colorScheme == .dark ? BrandColors.Dark.border : BrandColors.Light.border
        }
    }
}
