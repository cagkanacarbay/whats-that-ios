import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct DiscoveryStreamingLoaderView: View {
    let palette: DiscoveryCreationPalette
    let shouldShowLoader: Bool
    let currentMessage: String
    let previousMessage: String?
    let currentMessageOpacity: Double
    let previousMessageOpacity: Double
    let metadataVisible: Bool
    let state: DiscoveryAnalysisState
    let capturedAt: Date?
    let availableWidth: CGFloat
    let onMessageFinished: () -> Void
    let debugLog: (String) -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            if state.isPolling {
                pollingMessage
            } else if shouldShowLoader {
                loaderMessages
            } else {
                metadataView
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pollingMessage: some View {
        VStack(spacing: BrandSpacing.medium) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: palette.textPrimary))
                .scaleEffect(1.2)
            
            Text(state.statusMessage ?? "Checking for your discovery...")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, BrandSpacing.large)
    }

    private var loaderMessages: some View {
        Group {
            if !currentMessage.isEmpty {
                ZStack {
                    if let previousMessage, previousMessageOpacity > 0 {
                        ShimmerTextView(
                            text: previousMessage,
                            availableWidth: availableWidth,
                            color: palette.textPrimary,
                            isActive: false,
                            logger: debugLog
                        )
                        .opacity(previousMessageOpacity)
                    }

                    ShimmerTextView(
                        text: currentMessage,
                        availableWidth: availableWidth,
                        color: palette.textPrimary,
                        logger: debugLog,
                        onFinished: onMessageFinished
                    )
                    .opacity(currentMessageOpacity)
                }
            }
        }
    }

    private var metadataView: some View {
        VStack(spacing: BrandSpacing.small) {
            if let title = state.metadataTitle, !title.isEmpty {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity)
            }

            if let date = capturedAt {
                Text(date.formatted(.dateTime.month().day().year()))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity)
            }

            if let short = state.metadataShortDescription, !short.isEmpty {
                Text(short)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.large)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(metadataVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: metadataVisible)
    }
}
