import SwiftUI
import WhatsThatShared
import WhatsThatDomain

/// Container view for post-purchase configuration slides (thank you + voice + IPOP).
/// Shown after first successful credit purchase.
struct PostPurchaseConfigurationFlow: View {
    @StateObject private var voicePickerViewModel: VoicePickerViewModel
    @StateObject private var ipopViewModel: IPoPPreferencesViewModel

    let creditAmount: Int
    let onComplete: () -> Void

    @State private var currentSlide: Slide = .thankYou

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    enum Slide {
        case thankYou
        case voice
        case ipop
    }

    init(
        creditAmount: Int,
        loadVoiceoverPreferences: @escaping () async -> VoiceoverPreferences,
        saveVoiceoverPreferences: @escaping (VoiceoverPreferences) async -> Void,
        fetchVoiceOptions: @escaping () async -> [VoiceModelOption],
        fetchVoiceSampleURL: @escaping (String) async -> URL?,
        loadIPoPPreferences: @escaping () async -> IPoPPreferences?,
        saveIPoPPreferences: @escaping (IPoPPreferences) async -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.creditAmount = creditAmount
        _voicePickerViewModel = StateObject(
            wrappedValue: VoicePickerViewModel(
                loadVoiceoverPreferences: loadVoiceoverPreferences,
                saveVoiceoverPreferences: saveVoiceoverPreferences,
                fetchVoiceOptions: fetchVoiceOptions,
                fetchVoiceSampleURL: fetchVoiceSampleURL
            )
        )
        _ipopViewModel = StateObject(
            wrappedValue: IPoPPreferencesViewModel(
                loadPreferences: loadIPoPPreferences,
                savePreferences: saveIPoPPreferences
            )
        )
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: BrandSpacing.small) {
                progressDot(isActive: currentSlide == .thankYou)
                progressDot(isActive: currentSlide == .voice)
                progressDot(isActive: currentSlide == .ipop)
            }
            .padding(.top, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.medium)

            // Content (swipeable pages)
            TabView(selection: $currentSlide) {
                ThankYouSlideView(
                    creditAmount: creditAmount,
                    onContinue: { moveToVoice() }
                )
                .tag(Slide.thankYou)

                VoiceSelectionSlideView(
                    viewModel: voicePickerViewModel,
                    onContinue: { moveToIPOP() },
                    onSkip: { moveToIPOP() },
                    onBack: { moveToThankYou() }
                )
                .tag(Slide.voice)

                IPOPPreferencesSlideView(
                    viewModel: ipopViewModel,
                    onContinue: { finishConfiguration() },
                    onBack: { moveToVoice() }
                )
                .tag(Slide.ipop)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentSlide)
        }
        .background(palette.background)
        .task {
            await voicePickerViewModel.ensureLoadedForDisplay()
            await ipopViewModel.ensureLoaded()
        }
    }

    @ViewBuilder
    private func progressDot(isActive: Bool) -> some View {
        Circle()
            .fill(isActive ? BrandColors.Light.tabSelected : palette.textSecondary.opacity(0.3))
            .frame(width: 8, height: 8)
    }

    private func moveToThankYou() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentSlide = .thankYou
        }
    }

    private func moveToVoice() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentSlide = .voice
        }
    }

    private func moveToIPOP() {
        Task {
            await voicePickerViewModel.persistCurrentSelection()
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentSlide = .ipop
        }
    }

    private func finishConfiguration() {
        Task {
            // Ensure IPoP preferences are saved before completing
            _ = await ipopViewModel.persistChanges()
            await MainActor.run {
                onComplete()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PostPurchaseConfigurationFlow(
        creditAmount: 10,
        loadVoiceoverPreferences: { VoiceoverPreferences(autoEnabled: true, voiceModelId: "", ttsModel: "") },
        saveVoiceoverPreferences: { _ in },
        fetchVoiceOptions: { [] },
        fetchVoiceSampleURL: { _ in nil },
        loadIPoPPreferences: { nil },
        saveIPoPPreferences: { _ in },
        onComplete: {}
    )
}
