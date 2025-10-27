import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared

struct DiscoveryCreationFlowView: View {
    @ObservedObject private var viewModel: DiscoveryCreationFlowViewModel
    let placeholderEmoji: String
    let ctaTitle: String
    let retryTitle: String
    private let makeCreditsViewModel: (() -> CreditsViewModel)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isCreditsPresented = false
    @State private var presentedCreditsViewModel: CreditsViewModel?
    @State private var creditsSheetDetent: PresentationDetent = .fraction(0.8)

    init(
        viewModel: DiscoveryCreationFlowViewModel,
        placeholderEmoji: String,
        ctaTitle: String,
        retryTitle: String,
        makeCreditsViewModel: (() -> CreditsViewModel)? = nil
    ) {
        _viewModel = ObservedObject(initialValue: viewModel)
        self.placeholderEmoji = placeholderEmoji
        self.ctaTitle = ctaTitle
        self.retryTitle = retryTitle
        self.makeCreditsViewModel = makeCreditsViewModel
    }

    private var palette: DiscoveryCreationPalette {
        DiscoveryCreationPalette.resolve(for: colorScheme)
    }

    var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(palette.background.ignoresSafeArea())
            .alert(
                item: Binding(
                    get: { viewModel.error.map(IdentifiedError.init) },
                    set: { _ in viewModel.clearError() }
                )
            ) { identifiedError in
                alert(for: identifiedError.error)
            }
            .sheet(isPresented: $isCreditsPresented, onDismiss: {
                presentedCreditsViewModel = nil
                creditsSheetDetent = .fraction(0.8)
            }) {
                NavigationStack {
                    if let creditsViewModel = ensureCreditsViewModel() {
                        CreditsView(viewModel: creditsViewModel)
                    } else {
                        Text("Credits unavailable")
                            .font(.headline)
                            .padding()
                    }
                }
                .presentationDetents([.fraction(0.8), .large], selection: $creditsSheetDetent)
                .presentationDragIndicator(.visible)
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
                onRequestCredits: makeCreditsHandler
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
            onCancel: { viewModel.cancelFlow() }
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
        guard ensureCreditsViewModel() != nil else { return }
        creditsSheetDetent = .fraction(0.8)
        isCreditsPresented = true
    }

    @MainActor
    @discardableResult
    private func ensureCreditsViewModel() -> CreditsViewModel? {
        if let existing = presentedCreditsViewModel {
            return existing
        }
        guard let factory = makeCreditsViewModel else { return nil }
        let creditsViewModel = factory()
        let flowViewModel = viewModel
        creditsViewModel.onBalanceUpdated = { newBalance in
            Task { [weak flowViewModel] in
                await flowViewModel?.syncCreditBalance(newBalance)
            }
        }
        presentedCreditsViewModel = creditsViewModel
        return creditsViewModel
    }

    private func alert(for error: DiscoveryCreationFlowViewModel.FlowError) -> Alert {
        switch error {
        case .permissionDenied:
            return Alert(
                title: Text("Permission Needed"),
                message: Text(error.localizedDescription),
                primaryButton: .default(Text("Open Settings"), action: openAppSettings),
                secondaryButton: .cancel(Text("Not Now"))
            )
        default:
            return Alert(
                title: Text("Oops"),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
