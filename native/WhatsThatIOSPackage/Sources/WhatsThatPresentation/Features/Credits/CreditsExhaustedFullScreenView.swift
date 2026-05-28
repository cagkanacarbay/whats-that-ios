import SwiftUI
import WhatsThatShared
import WhatsThatDomain

/// Full-screen view shown when user's free credits are exhausted.
/// Shows the user's actual discoveries to remind them of the value they've received.
/// Cannot be dismissed by tapping outside - must use close button or "Maybe later".
struct CreditsExhaustedFullScreenView: View {
    /// The user's recent discoveries to display
    let discoveries: [DiscoverySummary]
    let playbackController: VoiceoverPlaybackController?
    let onGetCredits: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Close button - top left
            HStack {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(palette.textSecondary.opacity(0.12))
                        )
                }
                .padding(.leading, BrandSpacing.medium)
                .padding(.top, BrandSpacing.medium)
                Spacer()
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: BrandSpacing.large)

                    // Headline
                    Text("Look at what you have discovered.")
                        .font(.adaptiveSystem(size: 28, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.large)
                        .padding(.bottom, BrandSpacing.large)

                    // Discovery cards
                    VStack(spacing: BrandSpacing.medium) {
                        if let controller = playbackController {
                            ForEach(discoveries) { discovery in
                                ObservableDiscoveryHighlightCard(
                                    discovery: discovery,
                                    playbackController: controller
                                )
                            }
                        } else {
                            ForEach(discoveries) { discovery in
                                DiscoveryHighlightCard(discovery: discovery)
                            }
                        }
                    }
                    .padding(.horizontal, BrandSpacing.large)
                    .padding(.bottom, BrandSpacing.large)

                    // Pivot line
                    Text("And that's just the beginning.")
                        .font(.adaptiveSystem(size: 15, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .italic()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.large)
                        .padding(.bottom, BrandSpacing.medium)

                    // Transformation line
                    Text("You've discovered how to see the world differently.")
                        .font(.adaptiveSystem(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.large)
                        .padding(.bottom, BrandSpacing.xLarge)
                }
                .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)
            }

            // CTA section - fixed at bottom
            VStack(spacing: BrandSpacing.small) {
                BrandPrimaryButton(title: "Unlock More Stories") {
                    onGetCredits()
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Maybe later")
                        .font(.adaptiveBody().weight(.medium))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.xLarge)
            .padding(.top, BrandSpacing.medium)
            .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)
            .background(
                palette.background
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: -4)
            )
        }
        .background(palette.background.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }
}

// MARK: - Observable Discovery Highlight Card (with audio controls)

/// Wrapper that properly observes VoiceoverPlaybackController for reactive UI updates.
private struct ObservableDiscoveryHighlightCard: View {
    let discovery: DiscoverySummary
    @ObservedObject var playbackController: VoiceoverPlaybackController

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    /// Whether this discovery is currently preparing (generating audio)
    private var isPreparing: Bool {
        if case .preparing(let id) = playbackController.playbackState, id == discovery.id {
            return true
        }
        return false
    }

    /// Whether this discovery is currently playing
    private var isPlaying: Bool {
        if case .playing(let id) = playbackController.playbackState, id == discovery.id {
            return true
        }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.medium) {
            // Thumbnail with play/pause overlay
            ZStack {
                DiscoveryCachedImage(
                    discoveryId: discovery.id,
                    remoteURL: imageURL
                ) { phase in
                    ZStack {
                        // Placeholder background
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BrandColors.Light.tabSelected.opacity(0.1))

                        switch phase {
                        case .success(let image):
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .loading, .empty:
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(BrandColors.Light.tabSelected.opacity(0.5))
                        case .failure:
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(BrandColors.Light.tabSelected.opacity(0.5))
                        }
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Always show play/pause button; spinner when preparing
                if isPreparing {
                    // Generating spinner
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.5))
                            .frame(width: 48, height: 48)

                        Circle()
                            .strokeBorder(BrandColors.logo.opacity(0.3), lineWidth: 2)
                            .frame(width: 48, height: 48)

                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: BrandColors.logo))
                            .scaleEffect(1.0)
                    }
                } else {
                    // Play/pause button
                    Button {
                        playbackController.togglePlayback(for: discovery)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.black.opacity(0.5))
                                .frame(width: 48, height: 48)

                            Circle()
                                .strokeBorder(BrandColors.logo.opacity(0.3), lineWidth: 2)
                                .frame(width: 48, height: 48)

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(BrandColors.logo)
                                .offset(x: isPlaying ? 0 : 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 80, height: 80)

            // Title and first sentence of description
            VStack(alignment: .leading, spacing: 4) {
                Text(discovery.title)
                    .font(.adaptiveSystem(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                Text(firstSentence)
                    .font(.adaptiveSystem(size: 14, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.medium)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.textSecondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.textSecondary.opacity(0.1), lineWidth: 1)
        )
    }

    private var imageURL: URL? {
        guard let path = discovery.imagePath else { return nil }
        return URL(string: path)
    }

    /// Extracts the first sentence from the detail description, skipping any markdown h2 header
    private var firstSentence: String {
        guard let description = discovery.detailDescription, !description.isEmpty else {
            return discovery.highlight
        }

        var contentToSearch = description
        if description.hasPrefix("##") {
            if let newlineIndex = description.firstIndex(of: "\n") {
                let afterHeader = description[description.index(after: newlineIndex)...]
                contentToSearch = String(afterHeader).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard !contentToSearch.isEmpty else {
            return discovery.highlight
        }

        let sentenceEnders: [Character] = [".", "!", "?"]
        for (index, char) in contentToSearch.enumerated() {
            if sentenceEnders.contains(char) {
                let endIndex = contentToSearch.index(contentToSearch.startIndex, offsetBy: index + 1)
                return String(contentToSearch[..<endIndex])
            }
        }

        if contentToSearch.count > 150 {
            let endIndex = contentToSearch.index(contentToSearch.startIndex, offsetBy: 150)
            return String(contentToSearch[..<endIndex]) + "..."
        }
        return contentToSearch
    }
}

// MARK: - Discovery Highlight Card (static, no audio controls)

private struct DiscoveryHighlightCard: View {
    let discovery: DiscoverySummary

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.medium) {
            // Thumbnail
            DiscoveryCachedImage(
                discoveryId: discovery.id,
                remoteURL: imageURL
            ) { phase in
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BrandColors.Light.tabSelected.opacity(0.1))

                    switch phase {
                    case .success(let image):
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .loading, .empty:
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundStyle(BrandColors.Light.tabSelected.opacity(0.5))
                    case .failure:
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundStyle(BrandColors.Light.tabSelected.opacity(0.5))
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Title and first sentence of description
            VStack(alignment: .leading, spacing: 4) {
                Text(discovery.title)
                    .font(.adaptiveSystem(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                Text(firstSentence)
                    .font(.adaptiveSystem(size: 14, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.medium)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.textSecondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.textSecondary.opacity(0.1), lineWidth: 1)
        )
    }

    private var imageURL: URL? {
        guard let path = discovery.imagePath else { return nil }
        return URL(string: path)
    }

    /// Extracts the first sentence from the detail description, skipping any markdown h2 header
    private var firstSentence: String {
        guard let description = discovery.detailDescription, !description.isEmpty else {
            return discovery.highlight
        }

        var contentToSearch = description
        if description.hasPrefix("##") {
            if let newlineIndex = description.firstIndex(of: "\n") {
                let afterHeader = description[description.index(after: newlineIndex)...]
                contentToSearch = String(afterHeader).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard !contentToSearch.isEmpty else {
            return discovery.highlight
        }

        let sentenceEnders: [Character] = [".", "!", "?"]
        for (index, char) in contentToSearch.enumerated() {
            if sentenceEnders.contains(char) {
                let endIndex = contentToSearch.index(contentToSearch.startIndex, offsetBy: index + 1)
                return String(contentToSearch[..<endIndex])
            }
        }

        if contentToSearch.count > 150 {
            let endIndex = contentToSearch.index(contentToSearch.startIndex, offsetBy: 150)
            return String(contentToSearch[..<endIndex]) + "..."
        }
        return contentToSearch
    }
}

// MARK: - Preview

#Preview {
    CreditsExhaustedFullScreenView(
        discoveries: [],
        playbackController: nil,
        onGetCredits: {},
        onDismiss: {}
    )
}
