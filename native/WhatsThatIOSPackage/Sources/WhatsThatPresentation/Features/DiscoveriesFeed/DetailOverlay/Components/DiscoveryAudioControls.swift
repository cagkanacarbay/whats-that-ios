import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct DiscoveryAudioControls: View {
    let discovery: DiscoverySummary
    @Binding var scrollOffset: CGFloat

    private var voiceoverStatus: AudioGuideRowStatus {
        guard let asset = voiceoverController.normalizedAsset(for: discovery.id) else {
            return .empty
        }
        switch asset.status {
        case .ready:
            return .ready(duration: nil)
        case .streamingReady:
            return .streamingReady
        case .processing:
            return .generating
        case .failed:
            return .failed
        case .none, .missing:
            return .empty
        }
    }

    private var isPlaying: Bool {
        if case .playing(let id) = voiceoverController.playbackState {
            return id == discovery.id
        }
        return false
    }
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.postPurchaseConfig) private var postPurchaseConfig

    @ObservedObject private var voiceoverController: VoiceoverPlaybackController
    private let queueStore: AudioGuidesQueueStore
    private let progressStore: VoiceoverProgressStore
    private let creditBalanceStore: CreditBalanceStore?
    
    // MARK: - Scroll Animation Constants
    private let scrollTransitionThreshold: CGFloat = 60
    
    /// Progress from 0 (at top) to 1 (scrolled past threshold)
    private var scrollProgress: CGFloat {
        min(1.0, max(0.0, scrollOffset / scrollTransitionThreshold))
    }
    
    /// Shadow fully disappears when scrolled for "pop-down" effect
    private var animatedShadowOpacity: Double {
        0.15 * (1 - scrollProgress)
    }
    
    private var animatedShadowRadius: CGFloat {
        10 * (1 - scrollProgress)
    }
    
    private var animatedShadowY: CGFloat {
        4 * (1 - scrollProgress)
    }
    
    /// Border fades out when scrolled
    private var animatedBorderOpacity: Double {
        1.0 - scrollProgress
    }
    
    /// Pill shifts down when scrolled to embed into content
    private var animatedVerticalOffset: CGFloat {
        scrollProgress * 12
    }
    
    // Streaming animation state
    @State private var streamingRotation = Angle.zero

    // Feedback state for queue buttons
    @State private var showPlayNextConfirmation = false
    @State private var showAddToEndConfirmation = false
    
    // Generation confirmation state
    @State private var showGenerateConfirmation = false
    @State private var creditBalance: Int?
    
    // MARK: - Credits Sheet State
    @State private var showCreditsSheet: Bool = false
    @State private var presentedCreditsViewModel: CreditsViewModel?
    @State private var creditsSheetDetent: PresentationDetent = .fraction(0.8)
    private let makeCreditsViewModel: (() -> CreditsViewModel)?

    // Post-purchase configuration closures
    private let loadVoiceoverPreferences: (() async -> VoiceoverPreferences)?
    private let saveVoiceoverPreferences: ((VoiceoverPreferences) async -> Void)?
    private let fetchVoiceOptions: (() async -> [VoiceModelOption])?
    private let fetchVoiceSampleURL: ((String) async -> URL?)?
    private let loadIPoPPreferences: (() async -> IPoPPreferences?)?
    private let saveIPoPPreferences: ((IPoPPreferences) async -> Void)?

    init(
        discovery: DiscoverySummary,
        audioServices: AudioServicesContainer,
        scrollOffset: Binding<CGFloat>,
        makeCreditsViewModel: (() -> CreditsViewModel)? = nil,
        loadVoiceoverPreferences: (() async -> VoiceoverPreferences)? = nil,
        saveVoiceoverPreferences: ((VoiceoverPreferences) async -> Void)? = nil,
        fetchVoiceOptions: (() async -> [VoiceModelOption])? = nil,
        fetchVoiceSampleURL: ((String) async -> URL?)? = nil,
        loadIPoPPreferences: (() async -> IPoPPreferences?)? = nil,
        saveIPoPPreferences: ((IPoPPreferences) async -> Void)? = nil
    ) {
        self.discovery = discovery
        self._scrollOffset = scrollOffset
        self._voiceoverController = ObservedObject(wrappedValue: audioServices.playbackController)
        self.queueStore = audioServices.queueStore
        self.progressStore = audioServices.progressStore
        self.creditBalanceStore = audioServices.creditBalanceStore
        self.makeCreditsViewModel = makeCreditsViewModel
        self.loadVoiceoverPreferences = loadVoiceoverPreferences
        self.saveVoiceoverPreferences = saveVoiceoverPreferences
        self.fetchVoiceOptions = fetchVoiceOptions
        self.fetchVoiceSampleURL = fetchVoiceSampleURL
        self.loadIPoPPreferences = loadIPoPPreferences
        self.saveIPoPPreferences = saveIPoPPreferences
    }
    
    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }
    
    var body: some View {
        // Center the bar horizontally
        HStack {
            Spacer()
            
            // Unified audio control bar - matches mini player styling
            Button(action: handleMainAction) {
                HStack(spacing: 16) {
                    // Left side: Play icon + text
                    HStack(spacing: 10) {
                        mainButtonIcon
                            .transition(.scale.combined(with: .opacity))
                        
                        mainButtonText
                            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    }
                    
                    // Right side: Queue actions (only when audio is ready)
                    if voiceoverStatus.isPlayable {
                        HStack(spacing: 4) {
                            queueActionButton(
                                iconName: "text.insert",
                                label: "Next",
                                isConfirmed: showPlayNextConfirmation,
                                action: playNext
                            )
                            
                            queueActionButton(
                                iconName: "text.append",
                                label: "Queue",
                                isConfirmed: showAddToEndConfirmation,
                                action: addToEnd
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: UIDevice.isIPad ? 66 : 50)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(palette.surface.opacity(0.95))
                        .shadow(
                            color: Color.black.opacity(animatedShadowOpacity),
                            radius: animatedShadowRadius,
                            x: 0,
                            y: animatedShadowY
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(palette.border.opacity(animatedBorderOpacity), lineWidth: 0.5)
                        )
                )
                .offset(y: animatedVerticalOffset)
            }
            .buttonStyle(UnifiedBarButtonStyle())
            .disabled(isButtonDisabled)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPlaying)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: voiceoverStatus)
            
            Spacer()
        }
        .alert(
            (creditBalance ?? 1) > 0 ? "Generate an audio guide?" : "You need credits to generate audio guides",
            isPresented: $showGenerateConfirmation,
            actions: {
                if (creditBalance ?? 1) > 0 {
                    Button("Cancel", role: .cancel) { }
                    Button("Generate") {
                        voiceoverController.generateVoiceover(for: discovery)
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Not Now", role: .cancel) { }
                    Button("Get Credits") {
                        presentCreditsSheet()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            },
            message: {
                if (creditBalance ?? 1) > 0 {
                    if let balance = creditBalance {
                        Text("This will use 1 credit. You have \(String(balance)) credits remaining.")
                    } else {
                        Text("This will use 1 credit.")
                    }
                } else {
                    Text("Each audio guide costs 1 credit. Purchase more to continue.")
                }
            }
        )
        .task {
            if let store = creditBalanceStore {
                creditBalance = await store.getCached()
            }
        }
        // MARK: - Credits Sheet
        .sheet(isPresented: $showCreditsSheet, onDismiss: {
            presentedCreditsViewModel = nil
            creditsSheetDetent = .fraction(0.8)
        }) {
            NavigationStack {
                if let creditsViewModel = presentedCreditsViewModel {
                    CreditsView(
                        viewModel: creditsViewModel,
                        loadVoiceoverPreferences: loadVoiceoverPreferences ?? postPurchaseConfig?.loadVoiceoverPreferences,
                        saveVoiceoverPreferences: saveVoiceoverPreferences ?? postPurchaseConfig?.saveVoiceoverPreferences,
                        fetchVoiceOptions: fetchVoiceOptions ?? postPurchaseConfig?.fetchVoiceOptions,
                        fetchVoiceSampleURL: fetchVoiceSampleURL ?? postPurchaseConfig?.fetchVoiceSampleURL,
                        loadIPoPPreferences: loadIPoPPreferences ?? postPurchaseConfig?.loadIPoPPreferences,
                        saveIPoPPreferences: saveIPoPPreferences ?? postPurchaseConfig?.saveIPoPPreferences
                    )
                } else {
                    Text("Credits unavailable")
                        .font(.headline)
                        .padding()
                }
            }
            .presentationDetents([.fraction(0.8), .large], selection: $creditsSheetDetent)
            .presentationDragIndicator(.visible)
        }
        // MARK: - Observe assetStates for insufficient_credits errors
        .onChange(of: voiceoverController.assetStates) { oldStates, newStates in
            DispatchQueue.main.async {
                guard let asset = newStates[discovery.id],
                      asset.errorReason == "insufficient_credits" else { return }
                // Only react to NEW errors - ignore if error already existed in old state
                let hadErrorBefore = oldStates[discovery.id]?.errorReason == "insufficient_credits"
                guard !hadErrorBefore else { return }
                // Update local credit balance to 0 since server says no credits
                creditBalance = 0
                // Also update the store's cache
                if let store = creditBalanceStore {
                    Task {
                        await store.set(0)
                    }
                }
                // Don't auto-present credits sheet during intro mode -
                // CreditsExhaustedFullScreenView handles this case
                Task {
                    let isIntroMode = await FreeCreditsAlertTracker.shared.isInIntroMode
                    if !isIntroMode {
                        await MainActor.run {
                            presentCreditsSheet()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Credits Sheet Helpers
    
    private func presentCreditsSheet() {
        guard let factory = makeCreditsViewModel else { return }
        let creditsViewModel = factory()
        presentedCreditsViewModel = creditsViewModel
        creditsSheetDetent = .fraction(0.8)
        showCreditsSheet = true
    }
    
    // Inline queue action button for the unified bar
    @ViewBuilder
    private func queueActionButton(
        iconName: String,
        label: String,
        isConfirmed: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if isConfirmed {
                    Image(systemName: "checkmark")
                        .font(.system(size: UIDevice.isIPad ? 18 : 14, weight: .bold))
                        .foregroundColor(BrandColors.logo)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: UIDevice.isIPad ? 18 : 14, weight: .semibold))
                        .foregroundColor(palette.textSecondary)
                        .transition(.scale.combined(with: .opacity))
                }
                
                Text(label)
                    .font(.system(size: UIDevice.isIPad ? 12 : 9, weight: .medium))
                    .foregroundColor(isConfirmed ? BrandColors.logo : palette.textSecondary)
            }
            .frame(width: UIDevice.isIPad ? 60 : 44, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var mainButtonIcon: some View {
        ZStack {
            Circle()
                .fill(BrandColors.logo)
                .frame(width: UIDevice.isIPad ? 48 : 36, height: UIDevice.isIPad ? 48 : 36)
            
            Group {
                if isPlaying {
                    Image(systemName: "pause.fill")
                        .font(.system(size: UIDevice.isIPad ? 22 : 16, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    switch voiceoverStatus {
                    case .ready:
                        Image(systemName: "play.fill")
                            .font(.system(size: UIDevice.isIPad ? 22 : 16, weight: .bold))
                            .offset(x: 2)
                            .transition(.scale.combined(with: .opacity))
                    case .streamingReady:
                        Image(systemName: "play.fill")
                            .font(.system(size: UIDevice.isIPad ? 22 : 16, weight: .bold))
                            .offset(x: 2)
                            .transition(.scale.combined(with: .opacity))
                    case .generating, .generationQueued, .checking:
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                            .transition(.opacity)
                    case .empty, .failed:
                        Image(systemName: "sparkles")
                            .font(.system(size: UIDevice.isIPad ? 22 : 16, weight: .bold))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .foregroundColor(.white)
            .id(isPlaying ? "playing" : String(describing: voiceoverStatus))
        }
        .overlay {
            if case .streamingReady = voiceoverStatus, !isPlaying {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.white.opacity(0.7), lineWidth: 2)
                    .frame(width: UIDevice.isIPad ? 48 : 36, height: UIDevice.isIPad ? 48 : 36)
                    .rotationEffect(streamingRotation)
            }
        }
        .onAppear {
            if case .streamingReady = voiceoverStatus {
                startStreamingAnimation()
            }
        }
        .onChange(of: voiceoverStatus) { newStatus in
            if case .streamingReady = newStatus {
                startStreamingAnimation()
            }
        }
        .onChange(of: isPlaying) { _, nowPlaying in
            // Restart spinning when playback stops but status is still streamingReady
            if !nowPlaying, case .streamingReady = voiceoverStatus {
                startStreamingAnimation()
            }
        }
    }
    
    @ViewBuilder
    private var mainButtonText: some View {
        Group {
            if isPlaying {
                Text("Pause")
            } else {
                switch voiceoverStatus {
                case .ready, .streamingReady:
                    Text("Play")
                case .generating, .generationQueued:
                    Text("Generating...")
                case .checking:
                    Text("Checking...")
                case .empty, .failed:
                    Text("Generate Audio")
                }
            }
        }
        .font(.system(size: UIDevice.isIPad ? 22 : 16, weight: .semibold))
        .foregroundColor(palette.textPrimary)
    }
    
    private func startStreamingAnimation() {
        streamingRotation = .zero
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            streamingRotation = .degrees(360)
        }
    }

    private func handleMainAction() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        switch voiceoverStatus {
        case .ready, .streamingReady:
            voiceoverController.togglePlayback(for: discovery)
        case .empty:
            // Show confirmation for new generation
            withAnimation {
                showGenerateConfirmation = true
            }
        case .failed:
            // Retry immediately without confirmation
            voiceoverController.generateVoiceover(for: discovery)
        default:
            break
        }
    }
    
    private var isButtonDisabled: Bool {
        switch voiceoverStatus {
        case .generating, .generationQueued, .checking:
            return true
        case .ready, .streamingReady, .empty, .failed:
            return false
        }
    }
    
    private func playNext() {
        queueStore.playNext(discovery.id)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showPlayNextConfirmation = true
        }
        
        // Reset confirmation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showPlayNextConfirmation = false
            }
        }
    }
    
    private func addToEnd() {
        queueStore.addToEnd(discovery.id)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showAddToEndConfirmation = true
        }
        
        // Reset confirmation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showAddToEndConfirmation = false
            }
        }
    }
}

// MARK: - Helper Components

struct QueueActionButton: View {
    let iconName: String
    let label: String
    let isConfirmed: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }
    
    var body: some View {
        Button(action: action) {
             VStack(spacing: 4) {
                 if isConfirmed {
                     Image(systemName: "checkmark")
                         .font(.system(size: 18, weight: .bold))
                         .foregroundColor(BrandColors.logo) // Use brand color for tick
                         .transition(.scale.combined(with: .opacity))
                 } else {
                     Image(systemName: iconName)
                         .font(.system(size: 18, weight: .semibold))
                         .foregroundColor(palette.textSecondary)
                         .transition(.scale.combined(with: .opacity))
                 }
                 
                 Text(label)
                     .font(.system(size: 10, weight: .medium))
                     .foregroundColor(isConfirmed ? BrandColors.logo : palette.textSecondary)
             }
             .frame(width: 60)
        }
        .buttonStyle(PressedBackgroundButtonStyle(palette: palette, isConfirmed: isConfirmed))
    }
}

struct PressedBackgroundButtonStyle: ButtonStyle {
    let palette: BrandTheme.Palette
    let isConfirmed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed || isConfirmed ? palette.surface.opacity(0.8) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct UnifiedBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
