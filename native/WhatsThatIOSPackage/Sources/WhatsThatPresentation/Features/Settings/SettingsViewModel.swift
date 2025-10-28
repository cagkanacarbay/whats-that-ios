import Foundation
import SwiftUI
import WhatsThatDomain

@MainActor
final class SettingsViewModel: ObservableObject {
    enum AlertState: Equatable, Identifiable {
        case confirmReset
        case confirmSignOut
        case finished
        case appStoreCleared
        case error(String)
        case passwordResetSent(email: String)

        var id: String {
            switch self {
            case .confirmReset:
                return "confirm-reset"
            case .confirmSignOut:
                return "confirm-sign-out"
            case .finished:
                return "finished"
            case .appStoreCleared:
                return "appstore-cleared"
            case .error(let message):
                return "error_\(message)"
            case .passwordResetSent(let email):
                return "password-reset_\(email)"
            }
        }
    }

    @Published var isProcessing = false
    @Published var isSigningOut = false
    @Published var isLoadingCredits = false
    @Published var isClearingAppStore = false
    @Published var isRequestingPasswordReset = false
    @Published var creditBalance: Int?
    @Published var alertState: AlertState?
    let canRequestPasswordReset: Bool
    let userEmail: String?

    private let onResetOnboarding: () async -> Result<Void, Error>
    private let onFetchCreditBalance: () async -> Result<Int, Error>
    private let onSendPasswordReset: (String) async -> Result<Void, AuthError>
    private let onSignOut: () async -> Result<Void, Error>
    private let onClearAppStoreAccount: () async -> Result<Void, Error>
    private let onClose: () -> Void

    init(
        userEmail: String?,
        canRequestPasswordReset: Bool,
        onResetOnboarding: @escaping () async -> Result<Void, Error>,
        onFetchCreditBalance: @escaping () async -> Result<Int, Error>,
        onSendPasswordReset: @escaping (String) async -> Result<Void, AuthError>,
        onSignOut: @escaping () async -> Result<Void, Error>,
        onClearAppStoreAccount: @escaping () async -> Result<Void, Error>,
        onClose: @escaping () -> Void
    ) {
        self.userEmail = userEmail
        self.canRequestPasswordReset = canRequestPasswordReset
        self.onResetOnboarding = onResetOnboarding
        self.onFetchCreditBalance = onFetchCreditBalance
        self.onSendPasswordReset = onSendPasswordReset
        self.onSignOut = onSignOut
        self.onClearAppStoreAccount = onClearAppStoreAccount
        self.onClose = onClose
    }

    func presentResetConfirmation() {
        alertState = .confirmReset
    }

    func presentSignOutConfirmation() {
        alertState = .confirmSignOut
    }

    func dismissAlert() {
        alertState = nil
    }

    func refreshCreditBalance() async {
        guard !isLoadingCredits else { return }
        isLoadingCredits = true

        let result = await onFetchCreditBalance()

        isLoadingCredits = false
        switch result {
        case .success(let balance):
            creditBalance = balance
        case .failure(let error):
            alertState = .error(error.localizedDescription)
            creditBalance = nil
        }
    }

    func updateCreditBalance(_ newBalance: Int?) {
        creditBalance = newBalance
    }

    func performReset() async {
        guard !isProcessing else { return }
        isProcessing = true
        alertState = nil

        let result = await onResetOnboarding()

        isProcessing = false
        switch result {
        case .success:
            alertState = .finished
        case .failure(let error):
            alertState = .error(error.localizedDescription)
        }
    }

    func performSignOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        alertState = nil

        let result = await onSignOut()

        isSigningOut = false
        switch result {
        case .success:
            onClose()
        case .failure(let error):
            alertState = .error(error.localizedDescription)
        }
    }

    func performPasswordReset() async {
        guard canRequestPasswordReset else {
            alertState = .error("Password reset isn't available for this account.")
            return
        }

        guard !isRequestingPasswordReset else { return }

        guard let email = userEmail, email.isEmpty == false else {
            alertState = .error("We couldn't find your email address for this account.")
            return
        }

        isRequestingPasswordReset = true
        alertState = nil

        let result = await onSendPasswordReset(email)

        isRequestingPasswordReset = false
        switch result {
        case .success:
            alertState = .passwordResetSent(email: email)
        case .failure(let error):
            let message = error.errorDescription ?? AuthError.passwordResetFailed.errorDescription ?? "Something went wrong."
            alertState = .error(message)
        }
    }

    func clearAppStoreAccount() async {
        guard !isClearingAppStore else { return }
        isClearingAppStore = true
        alertState = nil

        let result = await onClearAppStoreAccount()

        isClearingAppStore = false
        switch result {
        case .success:
            alertState = .appStoreCleared
        case .failure(let error):
            alertState = .error(error.localizedDescription)
        }
    }
}
