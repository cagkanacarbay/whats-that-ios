import Foundation
import SwiftUI
import WhatsThatDomain
import WhatsThatShared
#if canImport(MarkdownUI)
import MarkdownUI
#endif
#if canImport(UIKit)
import UIKit
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

    @ObservedObject var viewModel: DiscoveryCreationFlowViewModel
    let placeholderEmoji: String
    let ctaTitle: String
    let retryTitle: String

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            content
        }
        .padding(.horizontal, BrandSpacing.large)
        .padding(.vertical, BrandSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        case let .analyzing(state):
            AnalysisStateView(
                state: state,
                imageData: viewModel.confirmationState?.displayImageData,
                onCancel: { viewModel.cancelFlow() }
            )
        }
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
        creditBalance == nil
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
            ZStack {
                palette.background.ignoresSafeArea()

                VStack {
                    Spacer(minLength: 0)
                    previewSection(size: proxy.size)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .topLeading) {
                overlayCircleButton(systemName: "xmark", action: onCancel)
                    .padding(.leading, BrandSpacing.large)
                    .padding(.top, BrandSpacing.xLarge)
            }
            .overlay(alignment: .topTrailing) {
                topTrailingControl
                    .padding(.trailing, BrandSpacing.large)
                    .padding(.top, BrandSpacing.xLarge)
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
        let targetHeight = max(size.height * 0.62, 320)
        if let image = previewImage {
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: size.width * 0.92)
                .frame(height: targetHeight)
                .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 16)
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(palette.border.opacity(0.1))
                .frame(width: size.width * 0.75, height: targetHeight)
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
    let state: DiscoveryAnalysisState
    let imageData: Data?
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var displayedMarkdown: String = ""
    @State private var loaderCleared: Bool = false
    @State private var shuffledMessages: [String] = AnalysisStateView.loadingMessages.shuffled()
    @State private var currentMessageIndex: Int = 0
    @State private var messageOpacity: Double = 1
    @State private var animateCharacters: Bool = false
    @State private var markdownAnimationTask: Task<Void, Never>?
    @State private var messageTimer: Timer?
    @State private var metadataVisible: Bool = false
    @State private var hasScrolledToContent = false
    @Namespace private var detailNamespace

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
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

    private var sanitizedNarrative: String {
        DiscoveryStreamFormatter.narrative(from: state.streamedText)
    }

    private var shouldShowLoader: Bool {
        !loaderCleared
    }

    var body: some View {
        if let summary = state.discoverySummary, !state.isStreaming {
            DiscoveryDetailView(
                discovery: summary,
                imageURL: summary.imagePath.flatMap(URL.init(string:)),
                namespace: detailNamespace,
                isExpanded: true,
                onClose: onCancel,
                onShare: makeShareAction(for: summary),
                onShowOptions: nil,
                onPlayAudio: nil
            )
            .background(palette.background.ignoresSafeArea())
            .onAppear {
                stopMessageRotation()
            }
        } else {
            GeometryReader { proxy in
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            imageSection(height: max(proxy.size.height * 0.78, 360))
                            markdownSection
                                .id(ScrollTarget.markdown)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(palette.background.ignoresSafeArea())
                    .onAppear {
                        resetStateForInitialRender()
                        startMessageRotationIfNeeded()
                        if loaderCleared {
                            DispatchQueue.main.async {
                                scrollToContent(using: scrollProxy, animated: false)
                            }
                        }
                    }
                    .onDisappear {
                        markdownAnimationTask?.cancel()
                        stopMessageRotation()
                    }
                    .onChange(of: state.displayMarkdown) { _ in
                        updateDisplayedMarkdown()
                    }
                    .onChange(of: state.metadataTitle) { _ in
                        evaluateMetadataVisibility()
                        evaluateLoaderCleared(with: displayedMarkdown)
                    }
                    .onChange(of: state.metadataShortDescription) { _ in
                        evaluateMetadataVisibility()
                        evaluateLoaderCleared(with: displayedMarkdown)
                    }
                    .onChange(of: state.isStreaming) { isStreaming in
                        if !isStreaming {
                            loaderCleared = true
                        }
                    }
                    .onChange(of: loaderCleared) { cleared in
                        if cleared {
                            stopMessageRotation()
                            scrollToContent(using: scrollProxy)
                        } else {
                            hasScrolledToContent = false
                            startMessageRotationIfNeeded()
                        }
                    }
                }
            }
        }
    }

    private func resetStateForInitialRender() {
        shuffledMessages = AnalysisStateView.loadingMessages.shuffled()
        currentMessageIndex = 0
        metadataVisible = (state.metadataTitle?.isEmpty == false) || (state.metadataShortDescription?.isEmpty == false)
        let initialNarrative = sanitizedNarrative
        displayedMarkdown = initialNarrative
        loaderCleared = loaderShouldBeCleared(for: initialNarrative)
        hasScrolledToContent = false
        if shouldShowLoader {
            triggerCharacterAnimation()
        }
    }

    private func updateDisplayedMarkdown() {
        let newValue = sanitizedNarrative
        guard newValue != displayedMarkdown else {
            evaluateLoaderCleared(with: newValue)
            return
        }
        animateMarkdown(to: newValue)
    }

    private func animateMarkdown(to target: String) {
        markdownAnimationTask?.cancel()
        let current = displayedMarkdown

        if target.count <= current.count + 2 {
            displayedMarkdown = target
            evaluateLoaderCleared(with: target)
            return
        }

        let delta = target.dropFirst(current.count)
        let delay = animationDelay(for: delta.count)

        markdownAnimationTask = Task {
            var buffer = current
            for character in delta {
                if Task.isCancelled { return }
                buffer.append(character)
                await MainActor.run {
                    displayedMarkdown = buffer
                    evaluateLoaderCleared(with: buffer)
                }
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func loaderShouldBeCleared(for text: String) -> Bool {
        if let title = state.metadataTitle, !title.isEmpty {
            return true
        }
        if let short = state.metadataShortDescription, !short.isEmpty {
            return true
        }
        if !state.isStreaming {
            return true
        }
        return DiscoveryStreamFormatter.visibleLength(for: text) >= AnalysisStateView.streamContentThreshold
    }

    private func evaluateLoaderCleared(with text: String) {
        if loaderCleared {
            return
        }
        if loaderShouldBeCleared(for: text) {
            loaderCleared = true
        }
    }

    private func evaluateMetadataVisibility() {
        let hasMetadata = (state.metadataTitle?.isEmpty == false) || (state.metadataShortDescription?.isEmpty == false)
        if hasMetadata && !metadataVisible {
            withAnimation(.easeInOut(duration: 0.25)) {
                metadataVisible = true
            }
        } else if !hasMetadata && metadataVisible && state.isStreaming {
            metadataVisible = false
        }
    }

    private func startMessageRotationIfNeeded() {
        guard shouldShowLoader else { return }
        guard messageTimer == nil else { return }

        triggerCharacterAnimation()

        let timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            rotateMessage()
        }
        RunLoop.main.add(timer, forMode: .common)
        messageTimer = timer
    }

    private func stopMessageRotation() {
        messageTimer?.invalidate()
        messageTimer = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            messageOpacity = 1
        }
    }

    private func rotateMessage() {
        guard shouldShowLoader else { return }
        guard !shuffledMessages.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.35)) {
            messageOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            currentMessageIndex = (currentMessageIndex + 1) % shuffledMessages.count
            triggerCharacterAnimation()
            withAnimation(.easeInOut(duration: 0.35)) {
                messageOpacity = 1
            }
        }
    }

    private func triggerCharacterAnimation() {
        animateCharacters = false
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.78)) {
                animateCharacters = true
            }
        }
    }

    private func animationDelay(for count: Int) -> UInt64 {
        let characters = max(1, count)
        let perCharacter = min(0.08, max(0.014, 0.9 / Double(characters)))
        return UInt64(perCharacter * 1_000_000_000)
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
    private func imageSection(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if let image = previewImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(palette.border.opacity(0.18))
                    .frame(height: height)
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
                colors: [
                    Color.clear,
                    palette.overlayMidtone,
                    palette.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
            .allowsHitTesting(false)

            overlayContent
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.large * CGFloat(1.2))
        }
    }

    private var overlayContent: some View {
        VStack(spacing: BrandSpacing.medium) {
            if shouldShowLoader {
                if !currentLoadingMessage.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(currentLoadingMessage.enumerated()), id: \.offset) { index, character in
                            Text(character == " " ? "\u{00A0}" : String(character))
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(Color.white)
                                .opacity(animateCharacters ? 1 : 0.25)
                                .animation(
                                    .interpolatingSpring(stiffness: 160, damping: 16)
                                        .delay(Double(index) * 0.05),
                                    value: animateCharacters
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .opacity(messageOpacity)
                    .animation(.easeInOut(duration: 0.35), value: messageOpacity)
                }

                if let status = state.statusMessage, !status.isEmpty {
                    Text(status)
                        .font(.system(size: 15, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, BrandSpacing.large)
                        .lineLimit(2)
                }
            } else {
                VStack(spacing: BrandSpacing.small) {
                    if let title = state.metadataTitle, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 26, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                    }
                    if let short = state.metadataShortDescription, !short.isEmpty {
                        Text(short)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.92))
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

    @ViewBuilder
    private var markdownSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            if displayedMarkdown.isEmpty || shouldShowLoader {
                if state.isStreaming {
                    Text("We’re composing your story…")
                        .font(.system(size: 15))
                        .foregroundStyle(palette.textSecondary)
                        .italic()
                } else {
                    Text("Analysis complete. Opening your discovery…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                #if canImport(MarkdownUI)
                Markdown(displayedMarkdown)
                    .markdownTheme(BrandMarkdownThemeFactory.discoveryDetailTheme(for: palette))
                    .animation(.easeInOut(duration: 0.2), value: displayedMarkdown)
                #else
                Text(displayedMarkdown)
                    .font(.system(size: 16))
                    .foregroundStyle(palette.textSecondary)
                #endif
            }
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

private enum DiscoveryStreamFormatter {
    private static let userResponseDelimiter = "=== USER RESPONSE ==="
    private static let confidencePrefix = "confidence level"
    private static let metadataHeadingRegex = try? NSRegularExpression(
        pattern: #"###\s*metadata_json"#,
        options: [.caseInsensitive]
    )

    static func narrative(from source: String) -> String {
        guard !source.isEmpty else { return "" }

        var working = source

        if let delimiterRange = working.range(of: userResponseDelimiter) {
            let afterDelimiter = working[delimiterRange.upperBound...]
            working = String(afterDelimiter).trimmingCharacters(in: .whitespacesAndNewlines)

            if working.lowercased().hasPrefix(confidencePrefix) {
                if let newlineIndex = working.firstIndex(of: "\n") {
                    let trimmed = working[newlineIndex...].dropFirst()
                    working = String(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    working = ""
                }
            }
        }

        working = removeMetadataSection(from: working)
        working = working.trimmingCharacters(in: .whitespacesAndNewlines)

        if let headingRange = working.range(of: #"##\s+"#, options: .regularExpression) {
            working = String(working[headingRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func visibleLength(for text: String) -> Int {
        narrative(from: text).trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private static func removeMetadataSection(from source: String) -> String {
        guard
            let regex = metadataHeadingRegex,
            let match = regex.firstMatch(
                in: source,
                options: [],
                range: NSRange(location: 0, length: source.utf16.count)
            ),
            let headingRange = Range(match.range, in: source)
        else {
            return source
        }

        if let jsonRange = findJsonBounds(in: source, startingAt: headingRange.upperBound) {
            var mutable = source
            mutable.removeSubrange(headingRange.lowerBound..<jsonRange.upperBound)
            return mutable
        } else {
            var mutable = source
            mutable.removeSubrange(headingRange.lowerBound..<mutable.endIndex)
            return mutable
        }
    }

    private static func findJsonBounds(in source: String, startingAt startIndex: String.Index) -> Range<String.Index>? {
        guard let start = source[startIndex...].firstIndex(of: "{") else {
            return nil
        }

        var index = start
        var depth = 0

        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let end = source.index(after: index)
                    return start..<end
                }
            }

            index = source.index(after: index)
        }

        return nil
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
