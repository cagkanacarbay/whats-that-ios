import Foundation
import SwiftUI
import WhatsThatDomain
import WhatsThatShared
#if canImport(MarkdownUI)
import MarkdownUI
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(MapKit)
import MapKit
#endif

struct DiscoveryCreationFlowView: View {
    enum LayoutConstants {
        static let previewHeight: CGFloat = 320
        static let controlHeight: CGFloat = 56
        static let cornerRadius: CGFloat = 20
    }

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

    var body: some View {
        mainContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundColor.ignoresSafeArea())
        .alert(
            item: Binding(
                get: { viewModel.error.map(IdentifiedError.init) },
                set: { _ in viewModel.clearError() }
            )
        ) { identifiedError in
            Alert(
                title: Text("Oops"),
                message: Text(identifiedError.error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.flowState {
        case .confirming, .analyzing:
            // Full-bleed overlays should not inherit outer padding.
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
        case .analyzing(_):
            makeAnalysisView()
        }
    }

    private var backgroundColor: Color {
        BrandTheme.palette(for: colorScheme).background
    }

    private func makeAnalysisView() -> DiscoveryStreamingStageView {
        DiscoveryStreamingStageView(
            viewModel: viewModel,
            imageData: viewModel.confirmationState?.displayImageData,
            capturedAt: viewModel.confirmationState?.media.createdAt,
            onCancel: { viewModel.cancelFlow() }
        )
    }
}
