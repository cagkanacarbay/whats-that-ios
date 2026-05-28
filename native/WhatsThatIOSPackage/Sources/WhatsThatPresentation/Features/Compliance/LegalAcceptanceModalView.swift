import MarkdownUI
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
    @State private var tosChecked = false
    @State private var privacyChecked = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSignOutConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: BrandSpacing.large) {
                    Spacer()
                        .frame(height: BrandSpacing.large)

                    // Header with emoji
                    Text("📜")
                        .font(.system(size: 48))

                    Text("Updated Terms")
                        .font(.adaptiveSystem(size: 24, weight: .bold))
                        .foregroundStyle(titleColor)

                    Text("Please review and accept the updated terms to continue using the app.")
                        .font(.adaptiveSystem(size: 15))
                        .foregroundStyle(bodyColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.small)

                    // Document Cards with toggles
                    VStack(spacing: BrandSpacing.large) {
                        if needsTos, let version = tosVersion {
                            VStack(alignment: .leading, spacing: BrandSpacing.medium) {
                                DocumentCard(
                                    title: "Terms of Service",
                                    version: version,
                                    message: tosMessage,
                                    url: AppConfiguration.termsAndConditionsURL
                                )
                                Toggle(isOn: $tosChecked) {
                                    Text("I have read and agree to the Terms of Service")
                                        .font(.adaptiveSystem(size: 14, weight: .medium))
                                        .foregroundStyle(bodyColor)
                                }
                                .toggleStyle(SwitchToggleStyle(tint: primaryColor))
                                .disabled(isSubmitting)
                            }
                        }

                        if needsPrivacy, let version = privacyVersion {
                            VStack(alignment: .leading, spacing: BrandSpacing.medium) {
                                DocumentCard(
                                    title: "Privacy Policy",
                                    version: version,
                                    message: privacyMessage,
                                    url: AppConfiguration.privacyPolicyURL
                                )
                                Toggle(isOn: $privacyChecked) {
                                    Text("I have read and agree to the Privacy Policy")
                                        .font(.adaptiveSystem(size: 14, weight: .medium))
                                        .foregroundStyle(bodyColor)
                                }
                                .toggleStyle(SwitchToggleStyle(tint: primaryColor))
                                .disabled(isSubmitting)
                            }
                        }
                    }
                    .padding(.top, BrandSpacing.small)

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
                    .disabled(!allRequiredChecked || isSubmitting)
                    .padding(.top, BrandSpacing.small)
                }
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.large)
            }

            // Sign Out button pinned to bottom
            Button("Sign Out") {
                showSignOutConfirmation = true
            }
            .font(.adaptiveSystem(size: 14, weight: .medium))
            .foregroundStyle(bodyColor.opacity(0.5))
            .disabled(isSubmitting)
            .padding(.vertical, BrandSpacing.medium)
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

    private var allRequiredChecked: Bool {
        let tosOk = !needsTos || tosChecked
        let privacyOk = !needsPrivacy || privacyChecked
        return tosOk && privacyOk
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
                Markdown(message)
                    .markdownTheme(complianceTheme)
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

    private var complianceTheme: Theme {
        BrandMarkdownThemeFactory.complianceMessageTheme(for: BrandTheme.palette(for: colorScheme))
    }
}
