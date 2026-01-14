import SwiftUI
import WhatsThatDomain
import WhatsThatShared

enum IPoPStrings {
    static let usageNote = "Most answers will lean on your top picks, and we’ll blend others when it helps. You can change them anytime."

    static func title(for dimension: IPoPDimension) -> String {
        switch dimension {
        case .ideas:
            return "Ideas"
        case .people:
            return "People"
        case .objects:
            return "Objects"
        case .physical:
            return "Physical"
        }
    }

    static func detail(for dimension: IPoPDimension) -> String {
        switch dimension {
        case .ideas:
            return "concepts, reasons, why they matter and how things connect"
        case .people:
            return "the people involved, feelings, relationships, and stories "
        case .objects:
            return "things, aesthetics, craftsmanship, and the design details"
        case .physical:
            return "the sensations: movement, touch, sound, taste, light, and smell"
        }
    }
}

struct IPoPPreferencesListView: View {
    @ObservedObject var viewModel: IPoPPreferencesViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        List {
            ForEach(Array(viewModel.orderedDraft.enumerated()), id: \.element.rawValue) { index, dimension in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(BrandColors.Light.tabSelected.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(BrandColors.Light.tabSelected.opacity(0.3), lineWidth: 1.5)
                            )
                            .frame(width: 36, height: 36)
                        Image(systemName: iconName(for: dimension))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BrandColors.Light.tabSelected)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(IPoPStrings.title(for: dimension))
                                .font(.adaptiveSystem(size: 16, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            if index == 0 {
                                Text("Most important")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(BrandColors.Light.tabSelected.opacity(0.12))
                                    )
                                    .foregroundStyle(BrandColors.Light.tabSelected)
                            }
                        }
                        Text(viewModel.subtitle(for: dimension))
                            .font(.adaptiveFootnote())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text("\(index + 1)")
                        .font(.adaptiveSystem(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }
                .padding(.vertical, 4)
                .listRowBackground(palette.surface)
            }
            .onMove(perform: viewModel.move)
        }
        .environment(\.editMode, .constant(.active))
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .padding(.top, -BrandSpacing.small)
    }

    private func iconName(for dimension: IPoPDimension) -> String {
        switch dimension {
        case .ideas:
            return "lightbulb.fill"
        case .people:
            return "person.2.fill"
        case .objects:
            return "cube.fill"
        case .physical:
            return "figure.walk"
        }
    }
}

struct IPoPPreferencesSheet: View {
    @ObservedObject var viewModel: IPoPPreferencesViewModel
    let onSaved: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasSaved = false

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            HStack {
                Button {
                    onCancel()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Settings")
                            .font(.adaptiveSystem(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                Spacer()
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.top, BrandSpacing.large)

            VStack(alignment: .leading, spacing: BrandSpacing.small) {
                Text("Content Preferences")
                    .font(.adaptiveSystem(size: 24, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                Text("Put these in the order that matters to you. We’ll shape our answers based on your preferences.")
                    .font(.adaptiveFootnote())
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.horizontal, BrandSpacing.large)
                VStack(alignment: .leading, spacing: 4) {
                    Text("I care about…")
                        .font(.adaptiveSystem(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .padding(.horizontal, BrandSpacing.large)
                        .padding(.top, BrandSpacing.large)
                        .padding(.bottom, BrandSpacing.small)

                    IPoPPreferencesListView(viewModel: viewModel)
                        .frame(maxHeight: .infinity)
                }
            }

            Text(IPoPStrings.usageNote)
                .font(.adaptiveFootnote())
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.horizontal, BrandSpacing.large)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.adaptiveFootnote())
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, BrandSpacing.large)
            }

            BrandPrimaryButton(title: viewModel.isSaving ? "Saving…" : "Save order") {
                Task { await saveAndDismiss() }
            }
            .disabled(viewModel.isSaving)
            .padding(.horizontal, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.large)
        }
        .background(palette.background)
        .onAppear {
            viewModel.resetDraftToPersistedOrDefault()
        }
    }

    private func saveAndDismiss() async {
        let didSave = await viewModel.persistChanges()
        if didSave {
            hasSaved = true
            onSaved()
        }
    }
}
