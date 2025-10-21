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
            IdleStateView(
                emoji: placeholderEmoji,
                title: ctaTitle,
                action: { viewModel.startFlow() }
            )
        case .requestingPermissions, .capturingInitial, .capturingRetake, .selectingInitial, .selectingRetake:
            ProgressStateView()
        case let .error(message):
            ErrorStateView(
                emoji: "⚠️",
                title: "Something went wrong",
                message: message.isEmpty ? "Please try again." : message,
                actionTitle: retryTitle,
                action: { viewModel.retake() }
            )
        case let .confirming(state):
            ConfirmationStateView(
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

    private func makeAnalysisView() -> AnalysisStateView {
        AnalysisStateView(
            viewModel: viewModel,
            imageData: viewModel.confirmationState?.displayImageData,
            capturedAt: viewModel.confirmationState?.media.createdAt,
            onCancel: { viewModel.cancelFlow() }
        )
    }
}

private struct IdleStateView: View {
    let emoji: String
    let title: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            Text(emoji)
                .font(.system(size: 72))
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
            Text("We’ll guide you from capture to narration in seconds.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            BrandPrimaryButton(title: "Get started", action: action)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProgressStateView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(palette.primaryAction)
            Text("Preparing…")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(palette.textPrimary)
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
        VStack(spacing: BrandSpacing.medium) {
            Text(emoji)
                .font(.system(size: 64))
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(message)
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            BrandPrimaryButton(title: actionTitle, action: action)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ConfirmationStateView: View {
    private enum ActiveAlert: Identifiable {
        case creditInfo(balance: Int)
        case outOfCredits
        case locationPermissions

        var id: String {
            switch self {
            case .creditInfo:
                return "creditInfo"
            case .outOfCredits:
                return "outOfCredits"
            case .locationPermissions:
                return "locationPermissions"
            }
        }
    }

    let state: DiscoveryConfirmationState
    let creditBalance: Int?
    let flowType: DiscoveryCreationFlowType
    let onRetake: () -> Void
    let onContinue: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeAlert: ActiveAlert?

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    private var previewImage: Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: state.displayImageData) else {
            return nil
        }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }

    private var creditDisplayText: String {
        let balanceText = creditBalance.map { String($0) } ?? "…"
        return "Credits: \(balanceText)"
    }

    private var creditTint: Color {
        guard let balance = creditBalance else {
            return palette.overlayButtonForeground.opacity(0.75)
        }
        if balance == 0 {
            return Color(hex: "#E5484D")
        }
        if balance <= 10 {
            return Color(hex: "#F5A524")
        }
        return palette.overlayButtonForeground
    }

    private var continueTitle: String {
        guard let balance = creditBalance, balance == 0 else {
            return "Continue"
        }
        return "Get credits"
    }

    private var continueBackground: Color {
        guard let balance = creditBalance, balance == 0 else {
            return palette.primaryAction
        }
        return Color(hex: "#E5484D")
    }

    private var continueIconName: String {
        if let balance = creditBalance, balance == 0 {
            return "cart"
        }
        return "arrow.right"
    }

    private var isContinueDisabled: Bool {
        creditBalance == 0
    }

    private var retakeTitle: String {
        flowType == .upload ? "Re-upload" : "Retake"
    }

    private var retakeIconName: String {
        flowType == .upload ? "arrow.up.tray" : "arrow.counterclockwise"
    }

    private var hasResolvedLocation: Bool {
        state.location != nil
    }

    private var shouldShowLocationPermissions: Bool {
        flowType == .camera && !state.isLocationPermissionGranted
    }

    private var shouldShowMissingLocation: Bool {
        flowType == .upload && state.location == nil
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            // Overlays already respect the safe area; only add minimal extra breathing room.
            let overlayTopPadding = topInset > 0 ? BrandSpacing.small : BrandSpacing.medium
            let overlayControlHeight: CGFloat = 48
            let previewTopPadding = topInset + overlayTopPadding + overlayControlHeight + BrandSpacing.small

            ZStack {
                palette.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    previewSection(size: proxy.size)
                        .padding(.top, previewTopPadding)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .overlay(alignment: .topLeading) {
                overlayCircleButton(systemName: "xmark", action: onCancel)
                    .padding(.leading, BrandSpacing.large)
                    .padding(.top, overlayTopPadding)
            }
            .overlay(alignment: .topTrailing) {
                topTrailingControl
                    .padding(.trailing, BrandSpacing.large)
                    .padding(.top, overlayTopPadding)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.clear,
                        palette.background.opacity(0.25),
                        palette.background.opacity(0.65),
                        palette.background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.size.height * 0.35)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                bottomOverlay
                    .padding(.horizontal, BrandSpacing.large)
                    .padding(.bottom, BrandSpacing.large * CGFloat(1.1))
                    .frame(maxWidth: proxy.size.width)
            }
        }
        .alert(item: $activeAlert) { alert(for: $0) }
    }

    @ViewBuilder
    private func previewSection(size: CGSize) -> some View {
        let fallbackHeight = max(size.height * 0.62, 320)
        if let image = previewImage {
            image
                .resizable()
                .scaledToFit()
                .frame(width: size.width)
                .clipped()
                .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 16)
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(palette.border.opacity(0.1))
                .frame(width: size.width, height: fallbackHeight)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                        Text("Preview unavailable")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
        }
    }
    @ViewBuilder
    private var topTrailingControl: some View {
        if shouldShowLocationPermissions {
            overlayCapsuleButton(
                title: "No Location Permissions",
                systemName: "location.slash"
            ) {
                activeAlert = .locationPermissions
            }
        } else if hasResolvedLocation {
            overlayCircleButton(systemName: "mappin.and.ellipse") {
                openCurrentLocation()
            }
        } else if shouldShowMissingLocation {
            overlayCapsuleBadge(title: "No location", systemName: "mappin")
        }
    }

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            Button {
                guard let balance = creditBalance else { return }
                if balance == 0 {
                    activeAlert = .outOfCredits
                } else {
                    activeAlert = .creditInfo(balance: balance)
                }
            } label: {
                Text(creditDisplayText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(creditTint)
                    .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(creditBalance == nil)

            HStack(spacing: BrandSpacing.small) {
                Button(action: onRetake) {
                    Label(retakeTitle, systemImage: retakeIconName)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: DiscoveryCreationFlowView.LayoutConstants.controlHeight)
                        .foregroundStyle(palette.overlayButtonForeground)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(palette.secondaryAction)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(palette.overlayButtonBorder, lineWidth: 1)
                }

                Button {
                    if let balance = creditBalance, balance == 0 {
                        activeAlert = .outOfCredits
                        return
                    }
                    onContinue()
                } label: {
                    Label(continueTitle, systemImage: continueIconName)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: DiscoveryCreationFlowView.LayoutConstants.controlHeight)
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(continueBackground)
                )
                .opacity(isContinueDisabled ? 0.45 : 1)
                .disabled(isContinueDisabled)
            }
        }
    }

    private func overlayCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
                .foregroundStyle(palette.overlayButtonForeground)
                .background(
                    Circle()
                        .fill(palette.overlayButtonBackground)
                )
                .overlay {
                    Circle()
                        .stroke(palette.overlayButtonBorder, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(palette.overlayButtonShadowOpacity), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func overlayCapsuleButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(palette.overlayButtonForeground)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(palette.overlayButtonBackground)
            )
            .overlay {
                Capsule()
                    .stroke(palette.overlayButtonBorder, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(palette.overlayButtonShadowOpacity), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func overlayCapsuleBadge(title: String, systemName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(palette.overlayButtonForeground.opacity(0.9))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(palette.overlayButtonBackground)
        )
        .overlay {
            Capsule()
                .stroke(palette.overlayButtonBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(palette.overlayButtonShadowOpacity), radius: 14, x: 0, y: 8)
        .allowsHitTesting(false)
    }

    private func alert(for alert: ActiveAlert) -> Alert {
        switch alert {
        case let .creditInfo(balance):
            return Alert(
                title: Text("Credit information"),
                message: Text("Each discovery costs 1 credit. You have \(balance)."),
                dismissButton: .default(Text("OK"))
            )
        case .outOfCredits:
            return Alert(
                title: Text("Out of credits"),
                message: Text("Each discovery costs 1 credit. Purchase more to continue."),
                dismissButton: .default(Text("OK"))
            )
        case .locationPermissions:
            return Alert(
                title: Text("Grant Location Permissions"),
                message: Text("Enable location access in Settings to improve analysis accuracy."),
                primaryButton: .default(Text("Open Settings"), action: openSettings),
                secondaryButton: .cancel()
            )
        }
    }

    private func openSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #endif
    }

    private func openCurrentLocation() {
        #if canImport(MapKit)
        guard let location = state.location else { return }
        let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = state.locationDescription ?? "Discovery location"
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
        #endif
    }
}

private struct AnalysisStateView: View {
    @ObservedObject private var viewModel: DiscoveryCreationFlowViewModel
    let imageData: Data?
    let capturedAt: Date?
    let onCancel: () -> Void

    init(
        viewModel: DiscoveryCreationFlowViewModel,
        imageData: Data?,
        capturedAt: Date?,
        onCancel: @escaping () -> Void
    ) {
        self._viewModel = ObservedObject(initialValue: viewModel)
        self.imageData = imageData
        self.capturedAt = capturedAt
        self.onCancel = onCancel
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var displayedMarkdown: String = ""
    @State private var loaderCleared: Bool = false
    @State private var shuffledMessages: [String] = AnalysisStateView.loadingMessages.shuffled()
    @State private var currentMessageIndex: Int = 0
    @State private var markdownAnimationTask: Task<Void, Never>?
    // For smooth crossfade between loader messages
    @State private var previousMessage: String? = nil
    @State private var previousMessageOpacity: Double = 0
    @State private var currentMessageOpacity: Double = 1
    @State private var metadataVisible: Bool = false
    @State private var hasScrolledToContent = false

    private enum Layout {
        static let headerHeightFactor: CGFloat = 0.72
        static let minimumHeaderHeight: CGFloat = 360
        static let minimumHeaderWidth: CGFloat = 320
    }

    private enum AnimationConstants {
        static let minimumCharacterDelay: Double = 0.002
        static let maximumCharacterDelay: Double = 0.02
        static let speedMultiplier: Double = 1.0 / 3.0
        static let minimumAcceleratedDelay = minimumCharacterDelay * speedMultiplier
    }

    #if DEBUG
    private let debugLoggingEnabled = true
    #else
    private let debugLoggingEnabled = false
    #endif

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    // Read the current analysis state from the view model to allow streaming updates
    private var state: DiscoveryAnalysisState {
        viewModel.analysisState ?? DiscoveryAnalysisState()
    }

    private var previewImage: Image? {
        #if canImport(UIKit)
        guard
            let data = imageData,
            let uiImage = UIImage(data: data)
        else {
            return nil
        }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }

    private var currentLoadingMessage: String {
        guard !shuffledMessages.isEmpty else { return "" }
        let index = min(currentMessageIndex, shuffledMessages.count - 1)
        return shuffledMessages[index]
    }

    private var currentMarkdown: String {
        // Prefer already-formatted markdown if present, otherwise derive
        // narrative from streamed text while stripping metadata JSON.
        let trimmed = state.displayMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return DiscoveryStreamFormatter.narrative(from: state.streamedText)
    }

    private var shouldShowLoader: Bool {
        !loaderCleared
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Match DiscoveryHero overlay behavior: place a placeholder
                        // header inside the scroll content and overlay the image onto it
                        // so the entire page (including the image) scrolls together.
                        // Reserve only the visible header height. The image is drawn
                        // in a top overlay and already extends into the safe area.
                        let reservedHeight = max(proxy.size.height * Layout.headerHeightFactor, Layout.minimumHeaderHeight)
                        let safeTop = proxy.safeAreaInsets.top
                        let headerWidth = max(proxy.size.width, Layout.minimumHeaderWidth)
                        Color.clear
                            .frame(height: reservedHeight)
                            // Layer image first so it remains stable
                            .overlay(
                                headerImageSection(size: proxy.size, safeTop: safeTop)
                                    .ignoresSafeArea(edges: .top)
                                    .compositingGroup(),
                                alignment: .bottom
                            )
                            // Then overlay the text/loader in its own compositing group
                            .overlay(
                                headerOverlayContent(width: headerWidth)
                                    .padding(.horizontal, BrandSpacing.large)
                                    .padding(.bottom, BrandSpacing.large * CGFloat(1.2))
                                    .compositingGroup(),
                                alignment: .bottom
                            )

                        markdownSection
                            .id(ScrollTarget.markdown)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Image/header drawn inside content overlay, so the whole page scrolls.
                .background(palette.background.ignoresSafeArea())
                .onAppear {
                    resetStateForInitialRender()
                    if loaderCleared {
                        DispatchQueue.main.async {
                            scrollToContent(using: scrollProxy, animated: false)
                        }
                    }
                }
                .onDisappear {
                    markdownAnimationTask?.cancel()
                }
                .overlay(alignment: .topLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .foregroundStyle(palette.overlayButtonForeground)
                            .background(
                                Circle()
                                    .fill(palette.overlayButtonBackground)
                            )
                            .overlay {
                                Circle()
                                    .stroke(palette.overlayButtonBorder, lineWidth: 1)
                            }
                            .shadow(color: Color.black.opacity(0.25), radius: 14, x: 0, y: 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, BrandSpacing.large)
                    .padding(.top, BrandSpacing.xLarge)
                }
                .onChange(of: state.displayMarkdown) {
                    updateDisplayedMarkdown()
                }
                .onChange(of: currentMessageIndex) { newIndex in
                    let currentOpacityFormatted = String(format: "%.2f", currentMessageOpacity)
                    let previousOpacityFormatted = String(format: "%.2f", previousMessageOpacity)
                    debugLog(
                        "loaderMessageIndex -> \(newIndex) message=\"\(currentLoadingMessage)\" prev=\"\(previousMessage ?? "nil")\" currentOpacity=\(currentOpacityFormatted) previousOpacity=\(previousOpacityFormatted)"
                    )
                }
                .onChange(of: currentMessageOpacity) { newValue in
                    let formatted = String(format: "%.2f", newValue)
                    debugLog("currentMessageOpacity changed -> \(formatted) message=\"\(currentLoadingMessage)\"")
                }
                .onChange(of: previousMessageOpacity) { newValue in
                    let formatted = String(format: "%.2f", newValue)
                    debugLog("previousMessageOpacity changed -> \(formatted) previous=\"\(previousMessage ?? "nil")\"")
                }
                .onChange(of: state.streamedText) {
                    // Throttle noisy updates: only consider stream text for clearing
                    // the loader if we still have no metadata and the loader is visible.
                    guard !loaderCleared,
                          (state.metadataTitle?.isEmpty ?? true) && (state.metadataShortDescription?.isEmpty ?? true)
                    else { return }
                    evaluateLoaderCleared(with: currentMarkdown)
                }
                .onChange(of: state.metadataTitle) {
                    evaluateMetadataVisibility()
                    evaluateLoaderCleared(with: displayedMarkdown)
                }
                .onChange(of: state.metadataShortDescription) {
                    evaluateMetadataVisibility()
                    evaluateLoaderCleared(with: displayedMarkdown)
                }
                .onChange(of: state.isStreaming) {
                    if !state.isStreaming {
                        // Streaming ended: snap to final text (no animation) to avoid cut-offs
                        markdownAnimationTask?.cancel()
                        let final = currentMarkdown
                        displayedMarkdown = final
                        evaluateLoaderCleared(with: final)
                        loaderCleared = true
                    }
                }
                .onChange(of: loaderCleared) {
                    debugLog("loaderCleared changed -> \(loaderCleared)")
                    if loaderCleared {
                        scrollToContent(using: scrollProxy)
                        let hasMetadata = (state.metadataTitle?.isEmpty == false) || (state.metadataShortDescription?.isEmpty == false)
                        if hasMetadata && !metadataVisible {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                metadataVisible = true
                            }
                        }
                    } else {
                        hasScrolledToContent = false
                    }
                }
            }
        }
    }

    private func resetStateForInitialRender() {
        shuffledMessages = AnalysisStateView.loadingMessages.shuffled()
        currentMessageIndex = 0
        previousMessage = nil
        previousMessageOpacity = 0
        currentMessageOpacity = 1
        metadataVisible = (state.metadataTitle?.isEmpty == false) || (state.metadataShortDescription?.isEmpty == false)
        let initialNarrative = currentMarkdown
        displayedMarkdown = initialNarrative
        loaderCleared = loaderShouldBeCleared(for: initialNarrative)
        hasScrolledToContent = false
        debugLog("resetState loaderCleared=\(loaderCleared) initialMarkdownLength=\(initialNarrative.count) metadataTitle=\(state.metadataTitle ?? "nil")")
    }

    private func updateDisplayedMarkdown() {
        let newValue = currentMarkdown
        guard newValue != displayedMarkdown else {
            evaluateLoaderCleared(with: newValue)
            return
        }
        animateMarkdown(to: newValue)
    }

    private func animateMarkdown(to target: String) {
        markdownAnimationTask?.cancel()
        let current = displayedMarkdown

        // If the change is very small, just apply it instantly.
        if target.count <= current.count + 2 {
            displayedMarkdown = target
            evaluateLoaderCleared(with: target)
            return
        }

        let delta = target.dropFirst(current.count)
        let deltaCount = delta.count

        // Stream quickly in smooth chunks to avoid flicker and long waits.
        // Aim to reveal a typical sentence (< ~120 chars) in ~0.35–0.5s.
        let targetDuration: Double = 0.42
        let minDelay: Double = 0.016   // ~60 FPS lower bound
        let maxDelay: Double = 0.06
        let steps = max(3, min(12, (deltaCount + 23) / 24))
        let chunkSize = max(1, deltaCount / steps)
        let stepDelay = max(minDelay, min(maxDelay, targetDuration / Double(steps)))
        let delayNs = UInt64(stepDelay * 1_000_000_000)

        markdownAnimationTask = Task {
            var buffer = current
            var idx = delta.startIndex
            while idx < delta.endIndex {
                if Task.isCancelled { return }
                let nextIdx = delta.index(idx, offsetBy: chunkSize, limitedBy: delta.endIndex) ?? delta.endIndex
                buffer.append(contentsOf: delta[idx..<nextIdx])
                idx = nextIdx
                await MainActor.run {
                    displayedMarkdown = buffer
                    evaluateLoaderCleared(with: buffer)
                }
                if idx < delta.endIndex {
                    try? await Task.sleep(nanoseconds: delayNs)
                }
            }
        }
    }

    private func loaderShouldBeCleared(for text: String) -> Bool {
        // End loading as soon as actual streamed narrative content is visible,
        // or metadata is present. Do not wait for the stream to finish.
        if let title = state.metadataTitle, !title.isEmpty {
            debugLog("loaderShouldBeCleared -> true (metadataTitle=\"\(title)\")")
            return true
        }
        if let short = state.metadataShortDescription, !short.isEmpty {
            debugLog("loaderShouldBeCleared -> true (metadataShortDescription length=\(short.count))")
            return true
        }
        let visibleLength = DiscoveryStreamFormatter.visibleLength(for: state.streamedText)
        if visibleLength > 0 {
            debugLog("loaderShouldBeCleared -> true (visibleStreamLength=\(visibleLength))")
            return true
        }
        debugLog("loaderShouldBeCleared -> false (textLength=\(text.count))")
        return false
    }

    private func evaluateLoaderCleared(with text: String) {
        if loaderCleared {
            return
        }
        if loaderShouldBeCleared(for: text) {
            loaderCleared = true
            debugLog("loaderCleared = true (textLength=\(text.count), isStreaming=\(state.isStreaming), title=\(state.metadataTitle ?? "nil"))")
        }
    }

    private func evaluateMetadataVisibility() {
        let hasMetadata = (state.metadataTitle?.isEmpty == false) || (state.metadataShortDescription?.isEmpty == false)
        if hasMetadata && !metadataVisible {
            if loaderCleared {
                withAnimation(.easeInOut(duration: 0.25)) {
                    metadataVisible = true
                }
                debugLog("metadataVisible = true (title=\(state.metadataTitle ?? "nil"), shortLen=\(state.metadataShortDescription?.count ?? 0))")
            } else {
                // Wait to animate title/short until the loader clears so it matches the description reveal.
            }
        } else if !hasMetadata && metadataVisible && state.isStreaming {
            metadataVisible = false
            debugLog("metadataVisible = false (awaiting metadata)")
        }
    }

    // Rotation handled by ShimmerTextView's onFinished callback.

    private func animationDelay(for count: Int) -> UInt64 {
        // Legacy per-character delay (kept for reference). Not used by the chunked animator.
        let characters = max(1, count)
        let baseDelay = min(0.02, max(0.002, 0.3 / Double(characters)))
        return UInt64(baseDelay * 1_000_000_000)
    }

    private func scrollToContent(using proxy: ScrollViewProxy, animated: Bool = true) {
        guard !hasScrolledToContent else { return }
        hasScrolledToContent = true
        let action = {
            proxy.scrollTo(ScrollTarget.markdown, anchor: .top)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.45)) {
                action()
            }
        } else {
            action()
        }
    }

    @ViewBuilder
    private func headerImageSection(size: CGSize, safeTop: CGFloat) -> some View {
        // Full-bleed image header with gradient/title overlay.
        let height = max(size.height * Layout.headerHeightFactor, Layout.minimumHeaderHeight)
        let width = max(size.width, Layout.minimumHeaderWidth)
        ZStack(alignment: .bottom) {
            if let image = previewImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height + safeTop)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [
                        Color(hex: "#20293A"),
                        Color(hex: "#141927")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: width, height: height + safeTop)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                            Text("Image preview unavailable")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
            }

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.clear, location: 0.0),
                    .init(color: palette.overlayMidtone, location: 0.7),
                    .init(color: palette.background, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: width, height: height + safeTop)
            .allowsHitTesting(false)
        }
        .frame(width: width, height: height + safeTop)
        .clipped()
    }

    private func headerOverlayContent(width: CGFloat) -> some View {
        let availableWidth = max(width - (BrandSpacing.large * 2), 0)
        return VStack(spacing: BrandSpacing.medium) {
            if shouldShowLoader {
                if !currentLoadingMessage.isEmpty {
                    ZStack {
                        if let prev = previousMessage, previousMessageOpacity > 0 {
                            ShimmerTextView(
                                text: prev,
                                availableWidth: availableWidth,
                                color: palette.textPrimary,
                                isActive: false,
                                logger: { debugLog($0) }
                            )
                            .opacity(previousMessageOpacity)
                        }

                        ShimmerTextView(
                            text: currentLoadingMessage,
                            availableWidth: availableWidth,
                            color: palette.textPrimary,
                            logger: { debugLog($0) },
                            onFinished: { advanceMessage() }
                        )
                        .opacity(currentMessageOpacity)
                    }
                }

            } else {
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
        .frame(maxWidth: .infinity)
    }

    private func advanceMessage() {
        guard shouldShowLoader else {
            debugLog("advanceMessage skipped (loader already cleared)")
            return
        }
        guard !shuffledMessages.isEmpty else {
            debugLog("advanceMessage skipped (no shuffled messages)")
            return
        }

        // Prepare crossfade: show previous message beneath and fade it out while the new fades in
        let old = currentLoadingMessage
        previousMessage = old
        previousMessageOpacity = 1
        currentMessageOpacity = 0
        debugLog("advanceMessage preparing crossfade from \"\(old)\" (index=\(currentMessageIndex))")

        // Compute next index and add a brief dwell before crossfading
        let nextIndex = (currentMessageIndex + 1) % shuffledMessages.count
        let upcomingMessage = shuffledMessages[nextIndex]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            debugLog("advanceMessage switching to index \(nextIndex) message=\"\(upcomingMessage)\"")
            currentMessageIndex = nextIndex
            withAnimation(.easeInOut(duration: 0.28)) {
                previousMessageOpacity = 0
                currentMessageOpacity = 1
            }
            let currentOpacityFormatted = String(format: "%.2f", currentMessageOpacity)
            let previousOpacityFormatted = String(format: "%.2f", previousMessageOpacity)
            debugLog(
                "advanceMessage crossfade applied currentOpacity=\(currentOpacityFormatted) previousOpacity=\(previousOpacityFormatted) loaderCleared=\(loaderCleared)"
            )
        }
    }

    @ViewBuilder
    private var markdownSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            if shouldShowLoader {
                if !state.isStreaming {
                    Text("Analysis complete.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
            } else if !displayedMarkdown.isEmpty {
                #if canImport(MarkdownUI)
                Markdown(displayedMarkdown)
                    .markdownTheme(BrandMarkdownThemeFactory.discoveryDetailTheme(for: palette))
                #else
                Text(displayedMarkdown)
                    .font(.system(size: 16))
                    .foregroundStyle(palette.textSecondary)
                #endif
            } // else: show nothing until the first markdown chunk lands
        }
        .padding(.top, BrandSpacing.large)
        .padding(.horizontal, BrandSpacing.large)
        .padding(.bottom, BrandSpacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let loadingMessages: [String] = [
        "Identifying landmarks…",
        "Admiring nature…",
        "Looking for leprechauns…",
        "Analyzing architecture…",
        "Uncovering hidden history…",
        "Spotting local wildlife…",
        "Decoding ancient symbols…",
        "Consulting travel guides…",
        "Tracking bigfoot sightings…",
        "Translating squirrel chatter…"
    ]

    private static let streamRevealThreshold: Int = 12
    private static let streamContentThreshold: Int = 40

    private enum ScrollTarget {
        static let markdown = "analysisMarkdown"
    }

    private func makeShareAction(for discovery: DiscoverySummary) -> (() -> Void)? {
        guard let shareURL = shareURL(for: discovery) else { return nil }
        return {
            presentShareSheet(for: discovery, url: shareURL)
        }
    }

    private func shareURL(for discovery: DiscoverySummary) -> URL? {
        if let token = discovery.shareToken {
            return URL(string: "https://whats-that.app/\(token.uuidString)")
        }

        if let path = discovery.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           let url = URL(string: path) {
            return url
        }

        return nil
    }

    private func debugLog(_ message: String) {
        guard debugLoggingEnabled else { return }
        print("[AnalysisStateView] \(message)")
    }

    private func presentShareSheet(for discovery: DiscoverySummary, url: URL) {
        #if canImport(UIKit)
        let message = [
            discovery.title,
            discovery.shortDescription ?? discovery.highlight
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")

        let items: [Any] = message.isEmpty ? [url] : [message, url]
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)

        guard let root = keyWindowRootViewController() else { return }
        DispatchQueue.main.async {
            root.present(controller, animated: true)
        }
        #endif
    }

    #if canImport(UIKit)
    private func keyWindowRootViewController() -> UIViewController? {
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    }
    #endif
}

private struct ShimmerTextView: View {
    let text: String
    let availableWidth: CGFloat
    let color: Color
    let isActive: Bool
    var logger: ((String) -> Void)? = nil
    var onFinished: (() -> Void)? = nil
    
    init(
        text: String,
        availableWidth: CGFloat,
        color: Color,
        isActive: Bool = true,
        logger: ((String) -> Void)? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        self.text = text
        self.availableWidth = availableWidth
        self.color = color
        self.isActive = isActive
        self.logger = logger
        self.onFinished = onFinished
    }

    // Tunables
    private let fontSize: CGFloat = 30
    private let passDuration: Double = 2.0  // seconds for one shimmer pass (slower)
    private let highlightWidthRatio: CGFloat = 0.22 // fraction of availableWidth

    @Environment(\.colorScheme) private var colorScheme
    @State private var notified = false

    @State private var progress: CGFloat = 0
    @State private var lastAnimatedText: String = ""

    var body: some View {
        Group {
            if isActive {
                shimmeringBody
            } else {
                staticBody
            }
        }
    }

    private var shimmeringBody: some View {
        let scale = scaleFactor(for: availableWidth)
        let width = max(availableWidth, 1)
        let stripeWidth = max(60, min(width * highlightWidthRatio, 160))
        let travel = width + stripeWidth
        let xOffset = -stripeWidth/2 + Double(progress) * travel - (travel - width)/2

        let highlight = (colorScheme == .dark) ? Color.white.opacity(0.9) : Color.white
        return ShimmerFrameView(
            text: text,
            color: color,
            highlightColor: highlight,
            fontSize: fontSize,
            scale: scale,
            stripeWidth: stripeWidth,
            xOffset: xOffset
        )
        .compositingGroup()
        .onAppear {
            triggerShimmerIfNeeded(for: text)
        }
        .onChange(of: text) { newValue in
            triggerShimmerIfNeeded(for: newValue)
        }
    }

    private var staticBody: some View {
        let scale = scaleFactor(for: availableWidth)
        return Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .scaleEffect(scale, anchor: .center)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    private func triggerShimmerIfNeeded(for newText: String) {
        guard isActive else { return }
        guard lastAnimatedText != newText else {
            log("startShimmer skipped text=\"\(newText)\" (unchanged)")
            return
        }
        lastAnimatedText = newText
        log("startShimmer text=\"\(newText)\" availableWidth=\(availableWidth)")
        startShimmerAnimation()
    }

    private func startShimmerAnimation() {
        notified = false
        progress = 0
        withAnimation(.linear(duration: passDuration)) {
            progress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + passDuration) {
            if !notified {
                notified = true
                log("shimmerCompleted text=\"\(text)\" notifying=true")
                onFinished?()
            } else {
                log("shimmerCompleted text=\"\(text)\" notifying=false (already notified)")
            }
        }
    }

    private func log(_ message: String) {
        guard let logger else { return }
        logger("[ShimmerTextView] \(message)")
    }

    private func baseText() -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(color.opacity(0.65))
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    private func shimmerOverlay(stripeWidth: CGFloat, xOffset: CGFloat) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(color)
            .mask(ShimmerStripe(width: stripeWidth, height: fontSize * 1.6, xOffset: xOffset))
            .blendMode(.screen)
    }

    private struct ShimmerStripe: View {
        let width: CGFloat
        let height: CGFloat
        let xOffset: CGFloat

        var body: some View {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .white.opacity(0.1), location: 0.3),
                    .init(color: .white, location: 0.5),
                    .init(color: .white.opacity(0.1), location: 0.7),
                    .init(color: .clear, location: 1.0)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width, height: height)
            .offset(x: xOffset)
        }
    }

    private struct ShimmerFrameView: View {
        let text: String
        let color: Color
        let highlightColor: Color
        let fontSize: CGFloat
        let scale: CGFloat
        let stripeWidth: CGFloat
        let xOffset: CGFloat

        var body: some View {
            ZStack {
                Text(text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .allowsHitTesting(false)

                Text(text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(highlightColor)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white.opacity(0.12), location: 0.32),
                                .init(color: .white, location: 0.5),
                                .init(color: .white.opacity(0.12), location: 0.68),
                                .init(color: .clear, location: 1.0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: stripeWidth, height: fontSize * 1.6)
                        .offset(x: xOffset)
                    )
                    .allowsHitTesting(false)
            }
            .scaleEffect(scale, anchor: .center)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
    }

    private func scaleFactor(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        guard textWidth > 0 else { return 1 }
        if textWidth <= width { return 1 }
        let adjusted = max(width - 12, 0)
        if adjusted <= 0 { return 0.65 }
        let scaled = adjusted / textWidth
        return max(0.65, scaled)
        #else
        return 1
        #endif
    }
}

private struct PulsingDotsView: View {
    let primaryColor: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSince1970
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(primaryColor.opacity(colorScheme == .dark ? 0.9 : 1))
                        .frame(width: 10, height: 10)
                        .scaleEffect(scale(for: time, index: index))
                        .opacity(opacity(for: time, index: index))
                }
            }
        }
    }

    private func scale(for time: TimeInterval, index: Int) -> CGFloat {
        let progress = (time + Double(index) * 0.22).remainder(dividingBy: 1.0)
        return 0.75 + 0.25 * CGFloat(sin(progress * 2 * .pi))
    }

    private func opacity(for time: TimeInterval, index: Int) -> Double {
        let progress = (time + Double(index) * 0.22).remainder(dividingBy: 1.0)
        return 0.5 + 0.5 * sin(progress * 2 * .pi + .pi / 2)
    }
}

private struct IdentifiedError: Identifiable {
    let id = UUID()
    let error: DiscoveryCreationFlowViewModel.FlowError
}
