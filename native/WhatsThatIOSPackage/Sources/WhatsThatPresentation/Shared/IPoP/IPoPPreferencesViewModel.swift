import Foundation
import SwiftUI
import WhatsThatDomain

@MainActor
final class IPoPPreferencesViewModel: ObservableObject {
    @Published var orderedDraft: [IPoPDimension]
    @Published private(set) var persistedOrder: [IPoPDimension]?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let loadPreferences: () async -> IPoPPreferences?
    private let savePreferences: (IPoPPreferences) async -> Void
    private var hasLoaded = false

    init(
        loadPreferences: @escaping () async -> IPoPPreferences?,
        savePreferences: @escaping (IPoPPreferences) async -> Void
    ) {
        self.loadPreferences = loadPreferences
        self.savePreferences = savePreferences
        self.orderedDraft = IPoPDimension.allCases
    }

    func ensureLoaded() async {
        guard !hasLoaded else {
            resetDraftToPersistedOrDefault()
            return
        }
        hasLoaded = true
        await loadFromStore()
    }

    func resetDraftToPersistedOrDefault() {
        orderedDraft = persistedOrder ?? IPoPDimension.allCases
    }

    func move(from source: IndexSet, to destination: Int) {
        orderedDraft.move(fromOffsets: source, toOffset: destination)
    }

    func persistChanges() async -> Bool {
        guard let preferences = IPoPPreferences(ordered: orderedDraft) else {
            errorMessage = "Please include each option exactly once."
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        await savePreferences(preferences)
        persistedOrder = preferences.ordered
        return true
    }

    var summaryOrder: [String]? {
        persistedOrder?.map { IPoPStrings.title(for: $0) }
    }

    func subtitle(for dimension: IPoPDimension) -> String {
        IPoPStrings.detail(for: dimension)
    }

    func clearPersisted() {
        persistedOrder = nil
        orderedDraft = IPoPDimension.allCases
        errorMessage = nil
    }

    private func loadFromStore() async {
        isLoading = true
        defer { isLoading = false }

        let stored = await loadPreferences()
        if let stored {
            persistedOrder = stored.ordered
            orderedDraft = stored.ordered
        } else {
            persistedOrder = nil
            orderedDraft = IPoPDimension.allCases
        }
    }
}
