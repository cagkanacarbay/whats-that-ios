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

    @StateObject private var viewModel: SettingsViewModel
    @StateObject private var voiceoverViewModel: VoiceoverSettingsViewModel
    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.system.rawValue
    @State private var isNearbyInspectorPresented = false

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
        onClose: @escaping () -> Void,
        loadVoiceoverPreferences: @escaping () async -> VoiceoverPreferences,
        saveVoiceoverPreferences: @escaping (VoiceoverPreferences) async -> Void,
        fetchVoiceOptions: @escaping () async -> [VoiceModelOption]
    ) {
        self.makeCreditsView = makeCreditsView
        self.makeNearbyCacheInspector = makeNearbyCacheInspector
        self.onClose = onClose
        self.loadVoiceoverPreferences = loadVoiceoverPreferences
        self.saveVoiceoverPreferences = saveVoiceoverPreferences
        self.fetchVoiceOptions = fetchVoiceOptions
        _viewModel = StateObject(
            wrappedValue: SettingsViewModel(
                userEmail: userEmail,
                canRequestPasswordReset: canRequestPasswordReset,
                onResetOnboarding: onResetOnboarding,
                onFetchCreditBalance: onFetchCreditBalance,
                onSendPasswordReset: onSendPasswordReset,
                onSignOut: onSignOut,
                onClearAppStoreAccount: onClearAppStoreAccount,
                onClose: onClose
            )
        )
        _voiceoverViewModel = StateObject(
            wrappedValue: VoiceoverSettingsViewModel(
                initialPreferences: VoiceoverPreferences(
                    autoEnabled: false,
                    voiceModelId: "",
                    ttsModel: "s1"
                ),
                loadPreferences: loadVoiceoverPreferences,
                savePreferences: saveVoiceoverPreferences,
                fetchVoiceOptions: fetchVoiceOptions
            )
        )
    }

    var body: some View {
        NavigationStack {
            List {
                creditsSection
                themeSection
                voiceoverSection
                accountSection
                onboardingSection
                devSection
            }
            .task {
                await viewModel.refreshCreditBalance()
                await voiceoverViewModel.load()
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
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
    }

    private var voiceoverSection: some View {
        Section(header: Text("Voiceover")) {
            Toggle("Auto-generate after analysis", isOn: $voiceoverViewModel.preferences.autoEnabled)
                .onChange(of: voiceoverViewModel.preferences.autoEnabled) { _, newValue in
                    Task { await voiceoverViewModel.updateAutoEnabled(newValue) }
                }

            if voiceoverViewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Picker("Voice", selection: $voiceoverViewModel.preferences.voiceModelId) {
                    ForEach(voiceoverViewModel.voiceOptions, id: \.voiceModelId) { option in
                        Text(option.displayName).tag(option.voiceModelId)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: voiceoverViewModel.preferences.voiceModelId) { _, newValue in
                    Task { await voiceoverViewModel.selectVoice(withId: newValue) }
                }
            }
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
        }
    }

    private var creditsSection: some View {
        Section(header: Text("Credits")) {
            NavigationLink {
                makeCreditsView { newBalance in
                    viewModel.updateCreditBalance(newBalance)
                }
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
        Task { await viewModel.performReset() }
    }

    private func signOut() {
        Task { await viewModel.performSignOut() }
    }
}
