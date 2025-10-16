import Foundation
import SwiftUI
import WhatsThatDomain
import WhatsThatShared
#if canImport(MarkdownUI)
import MarkdownUI
#endif
#if canImport(UIKit)
import UIKit
#endif

struct DiscoveryCreationFlowView: View {
    enum LayoutConstants {
        static let previewHeight: CGFloat = 320
        static let controlHeight: CGFloat = 56
        static let cornerRadius: CGFloat = 20
    }

    @ObservedObject var viewModel: DiscoveryCreationFlowViewModel
    let placeholderEmoji: String
    let ctaTitle: String
    let retryTitle: String

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            content
        }
        .padding(.horizontal, BrandSpacing.large)
        .padding(.vertical, BrandSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert(
            item: Binding(
                get: { viewModel.error.map(IdentifiedError.init) },
                set: { _ in viewModel.clearError() }
            )
        ) { identifiedError in
            Alert(
                title: Text("Oops"),
                message: Text(identifiedError.error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.flowState {
        case .idle, .cancelled:
            IdleStateView(
                emoji: placeholderEmoji,
                title: ctaTitle,
                action: { viewModel.startFlow() }
            )
        case .requestingPermissions, .capturingInitial, .capturingRetake, .selectingInitial, .selectingRetake:
            ProgressStateView()
        case let .error(message):
            ErrorStateView(
                emoji: "⚠️",
                title: "Something went wrong",
                message: message.isEmpty ? "Please try again." : message,
                actionTitle: retryTitle,
                action: { viewModel.retake() }
            )
        case let .confirming(state):
            ConfirmationStateView(
                state: state,
                creditBalance: viewModel.creditBalance,
                onRetake: { viewModel.retake() },
                onContinue: { viewModel.beginAnalysis() },
                onCancel: { viewModel.cancelFlow() }
            )
        case let .analyzing(state):
            AnalysisStateView(state: state)
        }
    }
}

private struct IdleStateView: View {
    let emoji: String
    let title: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            Text(emoji)
                .font(.system(size: 72))
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
            Text("We’ll guide you from capture to narration in seconds.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            BrandPrimaryButton(title: "Get started", action: action)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProgressStateView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(palette.primaryAction)
            Text("Preparing…")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorStateView: View {
    let emoji: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            Text(emoji)
                .font(.system(size: 64))
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(message)
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            BrandPrimaryButton(title: actionTitle, action: action)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ConfirmationStateView: View {
    let state: DiscoveryConfirmationState
    let creditBalance: Int?
    let onRetake: () -> Void
    let onContinue: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    private var previewImage: Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: state.displayImageData) else {
            return nil
        }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }

    private var creditLabel: String {
        guard let balance = creditBalance else {
            return "Checking credits…"
        }
        return "\(balance) credit\(balance == 1 ? "" : "s") available"
    }

    private var lowCreditWarning: String? {
        guard let balance = creditBalance else { return nil }
        if balance == 0 {
            return "You're out of credits. Buy more to continue."
        }
        if balance <= 3 {
            return "Only \(balance) credit\(balance == 1 ? "" : "s") remaining."
        }
        return nil
    }

    private var locationStatus: (icon: String, description: String, isResolved: Bool) {
        if let description = state.locationDescription {
            return ("mappin.and.ellipse", description, true)
        }
        if state.isLocationPermissionGranted {
            return ("location.fill", "Locating you…", false)
        }
        return ("location.slash", "Location unavailable", false)
    }

    private var isContinueDisabled: Bool {
        if let balance = creditBalance {
            return balance <= 0
        }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.large) {
                previewSection
                creditAndLocationSection
                personalizationSection
                actionButtons
                Button("Cancel", role: .cancel, action: onCancel)
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, BrandSpacing.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var previewSection: some View {
        if let image = previewImage {
            image
                .resizable()
                .scaledToFill()
                .frame(height: DiscoveryCreationFlowView.LayoutConstants.previewHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: DiscoveryCreationFlowView.LayoutConstants.cornerRadius,
                        style: .continuous
                    )
                )
        } else {
            RoundedRectangle(
                cornerRadius: DiscoveryCreationFlowView.LayoutConstants.cornerRadius,
                style: .continuous
            )
            .fill(palette.border.opacity(0.12))
            .frame(height: DiscoveryCreationFlowView.LayoutConstants.previewHeight)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Preview unavailable")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var creditAndLocationSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.small) {
            HStack(spacing: BrandSpacing.small) {
                Label(creditLabel, systemImage: "bolt.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.primaryAction)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(palette.primaryAction.opacity(0.1))
                    .clipShape(Capsule())

                if let lowCreditWarning {
                    Text(lowCreditWarning)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.red)
                }
            }

            let status = locationStatus
            Label(status.description, systemImage: status.icon)
                .font(.system(size: 15))
                .foregroundStyle(status.isResolved ? palette.textSecondary : palette.textSecondary.opacity(0.8))
        }
    }

    @ViewBuilder
    private var personalizationSection: some View {
        if state.customContext != nil {
            Label("Personalising to your recent discoveries", systemImage: "sparkles")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textSecondary.opacity(0.9))
        }
    }

    private var actionButtons: some View {
        HStack(spacing: BrandSpacing.small) {
            Button(action: onRetake) {
                Text("Retake")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: DiscoveryCreationFlowView.LayoutConstants.controlHeight)
            }
            .buttonStyle(.plain)
            .background(palette.secondaryAction)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.border.opacity(0.4), lineWidth: 1)
            }

            Button(action: onContinue) {
                Text(isContinueDisabled ? "Add credits" : "Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: DiscoveryCreationFlowView.LayoutConstants.controlHeight)
                    .foregroundStyle(Color.white)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(palette.primaryAction)
                    )
                    .opacity(isContinueDisabled ? 0.6 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isContinueDisabled)
        }
    }
}

private struct AnalysisStateView: View {
    let state: DiscoveryAnalysisState

    @Environment(\.colorScheme) private var colorScheme
    @State private var fallbackMessage = AnalysisStateView.fallbackMessages.randomElement() ?? "Listening to the world…"

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    private var statusText: String {
        if let message = state.statusMessage, !message.isEmpty {
            return message
        }
        return fallbackMessage
    }

    private var titleText: String {
        state.isStreaming ? "Crafting your discovery…" : "Analysis complete"
    }

    private var markdownBody: String {
        state.displayMarkdown
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.large) {
                statusCard
                metadataCard
                narrativeSection
                if !state.isStreaming {
                    Text("Your discovery is saved. We’ll open it automatically.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, BrandSpacing.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: state.isStreaming) { isStreaming in
            if isStreaming {
                fallbackMessage = AnalysisStateView.fallbackMessages.randomElement() ?? fallbackMessage
            }
        }
    }

    private var statusCard: some View {
        HStack(alignment: .center, spacing: BrandSpacing.medium) {
            if state.isStreaming {
                PulsingDotsView(primaryColor: palette.primaryAction)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(palette.primaryAction)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(titleText)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(statusText)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.surface.opacity(colorScheme == .dark ? 0.85 : 1))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.border.opacity(0.35), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var metadataCard: some View {
        if state.metadataTitle != nil || state.metadataShortDescription != nil {
            VStack(alignment: .leading, spacing: BrandSpacing.small) {
                if let title = state.metadataTitle {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                if let shortDescription = state.metadataShortDescription {
                    Text(shortDescription)
                        .font(.system(size: 15))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.surface.opacity(colorScheme == .dark ? 0.75 : 0.95))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.border.opacity(0.25), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var narrativeSection: some View {
        if markdownBody.isEmpty {
            Text("We’re composing your story…")
                .font(.system(size: 15))
                .foregroundStyle(palette.textSecondary)
                .italic()
        } else {
            #if canImport(MarkdownUI)
            Markdown(markdownBody)
                .markdownTheme(BrandMarkdownThemeFactory.discoveryDetailTheme(for: palette))
                .animation(.easeInOut(duration: 0.18), value: markdownBody)
            #else
            Text(markdownBody)
                .font(.system(size: 16))
                .foregroundStyle(palette.textSecondary)
            #endif
        }
    }

    private static let fallbackMessages: [String] = [
        "Identifying landmarks…",
        "Admiring nature…",
        "Uncovering hidden history…",
        "Listening for local stories…",
        "Tracking wildlife sightings…",
        "Consulting the travel guides…",
        "Sketching the surroundings…",
        "Mapping nearby highlights…"
    ]
}

private struct PulsingDotsView: View {
    let primaryColor: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSince1970
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(primaryColor.opacity(colorScheme == .dark ? 0.9 : 1))
                        .frame(width: 10, height: 10)
                        .scaleEffect(scale(for: time, index: index))
                        .opacity(opacity(for: time, index: index))
                }
            }
        }
    }

    private func scale(for time: TimeInterval, index: Int) -> CGFloat {
        let progress = (time + Double(index) * 0.22).remainder(dividingBy: 1.0)
        return 0.75 + 0.25 * CGFloat(sin(progress * 2 * .pi))
    }

    private func opacity(for time: TimeInterval, index: Int) -> Double {
        let progress = (time + Double(index) * 0.22).remainder(dividingBy: 1.0)
        return 0.5 + 0.5 * sin(progress * 2 * .pi + .pi / 2)
    }
}

private struct IdentifiedError: Identifiable {
    let id = UUID()
    let error: DiscoveryCreationFlowViewModel.FlowError
}
