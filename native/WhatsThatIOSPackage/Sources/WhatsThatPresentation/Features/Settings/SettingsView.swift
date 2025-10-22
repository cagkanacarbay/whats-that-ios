import SwiftUI
import WhatsThatShared

struct SettingsView: View {
    private let makeCreditsView: (@escaping (Int?) -> Void) -> AnyView
    private let onClose: () -> Void

    @StateObject private var viewModel: SettingsViewModel
    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.system.rawValue

    init(
        onResetOnboarding: @escaping () async -> Result<Void, Error>,
        onFetchCreditBalance: @escaping () async -> Result<Int, Error>,
        makeCreditsView: @escaping (@escaping (Int?) -> Void) -> AnyView,
        onSignOut: @escaping () async -> Result<Void, Error>,
        onClose: @escaping () -> Void
    ) {
        self.makeCreditsView = makeCreditsView
        self.onClose = onClose
        _viewModel = StateObject(
            wrappedValue: SettingsViewModel(
                onResetOnboarding: onResetOnboarding,
                onFetchCreditBalance: onFetchCreditBalance,
                onSignOut: onSignOut,
                onClose: onClose
            )
        )
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                appearanceSection
                onboardingSection
            }
            .task {
                await viewModel.refreshCreditBalance()
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
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
                case .error(let message):
                    return Alert(
                        title: Text("Something went wrong"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }

    private var accountSection: some View {
        Section(header: Text("Account")) {
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

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .padding(.vertical, 4)
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

    private var appearanceSection: some View {
        Section(header: Text("Appearance")) {
            Picker("Theme", selection: appearanceBinding) {
                ForEach(AppAppearance.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.symbolName)
                        .tag(mode)
                }
            }
            .pickerStyle(.inline)
            .accessibilityIdentifier("settings.appearancePicker")

            Text(appearance.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    private var onboardingSection: some View {
        Section(header: Text("Cache & Onboarding")) {
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
