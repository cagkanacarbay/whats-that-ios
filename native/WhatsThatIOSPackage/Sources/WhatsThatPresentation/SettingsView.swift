import SwiftUI
import WhatsThatShared

struct SettingsView: View {
    enum AlertState: Equatable {
        case confirmReset
        case confirmSignOut
        case finished
        case error(String)
    }

    let onResetOnboarding: () async -> Result<Void, Error>
    let onFetchCreditBalance: () async -> Result<Int, Error>
    let makeCreditsView: (@escaping (Int?) -> Void) -> AnyView
    let onSignOut: () async -> Result<Void, Error>
    let onClose: () -> Void

    @State private var isProcessing = false
    @State private var isSigningOut = false
    @State private var isLoadingCredits = false
    @State private var creditBalance: Int?
    @State private var alertState: AlertState?
    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.system.rawValue

    var body: some View {
        NavigationStack {
            List {
                accountSection
                appearanceSection
                onboardingSection
            }
            .task {
                await refreshCreditBalance()
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onClose)
                }
            }
            .alert(item: $alertState) { state in
                switch state {
                case .confirmReset:
                    return Alert(
                        title: Text("Reset onboarding?"),
                        message: Text("This will clear cached onboarding progress. You can re-run it immediately."),
                        primaryButton: .destructive(Text("Reset")) {
                            Task { await performReset() }
                        },
                        secondaryButton: .cancel {
                            alertState = nil
                        }
                    )
                case .confirmSignOut:
                    return Alert(
                        title: Text("Sign out?"),
                        message: Text("You will need to log in again to access your discoveries."),
                        primaryButton: .destructive(Text("Sign out")) {
                            Task { await performSignOut() }
                        },
                        secondaryButton: .cancel {
                            alertState = nil
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
                    creditBalance = newBalance
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

                    if isLoadingCredits {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else if let balance = creditBalance {
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
                alertState = .confirmSignOut
            } label: {
                HStack {
                    if isSigningOut {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text("Sign out")
                }
            }
            .disabled(isSigningOut)
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
                alertState = .confirmReset
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text("Reset onboarding experience")
                }
            }
            .disabled(isProcessing)
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

    private func performReset() async {
        guard await setProcessingState(active: true) else { return }

        let result = await onResetOnboarding()

        await MainActor.run {
            isProcessing = false
            switch result {
            case .success:
                alertState = .finished
            case .failure(let error):
                alertState = .error(error.localizedDescription)
            }
        }
    }

    private func performSignOut() async {
        await MainActor.run {
            alertState = nil
        }

        guard await setSignOutState(active: true) else { return }

        let result = await onSignOut()

        await MainActor.run {
            isSigningOut = false
            switch result {
            case .success:
                onClose()
            case .failure(let error):
                alertState = .error(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func setProcessingState(active: Bool) -> Bool {
        if active && isProcessing { return false }
        isProcessing = active
        if active {
            alertState = nil
        }
        return true
    }

    @MainActor
    private func setSignOutState(active: Bool) -> Bool {
        if active && isSigningOut { return false }
        isSigningOut = active
        if active {
            alertState = nil
        }
        return true
    }

    private func refreshCreditBalance() async {
        if isLoadingCredits { return }
        await MainActor.run {
            isLoadingCredits = true
        }

        let result = await onFetchCreditBalance()

        await MainActor.run {
            isLoadingCredits = false
            switch result {
            case .success(let balance):
                creditBalance = balance
            case .failure(let error):
                alertState = .error(error.localizedDescription)
                creditBalance = nil
            }
        }
    }
}

extension SettingsView.AlertState: Identifiable {
    var id: String {
        switch self {
        case .confirmReset:
            return "confirm"
        case .confirmSignOut:
            return "signOut"
        case .finished:
            return "finished"
        case .error(let message):
            return "error_\(message)"
        }
    }
}
