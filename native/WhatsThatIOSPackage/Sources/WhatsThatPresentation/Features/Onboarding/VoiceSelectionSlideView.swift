import SwiftUI
import WhatsThatShared
import WhatsThatDomain

/// Voice selection slide for post-purchase configuration.
struct VoiceSelectionSlideView: View {
    @ObservedObject var viewModel: VoicePickerViewModel

    let onContinue: () -> Void
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Title
            Text("Who tells your stories?")
                .font(.adaptiveSystem(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.small)

            // Subtitle
            Text("Find the voice that makes you want to keep listening.")
                .font(.adaptiveSystem(size: 17, weight: .regular))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.large)

            // Voice picker
            VoicePickerView(
                viewModel: viewModel,
                showCreditNote: false,
                showAutoToggle: false,
                persistSelectionOnTap: false
            )

            Spacer()

            // Buttons
            VStack(spacing: BrandSpacing.small) {
                BrandPrimaryButton(title: "Continue") {
                    viewModel.stop()
                    onContinue()
                }

                Button {
                    viewModel.stop()
                    onSkip()
                } label: {
                    Text("Skip for now")
                        .font(.adaptiveBody().weight(.medium))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.xLarge)
        }
        .background(palette.background)
    }
}

#Preview {
    VoiceSelectionSlideView(
        viewModel: VoicePickerViewModel(
            loadVoiceoverPreferences: { VoiceoverPreferences(autoEnabled: true, voiceModelId: "", ttsModel: "") },
            saveVoiceoverPreferences: { _ in },
            fetchVoiceOptions: { [] },
            fetchVoiceSampleURL: { _ in nil }
        ),
        onContinue: {},
        onSkip: {}
    )
}
