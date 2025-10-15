import SwiftUI
import WhatsThatDomain
import WhatsThatShared
#if canImport(UIKit)
import UIKit
#endif

struct DiscoveryCreationFlowView: View {
    enum LayoutConstants {
        static let previewHeight: CGFloat = 320
        static let buttonHeight: CGFloat = 52
    }

    @ObservedObject var viewModel: DiscoveryCreationFlowViewModel
    let placeholderEmoji: String
    let ctaTitle: String
    let retryTitle: String

    var body: some View {
        VStack(spacing: 24) {
            content
        }
        .padding(.horizontal, BrandSpacing.large)
        .padding(.vertical, BrandSpacing.large)
        .alert(item: Binding(
            get: { viewModel.error.map(IdentifiedError.init) },
            set: { _ in viewModel.clearError() }
        )) { identifiedError in
            Alert(title: Text("Oops"), message: Text(identifiedError.error.localizedDescription), dismissButton: .default(Text("OK")))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.flowState {
        case .idle, .cancelled:
            IdleStateView(emoji: placeholderEmoji, title: ctaTitle) {
                viewModel.startFlow()
            }
        case .requestingPermissions, .capturingInitial, .capturingRetake, .selectingInitial, .selectingRetake:
            ProgressStateView()
        case let .error(message):
            ErrorStateView(
                emoji: "⚠️",
                title: "Something went wrong",
                message: message.isEmpty ? "Please try again." : message,
                actionTitle: retryTitle
            ) {
                viewModel.retake()
            }
        case let .confirming(state):
            ConfirmationStateView(state: state, creditBalance: viewModel.creditBalance) {
                viewModel.retake()
            } onContinue: {
                viewModel.beginAnalysis()
            } onCancel: {
                viewModel.cancelFlow()
            }
        case let .analyzing(state):
            AnalysisStateView(state: state)
        }
    }
}

private struct IdleStateView: View {
    let emoji: String
    let title: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(emoji)
                .font(.system(size: 72))
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
            BrandPrimaryButton(title: "Get started", action: action)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProgressStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Preparing…")
                .font(.system(size: 18, weight: .medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorStateView: View {
    let emoji: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(emoji)
                .font(.system(size: 64))
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(message)
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
            BrandPrimaryButton(title: actionTitle, action: action)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ConfirmationStateView: View {
    let state: DiscoveryConfirmationState
    let creditBalance: Int?
    let onRetake: () -> Void
    let onContinue: () -> Void
    let onCancel: () -> Void

    private var image: Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: state.displayImageData) else {
            return nil
        }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }

    private var creditLabel: String {
        if let balance = creditBalance {
            return "Credits: \(balance)"
        }
        return "Credits: —"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: DiscoveryCreationFlowView.LayoutConstants.previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: DiscoveryCreationFlowView.LayoutConstants.previewHeight)
                    .overlay {
                        Text("No preview available")
                            .foregroundStyle(.secondary)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(creditLabel)
                    .font(.system(size: 18, weight: .semibold))
                if let location = state.locationDescription {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button(action: onRetake) {
                    Text("Retake")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: DiscoveryCreationFlowView.LayoutConstants.buttonHeight)
                        .background(Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: DiscoveryCreationFlowView.LayoutConstants.buttonHeight)
                        .background(BrandColors.Light.primaryAction)
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

            Button("Cancel", role: .cancel, action: onCancel)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AnalysisStateView: View {
    let state: DiscoveryAnalysisState

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.circular)
            if let status = state.statusMessage {
                Text(status)
                    .font(.system(size: 18, weight: .medium))
            }
            ScrollView {
                Text(state.streamedText.isEmpty ? "Listening to the world…" : state.streamedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.body, design: .default))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct IdentifiedError: Identifiable {
    let id = UUID()
    let error: DiscoveryCreationFlowViewModel.FlowError
}
