import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    enum AlertState: Equatable, Identifiable {
        case confirmReset
        case confirmSignOut
        case finished
        case error(String)

        var id: String {
            switch self {
            case .confirmReset:
                return "confirm-reset"
            case .confirmSignOut:
                return "confirm-sign-out"
            case .finished:
                return "finished"
            case .error(let message):
                return "error_\(message)"
            }
        }
    }

    @Published var isProcessing = false
    @Published var isSigningOut = false
    @Published var isLoadingCredits = false
    @Published var creditBalance: Int?
    @Published var alertState: AlertState?

    private let onResetOnboarding: () async -> Result<Void, Error>
    private let onFetchCreditBalance: () async -> Result<Int, Error>
    private let onSignOut: () async -> Result<Void, Error>
    private let onClose: () -> Void

    init(
        onResetOnboarding: @escaping () async -> Result<Void, Error>,
        onFetchCreditBalance: @escaping () async -> Result<Int, Error>,
        onSignOut: @escaping () async -> Result<Void, Error>,
        onClose: @escaping () -> Void
    ) {
        self.onResetOnboarding = onResetOnboarding
        self.onFetchCreditBalance = onFetchCreditBalance
        self.onSignOut = onSignOut
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
}
