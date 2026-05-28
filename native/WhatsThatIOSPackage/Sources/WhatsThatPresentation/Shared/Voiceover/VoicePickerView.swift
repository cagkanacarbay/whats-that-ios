import SwiftUI
import WhatsThatShared

public struct VoicePickerView: View {
    @ObservedObject private var viewModel: VoicePickerViewModel
    let showCreditNote: Bool
    let showAutoToggle: Bool
    let persistSelectionOnTap: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }
    
    public init(
        viewModel: VoicePickerViewModel,
        showCreditNote: Bool = false,
        showAutoToggle: Bool = true,
        persistSelectionOnTap: Bool = true
    ) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.showCreditNote = showCreditNote
        self.showAutoToggle = showAutoToggle
        self.persistSelectionOnTap = persistSelectionOnTap
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.voices.isEmpty {
                ProgressView()
                    .tint(BrandColors.Light.tabSelected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Voice List
                ScrollView {
                    VStack(spacing: BrandSpacing.medium) {
                        ForEach(viewModel.voices, id: \.voiceModelId) { voice in
                            let sampleState = viewModel.sampleStates[voice.voiceModelId] ?? .idle
                            VoiceRow(
                                voiceName: voice.displayName,
                                isSelected: viewModel.selectedVoiceId == voice.voiceModelId,
                                isPlaying: viewModel.playingVoiceId == voice.voiceModelId && viewModel.isPlaying,
                                isLoading: sampleState.isLoading && !sampleState.isReady,
                                palette: palette,
                                onSelect: {
                                    viewModel.handleVoiceTap(
                                        id: voice.voiceModelId,
                                        persistSelection: persistSelectionOnTap
                                    )
                                }
                            )
                        }
                    }
                    .padding(.horizontal, BrandSpacing.large)
                    .padding(.bottom, BrandSpacing.large)
                }
            }
            if showAutoToggle {
                VStack(alignment: .leading, spacing: BrandSpacing.small) {
                    Toggle(isOn: Binding(
                        get: { viewModel.isAutoEnabled },
                        set: { newValue in viewModel.setAutoEnabled(newValue) }
                    )) {
                        Text("Auto-generate audio guides after analysis")
                            .font(.adaptiveSystem(size: 17, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                    .disabled(viewModel.isAutoToggleLocked)
                    
                    if viewModel.isAutoToggleLocked {
                        Text("Enabled for your free intro voiceovers. You can disable this after your introduction credits are exhausted.")
                            .font(.adaptiveSystem(size: 13, weight: .regular))
                            .foregroundStyle(palette.textSecondary)
                    } else if showCreditNote {
                        Text("Each audio guide uses one credit to generate. Oh, but it's so worth it.")
                            .font(.adaptiveSystem(size: 13, weight: .regular))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, BrandSpacing.large)
                .padding(.vertical, BrandSpacing.medium)
                .background(palette.background)
            }
        }
        .task {
            await viewModel.ensureLoadedForDisplay()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

struct VoiceRow: View {
    let voiceName: String
    let isSelected: Bool
    let isPlaying: Bool
    let isLoading: Bool
    let palette: BrandTheme.Palette
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: BrandSpacing.medium) {
                // Icon / Indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(BrandColors.Light.tabSelected.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(BrandColors.Light.tabSelected.opacity(0.3), lineWidth: 1.5)
                        )
                        .frame(width: 48, height: 48)
                    
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(BrandColors.Light.tabSelected)
                            .frame(width: 20, height: 20)
                    } else if isPlaying {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(BrandColors.Light.tabSelected)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(BrandColors.Light.tabSelected)
                    }
                }
                
                Text(voiceName)
                    .font(.adaptiveSystem(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                
                Spacer()
                
                // Radio Selection
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? palette.primaryAction : palette.border, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(palette.primaryAction)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(BrandSpacing.medium)
            .background(
                RoundedRectangle(cornerRadius: BrandCornerRadius.medium)
                    .fill(palette.surface)
                    .shadow(
                        color: isSelected ? palette.primaryAction.opacity(0.1) : Color.black.opacity(0.05),
                        radius: isSelected ? 8 : 2,
                        x: 0,
                        y: 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrandCornerRadius.medium)
                    .stroke(isSelected ? palette.primaryAction.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
