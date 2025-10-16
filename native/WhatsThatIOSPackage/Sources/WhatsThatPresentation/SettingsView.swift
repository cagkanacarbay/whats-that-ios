import SwiftUI
import WhatsThatShared

struct SettingsView: View {
    enum AlertState: Equatable {
        case confirmReset
        case finished
        case error(String)
    }

    let onResetOnboarding: () async -> Result<Void, Error>
    let onClose: () -> Void

    @State private var isProcessing = false
    @State private var alertState: AlertState?
    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.system.rawValue

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                onboardingSection
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

    @MainActor
    private func setProcessingState(active: Bool) -> Bool {
        if active && isProcessing { return false }
        isProcessing = active
        if active {
            alertState = nil
        }
        return true
    }
}

extension SettingsView.AlertState: Identifiable {
    var id: String {
        switch self {
        case .confirmReset:
            return "confirm"
        case .finished:
            return "finished"
        case .error(let message):
            return "error_\(message)"
        }
    }
}
