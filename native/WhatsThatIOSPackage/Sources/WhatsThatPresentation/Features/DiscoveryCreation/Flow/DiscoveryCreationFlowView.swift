import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared

struct DiscoveryCreationFlowView: View {
    private enum ActiveAlert: Identifiable {
        case flowError(IdentifiedError)
        case locationPermissions
        case pollingFailed

        var id: String {
            switch self {
            case let .flowError(identifiedError):
                return identifiedError.id.uuidString
            case .locationPermissions:
                return "locationPermissions"
            case .pollingFailed:
                return "pollingFailed"
            }
        }
    }

    private enum ActiveSheet: Identifiable, Equatable {
        case credits(CreditsViewModel)
        case missingUploadLocation

        var id: String {
            switch self {
            case .credits:
                return "credits"
            case .missingUploadLocation:
                return "missingUploadLocation"
            }
        }

        // Custom Equatable - only compare cases, not associated values
        static func == (lhs: ActiveSheet, rhs: ActiveSheet) -> Bool {
            switch (lhs, rhs) {
            case (.credits, .credits):
                return true
            case (.missingUploadLocation, .missingUploadLocation):
                return true
            default:
                return false
            }
        }
    }

    @ObservedObject private var viewModel: DiscoveryCreationFlowViewModel
    let placeholderEmoji: String
    let ctaTitle: String
    let retryTitle: String
    /// When true, this view is the overlay instance and should present sheets like the audio generating modal.
    /// When false, this view is embedded in a tab and should not present to avoid duplicate presentation conflicts.
    private let isOverlay: Bool
    /// Called when user taps "Discover Another" from the audio generating modal.
    /// MainTabView handles this to switch to the appropriate tab before starting the new flow.
    private let onDiscoverAnother: (() -> Void)?
    private let makeCreditsViewModel: (() -> CreditsViewModel)?
    private let fetchRecentDiscoveries: (() -> [DiscoverySummary])?

    // Post-purchase configuration closures
    private let loadVoiceoverPreferences: (() async -> VoiceoverPreferences)?
    private let saveVoiceoverPreferences: ((VoiceoverPreferences) async -> Void)?
    private let fetchVoiceOptions: (() async -> [VoiceModelOption])?
    private let fetchVoiceSampleURL: ((String) async -> URL?)?
    private let loadIPoPPreferences: (() async -> IPoPPreferences?)?
    private let saveIPoPPreferences: ((IPoPPreferences) async -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var presentedCreditsViewModel: CreditsViewModel?
    @State private var creditsSheetDetent: PresentationDetent = .fraction(0.8)
    @State private var activeAlert: ActiveAlert?
    @State private var activeSheet: ActiveSheet?
    @State private var shouldCreateAnotherAfterModalDismiss = false
    @State private var shouldPresentCreditsAfterExhaustedDismiss = false
    @State private var wasCreditsSheetPresented = false
    @Environment(\.scenePhase) private var scenePhase

    init(
        viewModel: DiscoveryCreationFlowViewModel,
        placeholderEmoji: String,
        ctaTitle: String,
        retryTitle: String,
        isOverlay: Bool = false,
        onDiscoverAnother: (() -> Void)? = nil,
        makeCreditsViewModel: (() -> CreditsViewModel)? = nil,
        fetchRecentDiscoveries: (() -> [DiscoverySummary])? = nil,
        loadVoiceoverPreferences: (() async -> VoiceoverPreferences)? = nil,
        saveVoiceoverPreferences: ((VoiceoverPreferences) async -> Void)? = nil,
        fetchVoiceOptions: (() async -> [VoiceModelOption])? = nil,
        fetchVoiceSampleURL: ((String) async -> URL?)? = nil,
        loadIPoPPreferences: (() async -> IPoPPreferences?)? = nil,
        saveIPoPPreferences: ((IPoPPreferences) async -> Void)? = nil
    ) {
        _viewModel = ObservedObject(initialValue: viewModel)
        self.placeholderEmoji = placeholderEmoji
        self.ctaTitle = ctaTitle
        self.retryTitle = retryTitle
        self.isOverlay = isOverlay
        self.onDiscoverAnother = onDiscoverAnother
        self.makeCreditsViewModel = makeCreditsViewModel
        self.fetchRecentDiscoveries = fetchRecentDiscoveries
        self.loadVoiceoverPreferences = loadVoiceoverPreferences
        self.saveVoiceoverPreferences = saveVoiceoverPreferences
        self.fetchVoiceOptions = fetchVoiceOptions
        self.fetchVoiceSampleURL = fetchVoiceSampleURL
        self.loadIPoPPreferences = loadIPoPPreferences
        self.saveIPoPPreferences = saveIPoPPreferences
    }

    private var palette: DiscoveryCreationPalette {
        DiscoveryCreationPalette.resolve(for: colorScheme)
    }

    // During analyzing phase, only ignore top safe area so tab bar remains visible
    private var backgroundSafeAreaEdges: Edge.Set {
        switch viewModel.flowState {
        case .analyzing:
            return .top
        default:
            return .all
        }
    }

    var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(palette.background.ignoresSafeArea(edges: backgroundSafeAreaEdges))
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
            // Credits exhausted alerts are now handled via fullScreenCover below
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.refreshLocationPermissionOnForeground()
                }
            }
            // Detect when credits sheet closes and force refresh state
            // This is more reliable than onDismiss which can have timing issues
            .onChange(of: activeSheet) { _, newValue in
                // Track when credits sheet was presented
                if case .credits = newValue {
                    wasCreditsSheetPresented = true
                }
                // When sheet closes after credits was shown, force refresh
                if newValue == nil && wasCreditsSheetPresented {
                    wasCreditsSheetPresented = false
                    presentedCreditsViewModel = nil
                    creditsSheetDetent = .fraction(0.8)
                    Task {
                        await viewModel.refreshStateAfterCreditsSheet()
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .credits(let creditsViewModel):
                    NavigationStack {
                        CreditsView(
                            viewModel: creditsViewModel,
                            loadVoiceoverPreferences: loadVoiceoverPreferences,
                            saveVoiceoverPreferences: saveVoiceoverPreferences,
                            fetchVoiceOptions: fetchVoiceOptions,
                            fetchVoiceSampleURL: fetchVoiceSampleURL,
                            loadIPoPPreferences: loadIPoPPreferences,
                            saveIPoPPreferences: saveIPoPPreferences
                        )
                    }
                    .presentationDetents([.fraction(0.8), .large], selection: $creditsSheetDetent)
                    .presentationDragIndicator(.visible)
                case .missingUploadLocation:
                    MissingUploadLocationSheet(
                        onOpenPhotos: { openPhotosApp() },
                        onOpenSettings: { openSystemSettings() }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            // Audio generating modal - only presented by overlay to avoid duplicate presentation conflicts
            // when both embedded tab view and overlay share the same viewModel
            .sheet(
                isPresented: Binding(
                    get: { isOverlay && viewModel.showAudioGeneratingModal },
                    set: { viewModel.showAudioGeneratingModal = $0 }
                ),
                onDismiss: {
                    // Handle "Create Another" action AFTER sheet is fully dismissed.
                    // This prevents the camera picker from trying to present on the dismissing modal.
                    if shouldCreateAnotherAfterModalDismiss {
                        shouldCreateAnotherAfterModalDismiss = false
                        if let onDiscoverAnother {
                            onDiscoverAnother()
                        } else {
                            viewModel.unsubscribe()
                            viewModel.retake()
                        }
                    }
                }
            ) {
                AudioGeneratingModalView(
                    onCreateAnother: {
                        // Dismiss modal first, then trigger action in onDismiss.
                        // This ensures the modal is fully dismissed before starting new camera flow,
                        // preventing "view not in window hierarchy" errors.
                        viewModel.showAudioGeneratingModal = false
                        shouldCreateAnotherAfterModalDismiss = true
                    },
                    onReadThisDiscovery: {
                        viewModel.showAudioGeneratingModal = false
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $viewModel.showFreeCreditsExhaustedAtConfirm, onDismiss: {
                // Present credits sheet AFTER fullScreenCover is fully dismissed to avoid SwiftUI race condition
                if shouldPresentCreditsAfterExhaustedDismiss {
                    shouldPresentCreditsAfterExhaustedDismiss = false
                    // Small delay to ensure clean presentation after dismiss animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        presentCreditsSheet()
                    }
                }
            }) {
                CreditsExhaustedFullScreenView(
                    discoveries: Array((fetchRecentDiscoveries?() ?? []).prefix(3)),
                    playbackController: nil,
                    onGetCredits: {
                        // Don't mark intro complete - user needs to actually purchase credits
                        // Intro mode will exit when balance > 6 (via resolveIntroStateIfNeeded or purchase handler)
                        // Set flag to present credits sheet after this fullScreenCover dismisses
                        shouldPresentCreditsAfterExhaustedDismiss = true
                        viewModel.showFreeCreditsExhaustedAtConfirm = false
                    },
                    onDismiss: {
                        // Don't mark intro complete - modal will show again next time they try to create
                        // This ensures user keeps seeing the modal until they purchase credits
                        shouldPresentCreditsAfterExhaustedDismiss = false
                        viewModel.showFreeCreditsExhaustedAtConfirm = false
                    }
                )
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
                generateAudioGuide: $viewModel.generateAudioGuide,
                isAudioToggleLocked: viewModel.isInIntroMode
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
            onNewDiscovery: {
                // Use MainTabView's callback if available (for overlay) to ensure proper
                // tab switching and state restoration when user cancels. This matches
                // the behavior of "Discover Another" from the audio generating modal.
                if let onDiscoverAnother = onDiscoverAnother {
                    onDiscoverAnother()
                } else {
                    // Fallback for embedded tab views (not the overlay)
                    viewModel.unsubscribe()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewModel.retake()
                    }
                }
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
        let creditsViewModel: CreditsViewModel
        if let existing = presentedCreditsViewModel {
            creditsViewModel = existing
        } else {
            guard let factory = makeCreditsViewModel else { return }
            let newViewModel = factory()
            let flowViewModel = viewModel
            newViewModel.onBalanceUpdated = { newBalance in
                Task { [weak flowViewModel] in
                    await flowViewModel?.syncCreditBalance(newBalance)
                }
            }
            presentedCreditsViewModel = newViewModel
            creditsViewModel = newViewModel
        }

        creditsSheetDetent = .fraction(0.8)
        activeSheet = .credits(creditsViewModel)
    }

    private func showLocationPermissionsAlert() {
        activeAlert = .locationPermissions
    }

    private func presentMissingUploadLocationSheet() {
        activeSheet = .missingUploadLocation
    }

    private func alert(for activeAlert: ActiveAlert) -> Alert {
        switch activeAlert {
        case let .flowError(identifiedError):
            return alert(forFlowError: identifiedError.error)
        case .locationPermissions:
            return Alert(
                title: Text("Grant Location Permissions"),
                message: Text("We use location to improve the results generated by AI. Allow location access for What's That so we can deliver better results."),
                primaryButton: .default(Text("Settings"), action: openApplicationSettings),
                secondaryButton: .cancel()
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
        }
    }

    private func alert(forFlowError error: DiscoveryCreationFlowViewModel.FlowError) -> Alert {
        switch error {
        case .permissionDenied, .cameraPermissionDenied:
            return Alert(
                title: Text("Camera Access Required"),
                message: Text(error.localizedDescription),
                primaryButton: .default(Text("Go to Settings"), action: openApplicationSettings),
                secondaryButton: .cancel(Text("Cancel"))
            )
        case .photoLibraryPermissionDenied:
            return Alert(
                title: Text("Photo Access Required"),
                message: Text(error.localizedDescription),
                primaryButton: .default(Text("Go to Settings"), action: openApplicationSettings),
                secondaryButton: .cancel(Text("Cancel"))
            )
        default:
            return Alert(
                title: Text("Oops"),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func openApplicationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
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

    private func openSystemSettings() {
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
