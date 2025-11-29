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

    var body: some View {
        List {
            ForEach(Array(viewModel.orderedDraft.enumerated()), id: \.element.rawValue) { index, dimension in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: iconName(for: dimension))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(IPoPStrings.title(for: dimension))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            if index == 0 {
                                Text("Most important")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .foregroundStyle(Color.accentColor.opacity(0.12))
                                    )
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Text(viewModel.subtitle(for: dimension))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text("\(index + 1)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
            .onMove(perform: viewModel.move)
        }
        .environment(\.editMode, .constant(.active))
        .listStyle(.insetGrouped)
        .padding(.top, -BrandSpacing.small)
    }

    private func iconName(for dimension: IPoPDimension) -> String {
        switch dimension {
        case .ideas:
            return "lightbulb"
        case .people:
            return "person.2"
        case .objects:
            return "cube"
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
    @State private var hasSaved = false

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
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                Spacer()
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.top, BrandSpacing.large)

            VStack(alignment: .leading, spacing: BrandSpacing.small) {
                Text("Content Preferences")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, BrandSpacing.large)

                Text("Put these in the order that matters to you. We’ll shape our answers based on your preferences.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, BrandSpacing.large)
                VStack(alignment: .leading, spacing: 4) {
                    Text("I care about…")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, BrandSpacing.large)
                        .padding(.top, BrandSpacing.large)

                    IPoPPreferencesListView(viewModel: viewModel)
                        .frame(maxHeight: .infinity)
                }
            }

            Text(IPoPStrings.usageNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, BrandSpacing.large)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
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
