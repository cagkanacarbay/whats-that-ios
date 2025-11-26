import SwiftUI
import WhatsThatShared
import WhatsThatDomain

public struct VoicePickerView: View {
    @StateObject private var viewModel: VoicePickerViewModel
    let showCreditNote: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }
    
    public init(
        loadVoiceoverPreferences: @escaping () async -> VoiceoverPreferences,
        saveVoiceoverPreferences: @escaping (VoiceoverPreferences) async -> Void,
        fetchVoiceOptions: @escaping () async -> [VoiceModelOption],
        fetchVoiceSampleURL: @escaping (String) async -> URL?,
        showCreditNote: Bool = false
    ) {
        self._viewModel = StateObject(wrappedValue: VoicePickerViewModel(
            loadVoiceoverPreferences: loadVoiceoverPreferences,
            saveVoiceoverPreferences: saveVoiceoverPreferences,
            fetchVoiceOptions: fetchVoiceOptions,
            fetchVoiceSampleURL: fetchVoiceSampleURL
        ))
        self.showCreditNote = showCreditNote
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.voices.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Voice List
                ScrollView {
                    VStack(spacing: BrandSpacing.medium) {
                        ForEach(viewModel.voices, id: \.voiceModelId) { voice in
                            VoiceRow(
                                voiceName: voice.displayName,
                                isSelected: viewModel.selectedVoiceId == voice.voiceModelId,
                                isPlaying: viewModel.selectedVoiceId == voice.voiceModelId && viewModel.isPlaying,
                                palette: palette,
                                onSelect: {
                                    viewModel.selectVoice(id: voice.voiceModelId)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, BrandSpacing.large)
                    .padding(.bottom, BrandSpacing.large)
                }
            }
            
            // Auto-generate Toggle
            VStack(alignment: .leading, spacing: BrandSpacing.small) {
                Toggle(isOn: Binding(
                    get: { viewModel.isAutoEnabled },
                    set: { _ in viewModel.toggleAutoPlay() }
                )) {
                    Text("Auto-generate audio guides")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                }
                .toggleStyle(SwitchToggleStyle(tint: palette.primaryAction))
                
                if showCreditNote {
                    Text("Each audio guide uses one credit to generate.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.vertical, BrandSpacing.medium)
            .background(palette.background) // Ensure footer has background if list scrolls under?
        }
        .task {
            await viewModel.load()
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
    let palette: BrandTheme.Palette
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: BrandSpacing.medium) {
                // Icon / Indicator
                ZStack {
                    Circle()
                        .fill(isSelected ? palette.primaryAction.opacity(0.1) : palette.surface)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Circle().stroke(palette.border, lineWidth: isSelected ? 0 : 1)
                        )
                    
                    if isPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(palette.primaryAction)
                    } else {
                        Text(String(voiceName.prefix(1)))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(isSelected ? palette.primaryAction : palette.textSecondary)
                    }
                }
                
                Text(voiceName)
                    .font(.system(size: 17, weight: .semibold))
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
