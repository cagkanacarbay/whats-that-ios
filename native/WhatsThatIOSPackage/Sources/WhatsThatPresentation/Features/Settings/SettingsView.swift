import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct SettingsView: View {
    private let makeCreditsView: (@escaping (Int?) -> Void) -> AnyView
    private let makeNearbyCacheInspector: () -> AnyView
    private let onClose: () -> Void
    private let loadVoiceoverPreferences: () async -> VoiceoverPreferences
    private let saveVoiceoverPreferences: (VoiceoverPreferences) async -> Void
    private let fetchVoiceOptions: () async -> [VoiceModelOption]
    private let fetchVoiceSampleURL: (String) async -> URL?

    @StateObject private var viewModel: SettingsViewModel
    @StateObject private var voicePickerViewModel: VoicePickerViewModel
    @StateObject private var ipopPreferencesViewModel: IPoPPreferencesViewModel
    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.system.rawValue
    @State private var isNearbyInspectorPresented = false
    @State private var isCreditsSheetPresented = false
    @State private var isVoicePickerPresented = false
    @State private var isIPoPSheetPresented = false
    @State private var initialVoiceModelId: String?
    @State private var committedVoiceModelId: String?

    init(
        userEmail: String?,
        canRequestPasswordReset: Bool,
        onResetOnboarding: @escaping () async -> Result<Void, Error>,
        onFetchCreditBalance: @escaping () async -> Result<Int, Error>,
        makeCreditsView: @escaping (@escaping (Int?) -> Void) -> AnyView,
        makeNearbyCacheInspector: @escaping () -> AnyView,
        onSendPasswordReset: @escaping (String) async -> Result<Void, AuthError>,
        onSignOut: @escaping () async -> Result<Void, Error>,
        onClearAppStoreAccount: @escaping () async -> Result<Void, Error>,
        onDeleteAccount: @escaping () async -> Result<Void, Error>,
        onClose: @escaping () -> Void,
        loadVoiceoverPreferences: @escaping () async -> VoiceoverPreferences,
        saveVoiceoverPreferences: @escaping (VoiceoverPreferences) async -> Void,
        fetchVoiceOptions: @escaping () async -> [VoiceModelOption],
        fetchVoiceSampleURL: @escaping (String) async -> URL?,
        loadIPoPPreferences: @escaping () async -> IPoPPreferences?,
        saveIPoPPreferences: @escaping (IPoPPreferences) async -> Void
    ) {
        self.makeCreditsView = makeCreditsView
        self.makeNearbyCacheInspector = makeNearbyCacheInspector
        self.onClose = onClose
        self.loadVoiceoverPreferences = loadVoiceoverPreferences
        self.saveVoiceoverPreferences = saveVoiceoverPreferences
        self.fetchVoiceOptions = fetchVoiceOptions
        self.fetchVoiceSampleURL = fetchVoiceSampleURL
        _viewModel = StateObject(
            wrappedValue: SettingsViewModel(
                userEmail: userEmail,
                canRequestPasswordReset: canRequestPasswordReset,
                onResetOnboarding: onResetOnboarding,
                onFetchCreditBalance: onFetchCreditBalance,
                onSendPasswordReset: onSendPasswordReset,
                onSignOut: onSignOut,
                onClearAppStoreAccount: onClearAppStoreAccount,
                onDeleteAccount: onDeleteAccount,
                onClose: onClose
            )
        )
        _voicePickerViewModel = StateObject(
            wrappedValue: VoicePickerViewModel(
                loadVoiceoverPreferences: loadVoiceoverPreferences,
                saveVoiceoverPreferences: saveVoiceoverPreferences,
                fetchVoiceOptions: fetchVoiceOptions,
                fetchVoiceSampleURL: fetchVoiceSampleURL
            )
        )
        _ipopPreferencesViewModel = StateObject(
            wrappedValue: IPoPPreferencesViewModel(
                loadPreferences: loadIPoPPreferences,
                savePreferences: saveIPoPPreferences
            )
        )
    }

    var body: some View {
        NavigationStack {
            List {
                creditsSection
                themeSection
                ipopSection
                audioGuidesSection
                accountSection
                #if DEBUG
                onboardingSection
                devSection
                cacheDebugSection
                #endif
            }
            .task {
                await viewModel.refreshCreditBalance()
                await voicePickerViewModel.ensureLoadedForDisplay()
                await ipopPreferencesViewModel.ensureLoaded()
                if committedVoiceModelId == nil {
                    committedVoiceModelId = voicePickerViewModel.selectedVoiceId
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
            .sheet(isPresented: $isCreditsSheetPresented) {
                makeCreditsView { newBalance in
                    viewModel.updateCreditBalance(newBalance)
                }
            }
            .sheet(isPresented: $isVoicePickerPresented) {
                AudioGuidePickerSheet(
                    viewModel: voicePickerViewModel,
                    onConfirm: confirmVoiceSelection,
                    onCancel: revertVoiceSelection
                )
            }
            .sheet(isPresented: $isIPoPSheetPresented) {
                IPoPPreferencesSheet(
                    viewModel: ipopPreferencesViewModel,
                    onSaved: {
                        isIPoPSheetPresented = false
                    },
                    onCancel: {
                        ipopPreferencesViewModel.resetDraftToPersistedOrDefault()
                        isIPoPSheetPresented = false
                    }
                )
            }
            .alert(item: alertBinding) { state in
                switch state {
                case .confirmReset:
                    return Alert(
                        title: Text("Reset onboarding?"),
                        message: Text("This will clear cached onboarding progress. You can re-run it immediately."),
                        primaryButton: .destructive(Text("Reset"), action: resetOnboarding),
                        secondaryButton: .cancel {
                            viewModel.dismissAlert()
                        }
                    )
                case .confirmSignOut:
                    return Alert(
                        title: Text("Sign out?"),
                        message: Text("You will need to log in again to access your discoveries."),
                        primaryButton: .destructive(Text("Sign out"), action: signOut),
                        secondaryButton: .cancel {
                            viewModel.dismissAlert()
                        }
                    )
                case .confirmDeleteAccount:
                    // This case is handled by the sheet, so just dismiss if it somehow appears
                    return Alert(
                        title: Text("Delete account"),
                        message: Text("Please use the confirmation sheet."),
                        dismissButton: .default(Text("OK")) {
                            viewModel.dismissAlert()
                        }
                    )
                case .finished:
                    return Alert(
                        title: Text("Done"),
                        message: Text("Onboarding has been reset."),
                        dismissButton: .default(Text("OK")) {
                            onClose()
                        }
                    )
                case .appStoreCleared:
                    return Alert(
                        title: Text("Cache cleared"),
                        message: Text("Local App Store receipt and purchase cache cleared for this app."),
                        dismissButton: .default(Text("OK")) {
                            viewModel.dismissAlert()
                        }
                    )
                case .error(let message):
                    return Alert(
                        title: Text("Something went wrong"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                case .passwordResetSent(let email):
                    return Alert(
                        title: Text("Check your email"),
                        message: Text("We've sent password reset instructions to \(email)."),
                        dismissButton: .default(Text("OK")) {
                            viewModel.dismissAlert()
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingDeletionConfirmation) {
            DeleteAccountConfirmationSheet(
                confirmationText: $viewModel.deletionConfirmationText,
                canConfirm: viewModel.canConfirmDeletion,
                onConfirm: {
                    Task { await viewModel.performAccountDeletion() }
                },
                onCancel: {
                    viewModel.cancelDeleteAccountConfirmation()
                }
            )
            .presentationDetents([.medium])
        }
        .overlay {
            if viewModel.isDeletingAccount {
                DeletingAccountOverlay()
            }
        }
    }

    private var audioGuidesSection: some View {
        Section(header: Text("Audio guides")) {
            Toggle("Auto-generate audio guides after analysis (1 credit)", isOn: autoGenerateAudioGuideBinding)

            Button {
                initialVoiceModelId = committedVoiceModelId ?? voicePickerViewModel.selectedVoiceId
                if let initialVoiceModelId {
                    voicePickerViewModel.selectedVoiceId = initialVoiceModelId
                }
                isVoicePickerPresented = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice model")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.primary)

                        if let selectedVoiceName {
                            Text(selectedVoiceName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if voicePickerViewModel.voices.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("Loading voices")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Choose a voice")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.vertical, 4)
            }
            .disabled(voicePickerViewModel.voices.isEmpty)
            .accessibilityIdentifier("settings.audioGuides.voicePicker")
        }
    }

    private var ipopSection: some View {
        Section(header: Text("Content preferences")) {
            Button {
                ipopPreferencesViewModel.resetDraftToPersistedOrDefault()
                isIPoPSheetPresented = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Content preferences")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.primary)

                        if let summary = ipopPreferencesViewModel.summaryOrder {
                            ipopSummaryChips(summary)
                        } else {
                            Text("Not set yet")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("settings.ipop")

            Text("We use your preferences to craft responses that interest you.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        }
    }

    private var accountSection: some View {
        Section(header: Text("Account")) {
            if viewModel.canRequestPasswordReset {
                Button {
                    Task { await viewModel.performPasswordReset() }
                } label: {
                    HStack {
                        if viewModel.isRequestingPasswordReset {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        Text("Email me a reset link")
                        Spacer()
                    }
                }
                .disabled(viewModel.isRequestingPasswordReset)
                .accessibilityIdentifier("settings.resetPassword")

                if let email = viewModel.userEmail {
                    Text("We'll send instructions to \(email).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }
            }

            Button(role: .destructive) {
                viewModel.presentSignOutConfirmation()
            } label: {
                HStack {
                    if viewModel.isSigningOut {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text("Sign out")
                }
            }
            .disabled(viewModel.isSigningOut)
            .accessibilityIdentifier("settings.signOut")

            Button(role: .destructive) {
                viewModel.presentDeleteAccountConfirmation()
            } label: {
                Text("Delete account")
            }
            .accessibilityIdentifier("settings.deleteAccount")
        }
    }

    private var creditsSection: some View {
        Section(header: Text("Credits")) {
            Button {
                isCreditsSheetPresented = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Color.accentColor)

                    Text("Credits")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.primary)

                    Spacer()

                    if viewModel.isLoadingCredits {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else if let balance = viewModel.creditBalance {
                        Text("\(balance)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                    } else {
                        Text("—")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var themeSection: some View {
        Section(header: Text("Theme")) {
            Picker(selection: appearanceBinding) {
                ForEach(AppAppearance.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.symbolName)
                        .tag(mode)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .accessibilityIdentifier("settings.appearancePicker")
            .accessibilityLabel("Theme")

            Text(appearance.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    #if DEBUG
    private var onboardingSection: some View {
        Section(header: Text("Cache & Onboarding")) {
            Button {
                Task { await viewModel.clearAppStoreAccount() }
            } label: {
                HStack {
                    if viewModel.isClearingAppStore {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text("Clear App Store account cache")
                }
            }
            .disabled(viewModel.isClearingAppStore)
            .accessibilityIdentifier("settings.clearAppStoreAccount")

            Text("Removes the local App Store receipt and cached purchase info used by this app. Useful to see when iOS prompts for Apple ID during purchases. Does not sign you out of the App Store.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)

            Button(role: .destructive) {
                viewModel.presentResetConfirmation()
            } label: {
                HStack {
                    if viewModel.isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text("Reset onboarding experience")
                }
            }
            .disabled(viewModel.isProcessing)
            .accessibilityIdentifier("settings.resetOnboarding")

            Text("Clears saved onboarding state so you can replay the intro slides and permission prompts. Your account stays signed in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }
    #endif

    #if DEBUG
    private var devSection: some View {
        Section(header: Text("Development")) {
            Button {
                isNearbyInspectorPresented = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Color.accentColor)
                    Text("Nearby places cache (dev)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.primary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .sheet(isPresented: $isNearbyInspectorPresented) {
                makeNearbyCacheInspector()
            }
        }
    }
    #endif
    
    #if DEBUG
    @Environment(\.audioServices) private var audioServices
    @State private var cacheAlertMessage: String?
    @State private var showCacheAlert = false
    #endif
    
    #if DEBUG
    private var cacheDebugSection: some View {
        Section(header: Text("Cache Management (Dev)")) {
            // Audio Files Cache
            Button(role: .destructive) {
                Task {
                    await VoiceoverFileCache.shared.clearAll()
                    cacheAlertMessage = "Cleared voiceover audio files cache"
                    showCacheAlert = true
                }
            } label: {
                cacheButtonLabel(
                    icon: "waveform",
                    title: "Clear Audio Files Cache",
                    subtitle: "Downloaded voiceover audio files"
                )
            }
            
            // Discovery Images Cache
            Button(role: .destructive) {
                Task {
                    await DiscoveryAssetCache.shared.clearAll()
                    cacheAlertMessage = "Cleared discovery images cache"
                    showCacheAlert = true
                }
            } label: {
                cacheButtonLabel(
                    icon: "photo.stack",
                    title: "Clear Discovery Images Cache",
                    subtitle: "Cached discovery thumbnails and images"
                )
            }
            
            // Clear All Audio Data (combined button)
            Button(role: .destructive) {
                Task {
                    await clearAllAudioData()
                    cacheAlertMessage = "Cleared all audio data: files, queue, history, and progress"
                    showCacheAlert = true
                }
            } label: {
                cacheButtonLabel(
                    icon: "speaker.slash",
                    title: "Clear All Audio Data",
                    subtitle: "Audio files, queue, history, progress - everything"
                )
            }
            
            // Clear All Caches
            Button(role: .destructive) {
                Task {
                    await VoiceoverFileCache.shared.clearAll()
                    await DiscoveryAssetCache.shared.clearAll()
                    await clearAllAudioData()
                    cacheAlertMessage = "Cleared all caches"
                    showCacheAlert = true
                }
            } label: {
                cacheButtonLabel(
                    icon: "trash",
                    title: "Clear All Caches",
                    subtitle: "Audio files, images, queue, and progress"
                )
            }
        }
        .alert("Cache Cleared", isPresented: $showCacheAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(cacheAlertMessage ?? "Cache cleared successfully")
        }
    }
    #endif
    #if DEBUG
    private func cacheButtonLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(Color.red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    /// Clears all audio-related data including queue, history, and progress.
    /// Uses audioServices if available, otherwise falls back to direct UserDefaults removal.
    private func clearAllAudioData() async {
        // Clear voiceover audio files
        await VoiceoverFileCache.shared.clearAll()
        
        // Try to clear via audioServices first (updates in-memory state)
        if let services = audioServices {
            services.queueStore.clearAll()
            services.progressStore.clearAll()
        }
        
        // Also directly remove from UserDefaults to ensure persistence is cleared
        // This handles cases where audioServices might not be available or state wasn't synced
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "audio_guides_queue_store")
        defaults.removeObject(forKey: "voiceover_positions")
        defaults.removeObject(forKey: "voiceover_last_played")
        defaults.synchronize()
    }
    #endif

    private var appearance: AppAppearance {
        AppAppearance(rawValue: storedAppearance) ?? .system
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { appearance },
            set: { newValue in
                storedAppearance = newValue.rawValue
                BrandTheme.activeMode = newValue.brandMode
            }
        )
    }

    private var alertBinding: Binding<SettingsViewModel.AlertState?> {
        Binding(
            get: { viewModel.alertState },
            set: { viewModel.alertState = $0 }
        )
    }

    private func resetOnboarding() {
        Task {
            let didReset = await viewModel.performReset()
            if didReset {
                ipopPreferencesViewModel.clearPersisted()
            }
        }
    }

    private func signOut() {
        Task { await viewModel.performSignOut() }
    }

    private var selectedVoiceName: String? {
        guard let selectedId = committedVoiceModelId else { return nil }
        return voicePickerViewModel.voices.first(where: { $0.voiceModelId == selectedId })?.displayName
    }

    private var autoGenerateAudioGuideBinding: Binding<Bool> {
        Binding(
            get: { voicePickerViewModel.isAutoEnabled },
            set: { newValue in voicePickerViewModel.setAutoEnabled(newValue) }
        )
    }

    private func ipopSummaryChips(_ items: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .foregroundStyle(Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(Color.accentColor)
            }
        }
        .dynamicTypeSize(.large)
    }

    private func confirmVoiceSelection() {
        Task {
            committedVoiceModelId = voicePickerViewModel.selectedVoiceId
            await voicePickerViewModel.persistCurrentSelection()
            isVoicePickerPresented = false
        }
    }

    private func revertVoiceSelection() {
        if let initialVoiceModelId {
            voicePickerViewModel.selectedVoiceId = initialVoiceModelId
        }
        voicePickerViewModel.stop()
    }
}

private struct AudioGuidePickerSheet: View {
    @ObservedObject var viewModel: VoicePickerViewModel
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasConfirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            HStack {
                Button {
                    hasConfirmed = true
                    onCancel()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Settings")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                Spacer()
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.top, BrandSpacing.large)

            Text("Select an audio guide narrator")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, BrandSpacing.large)

            VoicePickerView(
                viewModel: viewModel,
                showCreditNote: true,
                showAutoToggle: false,
                persistSelectionOnTap: false
            )
            .padding(.top, BrandSpacing.small)

            BrandPrimaryButton(title: "Confirm voice") {
                hasConfirmed = true
                onConfirm()
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.large)
        }
        .onDisappear {
            if !hasConfirmed {
                onCancel()
            }
        }
    }
}

// MARK: - Delete Account Confirmation Sheet

private struct DeleteAccountConfirmationSheet: View {
    @Binding var confirmationText: String
    let canConfirm: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            HStack {
                Button {
                    onCancel()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                Spacer()
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.top, BrandSpacing.large)

            Text("Delete your account?")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, BrandSpacing.large)

            Text("This action is permanent. All your discoveries, credits, and data will be deleted and cannot be recovered.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, BrandSpacing.large)

            VStack(alignment: .leading, spacing: 8) {
                Text("Type **delete my account** to confirm:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("delete my account", text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("settings.deleteAccountConfirmationField")
            }
            .padding(.horizontal, BrandSpacing.large)

            Spacer()

            Button(role: .destructive) {
                onConfirm()
            } label: {
                Text("Delete my account")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canConfirm ? Color.red : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canConfirm)
            .padding(.horizontal, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.large)
            .accessibilityIdentifier("settings.deleteAccountConfirmButton")
        }
    }
}

// MARK: - Deleting Account Overlay

private struct DeletingAccountOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: BrandSpacing.large) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("We're sad to see you go...")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("Deleting your account and data")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding()
        }
    }
}
