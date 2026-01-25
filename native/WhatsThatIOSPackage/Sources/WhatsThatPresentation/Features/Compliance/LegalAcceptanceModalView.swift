import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct LegalAcceptanceModalView: View {
    let needsTos: Bool
    let needsPrivacy: Bool
    let tosVersion: String?
    let privacyVersion: String?
    let tosMessage: String?
    let privacyMessage: String?
    let onAccept: (String?, String?) async -> Result<Void, Error>
    let onSignOut: () async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isChecked = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSignOutConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.large) {
                // Header
                VStack(spacing: BrandSpacing.small) {
                    Text("📜")
                        .font(.system(size: 48))
                    Text("Terms Update Required")
                        .font(.adaptiveSystem(size: 24, weight: .bold))
                        .foregroundStyle(titleColor)
                }
                .padding(.top, BrandSpacing.large)

                // Document Cards
                VStack(spacing: BrandSpacing.medium) {
                    if needsTos, let version = tosVersion {
                        DocumentCard(
                            title: "Terms of Service",
                            version: version,
                            message: tosMessage,
                            url: AppConfiguration.termsAndConditionsURL
                        )
                    }

                    if needsPrivacy, let version = privacyVersion {
                        DocumentCard(
                            title: "Privacy Policy",
                            version: version,
                            message: privacyMessage,
                            url: AppConfiguration.privacyPolicyURL
                        )
                    }
                }

                // Checkbox
                Toggle(isOn: $isChecked) {
                    Text(checkboxText)
                        .font(.adaptiveSystem(size: 14, weight: .medium))
                        .foregroundStyle(bodyColor)
                }
                .toggleStyle(SwitchToggleStyle(tint: primaryColor))
                .disabled(isSubmitting)

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.adaptiveSystem(size: 14, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                }

                // Accept button
                BrandPrimaryButton(
                    title: isSubmitting ? "Accepting..." : "Accept and Continue",
                    isLoading: isSubmitting
                ) {
                    Task { await handleAccept() }
                }
                .disabled(!isChecked || isSubmitting)

                // Sign Out button
                Button("Sign Out") {
                    showSignOutConfirmation = true
                }
                .font(.adaptiveSystem(size: 16, weight: .medium))
                .foregroundStyle(bodyColor.opacity(0.7))
                .disabled(isSubmitting)

                Spacer(minLength: BrandSpacing.large)
            }
            .padding(.horizontal, BrandSpacing.large)
        }
        .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)
        .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task { await onSignOut() }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    private var checkboxText: String {
        if needsTos && needsPrivacy {
            return "I have read and agree to the updated Terms of Service and Privacy Policy"
        } else if needsTos {
            return "I have read and agree to the updated Terms of Service"
        } else {
            return "I have read and agree to the updated Privacy Policy"
        }
    }

    private func handleAccept() async {
        await MainActor.run {
            isSubmitting = true
            errorMessage = nil
        }

        let tosToAccept = needsTos ? tosVersion : nil
        let privacyToAccept = needsPrivacy ? privacyVersion : nil

        print("[LegalAcceptance] Starting accept - tosVersion=\(tosToAccept ?? "nil"), privacyVersion=\(privacyToAccept ?? "nil")")

        // Retry up to 3 times
        var lastError: Error?
        for attempt in 1...3 {
            print("[LegalAcceptance] Attempt \(attempt)/3")
            let result = await onAccept(tosToAccept, privacyToAccept)
            switch result {
            case .success:
                print("[LegalAcceptance] Success on attempt \(attempt)")
                return // Success - view will be dismissed by parent
            case .failure(let error):
                print("[LegalAcceptance] Attempt \(attempt) failed: \(error)")
                lastError = error
                if attempt < 3 {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        // All attempts failed
        print("[LegalAcceptance] All attempts failed. Last error: \(String(describing: lastError))")
        await MainActor.run {
            isSubmitting = false
            errorMessage = "Network error. Please check your connection and try again."
        }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var primaryColor: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }
}

// MARK: - Document Card

private struct DocumentCard: View {
    let title: String
    let version: String
    let message: String?
    let url: URL

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.small) {
            HStack {
                Text("\(title) v\(version)")
                    .font(.adaptiveSystem(size: 16, weight: .semibold))
                    .foregroundStyle(titleColor)
                Spacer()
            }

            if let message, !message.isEmpty {
                Text(message)
                    .font(.adaptiveSystem(size: 14))
                    .foregroundStyle(bodyColor)
            }

            Button {
                openURL(url)
            } label: {
                HStack(spacing: 4) {
                    Text("View Full Document")
                        .font(.adaptiveSystem(size: 14, weight: .medium))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(primaryColor)
            }
        }
        .padding(BrandSpacing.medium)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var primaryColor: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
}
