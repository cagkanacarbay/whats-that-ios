import Foundation
import SwiftUI
import WhatsThatDomain
import WhatsThatShared

/// Coordinates the discovery creation flow lifecycle.
///
/// Owns the two creation flow ViewModels, manages modal presentation state
/// (with dismiss-animation guards), handles discovery completion tracking
/// (fallback timer + store upsert), and configures session manager callbacks.
///
/// Extracted from MainTabView in Phase 4 of the architecture redesign.
/// MainTabView now delegates all creation-flow concerns to this coordinator.
@MainActor
final class CreationFlowCoordinator: ObservableObject {

    // MARK: - Modal Presentation State

    /// The currently active creation flow type, drives fullScreenCover presentation.
    @Published var activeFlowType: DiscoveryCreationFlowType?

    /// Pending flow type queued during a dismiss animation.
    private(set) var pendingCreationFlowAfterDismiss: DiscoveryCreationFlowType?

    /// True between activeFlowType=nil and fullScreenCover's onDismiss callback.
    /// Prevents setting a new activeFlowType during the dismiss animation,
    /// which SwiftUI silently drops (leaving the state stuck).
    private(set) var isDismissingModal = false

    // MARK: - ViewModels

    let cameraViewModel: DiscoveryCreationFlowViewModel
    let uploadViewModel: DiscoveryCreationFlowViewModel

    // MARK: - Dependencies

    let audioServices: AudioServicesContainer
    let makeCreditsViewModel: (() -> CreditsViewModel)?
    let loadVoiceoverPreferences: (() async -> VoiceoverPreferences)?
    let saveVoiceoverPreferences: ((VoiceoverPreferences) async -> Void)?
    let fetchVoiceOptions: (() async -> [VoiceModelOption])?
    let fetchVoiceSampleURL: ((String) async -> URL?)?
    let loadIPoPPreferences: (() async -> IPoPPreferences?)?
    let saveIPoPPreferences: ((IPoPPreferences) async -> Void)?

    // MARK: - Internal State

    private var awaitingSummaryId: Int64?
    private var summaryFallbackTask: Task<Void, Never>?
    private let storeObserver: DiscoveryStoreObserver

    private var sessionManager: DiscoverySessionManager { DiscoverySessionManager.shared }

    // MARK: - Init

    init(
        cameraViewModel: DiscoveryCreationFlowViewModel,
        uploadViewModel: DiscoveryCreationFlowViewModel,
        audioServices: AudioServicesContainer,
        storeObserver: DiscoveryStoreObserver,
        makeCreditsViewModel: (() -> CreditsViewModel)? = nil,
        loadVoiceoverPreferences: (() async -> VoiceoverPreferences)? = nil,
        saveVoiceoverPreferences: ((VoiceoverPreferences) async -> Void)? = nil,
        fetchVoiceOptions: (() async -> [VoiceModelOption])? = nil,
        fetchVoiceSampleURL: ((String) async -> URL?)? = nil,
        loadIPoPPreferences: (() async -> IPoPPreferences?)? = nil,
        saveIPoPPreferences: ((IPoPPreferences) async -> Void)? = nil
    ) {
        self.cameraViewModel = cameraViewModel
        self.uploadViewModel = uploadViewModel
        self.audioServices = audioServices
        self.storeObserver = storeObserver
        self.makeCreditsViewModel = makeCreditsViewModel
        self.loadVoiceoverPreferences = loadVoiceoverPreferences
        self.saveVoiceoverPreferences = saveVoiceoverPreferences
        self.fetchVoiceOptions = fetchVoiceOptions
        self.fetchVoiceSampleURL = fetchVoiceSampleURL
        self.loadIPoPPreferences = loadIPoPPreferences
        self.saveIPoPPreferences = saveIPoPPreferences
    }

    // MARK: - Modal Presentation

    /// Attempts to present the creation flow modal for the given type.
    /// Guards against presenting while a modal is already active or during a dismiss animation.
    func tryPresentFlow(type: DiscoveryCreationFlowType) {
        guard activeFlowType == nil else { return }
        if isDismissingModal {
            pendingCreationFlowAfterDismiss = type
            return
        }
        var transaction = Transaction(animation: .none)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeFlowType = type
        }
    }

    /// Dismisses the creation flow modal instantly (no slide-down animation).
    func dismissFlow() {
        isDismissingModal = true
        var transaction = Transaction(animation: .none)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeFlowType = nil
        }
    }

    /// Called when the fullScreenCover's onDismiss fires (dismiss animation complete).
    /// Handles pending flow re-presentation if queued during the dismiss animation.
    func handleModalDismissCompleted() {
        isDismissingModal = false
        if let pendingType = pendingCreationFlowAfterDismiss {
            pendingCreationFlowAfterDismiss = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                var transaction = Transaction(animation: .none)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self?.activeFlowType = pendingType
                }
            }
        }
    }

    // MARK: - Discovery Lifecycle

    /// Handles a newly created discovery ID from the stream's .complete event.
    /// Starts a fallback timer to reload discoveries if the summary callback doesn't arrive.
    func handleDiscoveryCreated(_ discoveryId: Int64) {
        awaitingSummaryId = discoveryId
        summaryFallbackTask?.cancel()
        summaryFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.awaitingSummaryId == discoveryId {
                    Task { await self?.storeObserver.reload() }
                }
            }
        }
    }

    /// Handles a completed discovery (from streaming completion or polling recovery).
    /// Upserts the summary to the store and cancels the fallback timer.
    func handleCompletedDiscovery(_ summary: DiscoverySummary) {
        summaryFallbackTask?.cancel()
        awaitingSummaryId = nil
        Task {
            await storeObserver.upsert(summary)
            await audioServices.discoveryStore.upsert(summary)
        }
    }

    // MARK: - Session Manager

    /// Configures session manager callbacks for background discovery completion.
    func configureSessionManager() {
        let audioServices = self.audioServices
        let storeObserver = self.storeObserver
        sessionManager.onDiscoveryCompleted = { [weak audioServices, weak storeObserver] summary, generateAudio in
            Task { @MainActor in
                await storeObserver?.upsert(summary)
            }
            if generateAudio {
                audioServices?.playbackController.generateVoiceover(for: summary)
            }
        }
        sessionManager.onDiscoveryFailed = { _, _ in }
    }

    /// Cancels the fallback timer task on cleanup.
    func cleanup() {
        summaryFallbackTask?.cancel()
    }

    // MARK: - Reconnect

    /// Reconnects to an in-progress session by attaching the ViewModel
    /// and presenting the creation flow modal.
    func reconnectToSession(_ item: InProgressItem) {
        let vm = viewModel(for: item.flowType)
        vm.attachToSession(sessionId: item.id, media: item.media)
        tryPresentFlow(type: item.flowType)
    }

    // MARK: - Helpers

    /// Returns the ViewModel for a given flow type.
    func viewModel(for flowType: DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel {
        flowType == .camera ? cameraViewModel : uploadViewModel
    }
}
