import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared

struct DiscoveryCreationFlowView: View {
    @ObservedObject private var viewModel: DiscoveryCreationFlowViewModel
    let placeholderEmoji: String
    let ctaTitle: String
    let retryTitle: String

    @Environment(\.colorScheme) private var colorScheme

    init(
        viewModel: DiscoveryCreationFlowViewModel,
        placeholderEmoji: String,
        ctaTitle: String,
        retryTitle: String
    ) {
        _viewModel = ObservedObject(initialValue: viewModel)
        self.placeholderEmoji = placeholderEmoji
        self.ctaTitle = ctaTitle
        self.retryTitle = retryTitle
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
                onCancel: { viewModel.cancelFlow() }
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
