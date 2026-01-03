import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared

struct DiscoveryCreationFlowView: View {
    private enum ActiveAlert: Identifiable {
        case flowError(IdentifiedError)
        case locationPermissions
        case outOfCredits
        case pollingFailed
        case freeCreditsExhaustedAtAudioGeneration
        case freeCreditsExhaustedAtConfirm

        var id: String {
            switch self {
            case let .flowError(identifiedError):
                return identifiedError.id.uuidString
            case .locationPermissions:
                return "locationPermissions"
            case .outOfCredits:
                return "outOfCredits"
            case .pollingFailed:
                return "pollingFailed"
            case .freeCreditsExhaustedAtAudioGeneration:
                return "freeCreditsExhaustedAtAudioGeneration"
            case .freeCreditsExhaustedAtConfirm:
                return "freeCreditsExhaustedAtConfirm"
            }
        }
    }

    private enum ActiveSheet: Identifiable {
        case credits
        case missingUploadLocation

        var id: String {
            switch self {
            case .credits:
                return "credits"
            case .missingUploadLocation:
                return "missingUploadLocation"
            }
        }
    }

    @ObservedObject private var viewModel: DiscoveryCreationFlowViewModel
    let placeholderEmoji: String
    let ctaTitle: String
    let retryTitle: String
    private let makeCreditsViewModel: (() -> CreditsViewModel)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var presentedCreditsViewModel: CreditsViewModel?
    @State private var creditsSheetDetent: PresentationDetent = .fraction(0.8)
    @State private var activeAlert: ActiveAlert?
    @State private var activeSheet: ActiveSheet?
    @Environment(\.scenePhase) private var scenePhase

    init(
        viewModel: DiscoveryCreationFlowViewModel,
        placeholderEmoji: String,
        ctaTitle: String,
        retryTitle: String,
        makeCreditsViewModel: (() -> CreditsViewModel)? = nil
    ) {
        _viewModel = ObservedObject(initialValue: viewModel)
        self.placeholderEmoji = placeholderEmoji
        self.ctaTitle = ctaTitle
        self.retryTitle = retryTitle
        self.makeCreditsViewModel = makeCreditsViewModel
    }

    private var palette: DiscoveryCreationPalette {
        DiscoveryCreationPalette.resolve(for: colorScheme)
    }

    var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(palette.background.ignoresSafeArea())
            .alert(
                item: Binding(
                    get: { activeAlert },
                    set: { newValue in
                        if let newValue {
                            activeAlert = newValue
                        } else {
                            let dismissedAlert = activeAlert
                            activeAlert = nil
                            if case .flowError = dismissedAlert {
                                viewModel.clearError()
                            }
                        }
                    }
                )
            ) { alert(for: $0) }
            .onChange(of: viewModel.error) { _, error in
                DispatchQueue.main.async {
                    if let error {
                        activeAlert = .flowError(IdentifiedError(error: error))
                    } else if case .flowError = activeAlert {
                        activeAlert = nil
                    }
                }
            }
            .onChange(of: viewModel.showPollingFailedAlert) { _, showAlert in
                if showAlert {
                    DispatchQueue.main.async {
                        activeAlert = .pollingFailed
                        viewModel.showPollingFailedAlert = false
                    }
                }
            }
            .onChange(of: viewModel.showFreeCreditsExhaustedAtAudioGeneration) { _, showAlert in
                if showAlert {
                    DispatchQueue.main.async {
                        activeAlert = .freeCreditsExhaustedAtAudioGeneration
                        viewModel.showFreeCreditsExhaustedAtAudioGeneration = false
                    }
                }
            }
            .onChange(of: viewModel.showFreeCreditsExhaustedAtConfirm) { _, showAlert in
                if showAlert {
                    DispatchQueue.main.async {
                        activeAlert = .freeCreditsExhaustedAtConfirm
                        viewModel.showFreeCreditsExhaustedAtConfirm = false
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.refreshLocationPermissionOnForeground()
                }
            }
            .sheet(item: $activeSheet, onDismiss: {
                if presentedCreditsViewModel != nil {
                    presentedCreditsViewModel = nil
                    creditsSheetDetent = .fraction(0.8)
                }
            }) { sheet in
                switch sheet {
                case .credits:
                    NavigationStack {
                        // Use presentedCreditsViewModel directly - it's set before activeSheet
                        if let creditsViewModel = presentedCreditsViewModel {
                            CreditsView(viewModel: creditsViewModel)
                        } else {
                            Text("Credits unavailable")
                                .font(.headline)
                                .padding()
                        }
                    }
                    .presentationDetents([.fraction(0.8), .large], selection: $creditsSheetDetent)
                    .presentationDragIndicator(.visible)
                case .missingUploadLocation:
                    MissingUploadLocationSheet(
                        onOpenPhotos: { openPhotosApp() },
                        onOpenSettings: { openSettingsApp() }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.flowState {
        case .confirming, .analyzing:
            content
        default:
            VStack(spacing: BrandSpacing.large) {
                content
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.vertical, BrandSpacing.large)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.flowState {
        case .idle, .cancelled:
            DiscoveryCaptureStartView(
                emoji: placeholderEmoji,
                title: ctaTitle,
                action: { viewModel.startFlow() }
            )
        case .requestingPermissions, .capturingInitial, .capturingRetake, .selectingInitial, .selectingRetake:
            DiscoveryCaptureProgressView()
        case let .error(message):
            DiscoveryCreationErrorView(
                title: "Something went wrong",
                message: message.isEmpty ? "Please try again." : message,
                actionTitle: retryTitle,
                action: { viewModel.retake() }
            )
        case let .confirming(state):
            DiscoveryConfirmationView(
                state: state,
                creditBalance: viewModel.creditBalance,
                flowType: viewModel.flowType,
                onRetake: { viewModel.retake() },
                onContinue: { viewModel.beginAnalysis() },
                onCancel: { viewModel.cancelFlow() },
                onRequestCredits: makeCreditsHandler,
                onShowLocationPermissions: { showLocationPermissionsAlert() },
                onShowMissingUploadLocation: { presentMissingUploadLocationSheet() },
                onShowOutOfCredits: { showOutOfCreditsAlert() },
                generateAudioGuide: $viewModel.generateAudioGuide
            )
        case .analyzing:
            streamingStage
        }
    }

    @ViewBuilder
    private var streamingStage: some View {
        DiscoveryStreamingStageView(
            viewModel: viewModel,
            imageData: viewModel.confirmationState?.displayImageData,
            capturedAt: viewModel.confirmationState?.media.createdAt,
            onCancel: {
                // Transfer to background instead of cancelling - discovery continues processing
                viewModel.unsubscribe()
            },
            makeCreditsViewModel: makeCreditsViewModel
        )
    }

    private var makeCreditsHandler: (() -> Void)? {
        guard makeCreditsViewModel != nil else {
            return nil
        }
        return { presentCreditsSheet() }
    }

    @MainActor
    private func presentCreditsSheet() {
        guard ensureCreditsViewModel() != nil else { return }
        creditsSheetDetent = .fraction(0.8)
        activeSheet = .credits
    }

    @MainActor
    @discardableResult
    private func ensureCreditsViewModel() -> CreditsViewModel? {
        if let existing = presentedCreditsViewModel {
            return existing
        }
        guard let factory = makeCreditsViewModel else { return nil }
        let creditsViewModel = factory()
        let flowViewModel = viewModel
        creditsViewModel.onBalanceUpdated = { newBalance in
            Task { [weak flowViewModel] in
                await flowViewModel?.syncCreditBalance(newBalance)
            }
        }
        presentedCreditsViewModel = creditsViewModel
        return creditsViewModel
    }

    private func showLocationPermissionsAlert() {
        activeAlert = .locationPermissions
    }

    private func presentMissingUploadLocationSheet() {
        activeSheet = .missingUploadLocation
    }

    private func showOutOfCreditsAlert() {
        activeAlert = .outOfCredits
    }

    private func alert(for activeAlert: ActiveAlert) -> Alert {
        switch activeAlert {
        case let .flowError(identifiedError):
            return alert(forFlowError: identifiedError.error)
        case .locationPermissions:
            return Alert(
                title: Text("Grant Location Permissions"),
                message: Text("We use location to improve the results generated by AI. Allow location access for What's That so we can deliver better results."),
                primaryButton: .default(Text("Settings"), action: openAppSettings),
                secondaryButton: .cancel()
            )
        case .outOfCredits:
            return Alert(
                title: Text("Out of credits"),
                message: Text("Each discovery costs 1 credit. Purchase more to continue."),
                dismissButton: .default(Text("OK"))
            )
        case .pollingFailed:
            return Alert(
                title: Text("Discovery Failed"),
                message: Text("There was an error generating your discovery. Please try again."),
                primaryButton: .default(Text("Retry"), action: {
                    viewModel.retryWithPendingMedia()
                }),
                secondaryButton: .cancel(Text("Cancel"), action: {
                    viewModel.cancelFlow()
                })
            )
        case .freeCreditsExhaustedAtAudioGeneration:
            return Alert(
                title: Text("So Much More to Discover"),
                message: Text("Your free credits are used up. To listen to this discovery as an audio guide and make new discoveries, add credits."),
                primaryButton: .default(Text("Get Credits"), action: {
                    presentCreditsSheet()
                }),
                secondaryButton: .cancel(Text("Not Now"))
            )
        case .freeCreditsExhaustedAtConfirm:
            return Alert(
                title: Text("So Much More to Discover"),
                message: Text("Your free credits are used up. To generate new discoveries and audio guides, add credits."),
                primaryButton: .default(Text("Get Credits"), action: {
                    presentCreditsSheet()
                }),
                secondaryButton: .cancel(Text("Not Now"))
            )
        }
    }

    private func alert(forFlowError error: DiscoveryCreationFlowViewModel.FlowError) -> Alert {
        switch error {
        case .permissionDenied:
            return Alert(
                title: Text("Permission Needed"),
                message: Text(error.localizedDescription),
                primaryButton: .default(Text("Open Settings"), action: openAppSettings),
                secondaryButton: .cancel(Text("Not Now"))
            )
        default:
            return Alert(
                title: Text("Oops"),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func openPhotosApp() {
        let candidates = ["photos-redirect://", "photos://"]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
        }
    }

    private func openSettingsApp() {
        let prefSchemes = ["App-Prefs:", "prefs:"]

        for scheme in prefSchemes {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
        }

        guard let fallbackURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(fallbackURL, options: [:], completionHandler: nil)
    }
}

private struct MissingUploadLocationSheet: View {
    let onOpenPhotos: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let steps = [
        "Open the Photos app.",
        "Select this image.",
        "Tap the Info button at the bottom of the screen.",
        "Tap Add Location."
    ]

    private let cameraLocationSteps = [
        "Open the Settings app.",
        "Tap Privacy & Security.",
        "Choose Location Services and ensure it is enabled.",
        "Scroll to Camera and set Allow Location Access to While Using the App."
    ]

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.large) {
                    VStack(alignment: .leading, spacing: BrandSpacing.small) {
                        Text("No Location Data in This Image")
                            .font(.title2.weight(.semibold))
                        Text("We use location to improve the results generated by AI.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: BrandSpacing.small) {
                        Text("Add a Location to This Image")
                            .font(.headline)
                        Text("To add a location to this image, follow these steps:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                Text("\(index + 1). \(step)")
                                    .font(.subheadline)
                                    .foregroundStyle(palette.textPrimary)
                            }
                        }
                        .padding(.top, 6)

                        actionButton(
                            title: "Open Photos",
                            systemImage: "photo.on.rectangle",
                            style: .prominent,
                            action: onOpenPhotos
                        )
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: BrandSpacing.small) {
                        Text("Keep Location for Future Photos")
                            .font(.headline)
                        Text("Turn on location access for the Camera app so new photos automatically include location details.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(cameraLocationSteps.enumerated()), id: \.offset) { index, step in
                                Text("\(index + 1). \(step)")
                                    .font(.subheadline)
                                    .foregroundStyle(palette.textPrimary)
                            }
                        }
                        .padding(.top, 6)

                        actionButton(
                            title: "Open Settings",
                            systemImage: "gearshape",
                            style: .tinted,
                            action: onOpenSettings
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, BrandSpacing.large)
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.xLarge)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private enum ButtonStyleKind {
        case prominent
        case tinted
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        systemImage: String,
        style: ButtonStyleKind,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .background(buttonBackground(for: style))
        .foregroundStyle(buttonForeground(for: style))
        .overlay(buttonBorder(for: style))
        .clipShape(Capsule(style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
    }

    @ViewBuilder
    private func buttonBackground(for style: ButtonStyleKind) -> some View {
        switch style {
        case .prominent:
            Capsule(style: .continuous)
                .fill(palette.primaryAction)
        case .tinted:
            Capsule(style: .continuous)
                .fill(palette.primaryAction.opacity(0.12))
        }
    }

    private func buttonForeground(for style: ButtonStyleKind) -> Color {
        switch style {
        case .prominent:
            return Color.white
        case .tinted:
            return palette.primaryAction
        }
    }

    @ViewBuilder
    private func buttonBorder(for style: ButtonStyleKind) -> some View {
        switch style {
        case .prominent:
            Capsule(style: .continuous)
                .stroke(palette.primaryAction.opacity(0.6), lineWidth: 0.5)
        case .tinted:
            Capsule(style: .continuous)
                .stroke(palette.primaryAction.opacity(0.4), lineWidth: 1)
        }
    }
}
