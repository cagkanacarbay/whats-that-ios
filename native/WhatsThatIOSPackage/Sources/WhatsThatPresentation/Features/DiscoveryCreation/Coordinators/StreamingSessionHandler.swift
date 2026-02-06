import Combine
import Foundation
import UIKit
import WhatsThatDomain
import WhatsThatShared

/// Discrete events from StreamingSessionHandler → VM.
@MainActor
protocol StreamingSessionDelegate: AnyObject {
    func streamingDidCreateDiscovery(_ discoveryId: Int64)
    func streamingDidCompleteDiscovery(_ summary: DiscoverySummary)
    func streamingDidFail(_ error: DiscoveryCreationFlowViewModel.FlowError)
    func streamingDidUpdateCreditBalance(_ balance: Int?)
    func streamingDidChangeFlowState(_ state: DiscoveryCreationFlowState)
    func streamingShouldShowAudioModal()
    func streamingShouldShowPollingFailedAlert()
    func streamingShouldReturnToConfirmation()
}

/// Handles the analysis streaming session lifecycle including event processing,
/// polling fallback, image caching, and photo library saving.
@MainActor
final class StreamingSessionHandler: DiscoverySessionSubscriber {
    /// Continuous state — VM bridges to its @Published via Combine subscription.
    @Published private(set) var analysisState: DiscoveryAnalysisState?

    /// Delegate for discrete events (completion, error, UI triggers).
    weak var delegate: StreamingSessionDelegate?

    /// Media from the last analysis start (for retry).
    private(set) var pendingMedia: DiscoveryCapturedMedia?

    /// Current session ID (for unsubscribing during discoverMore transition).
    private(set) var currentSessionId: UUID?

    private let historyRepository: DiscoveryHistoryRepository
    private let creditBalanceStore: CreditBalanceStore
    private let photoSavePreferencesStore: PhotoSavePreferencesStore?
    private let photoLibrarySaveService: (any PhotoLibrarySaveServiceProtocol)?
    private let analysisParser = DiscoveryAnalysisParser()

    private var analysisStartTime: Date?
    private var pollingTask: Task<Void, Never>?

    #if DEBUG
    private let debugLoggingEnabled = true

    /// Set to true to simulate polling always failing (never finds discovery)
    static var debugPollingAlwaysFails: Bool = false

    /// Set to true to use short polling intervals (5s total instead of ~79s)
    static var debugUseShortPollingIntervals: Bool = false
    #else
    private let debugLoggingEnabled = false
    #endif

    /// Returns polling intervals - short for debugging, normal for production
    private var pollingIntervals: [TimeInterval] {
        #if DEBUG
        if Self.debugUseShortPollingIntervals {
            return [1, 1, 1, 1, 1]  // 5s total for quick testing
        }
        #endif
        return [1, 2, 4, 8, 16, 16, 16, 16]  // ~79s total
    }

    init(
        historyRepository: DiscoveryHistoryRepository,
        creditBalanceStore: CreditBalanceStore,
        photoSavePreferencesStore: PhotoSavePreferencesStore?,
        photoLibrarySaveService: (any PhotoLibrarySaveServiceProtocol)?
    ) {
        self.historyRepository = historyRepository
        self.creditBalanceStore = creditBalanceStore
        self.photoSavePreferencesStore = photoSavePreferencesStore
        self.photoLibrarySaveService = photoLibrarySaveService
    }

    /// Start analysis session via the session manager.
    func startSession(
        payload: DiscoveryAnalysisPayload,
        media: DiscoveryCapturedMedia,
        generateAudioGuide: Bool,
        flowType: DiscoveryCreationFlowType
    ) {
        let initialState = DiscoveryAnalysisState(
            statusMessage: "Preparing analysis…",
            streamedText: "",
            isStreaming: true
        )
        analysisState = initialState
        analysisStartTime = Date()
        pendingMedia = media
        pollingTask?.cancel()
        pollingTask = nil

        currentSessionId = DiscoverySessionManager.shared.startSession(
            payload: payload,
            media: media,
            generateAudioGuide: generateAudioGuide,
            flowType: flowType,
            subscriber: self
        )

        debugLog("Started session \(currentSessionId?.uuidString ?? "nil") via session manager")
    }

    /// Save photo to library if enabled (camera captures only).
    func savePhotoIfEnabled(media: DiscoveryCapturedMedia) async {
        guard let preferencesStore = photoSavePreferencesStore,
              let saveService = photoLibrarySaveService else {
            debugLog("Photo save services not available")
            return
        }

        let isEnabled = await preferencesStore.isEnabled()
        guard isEnabled else {
            debugLog("Photo auto-save is disabled")
            return
        }

        debugLog("Saving photo to library...")

        let result = await saveService.save(imageData: media.data)
        switch result {
        case .success:
            debugLog("Photo saved to library successfully")
        case .permissionDenied:
            debugLog("Photo save skipped: permission denied")
        case .permissionRestricted:
            debugLog("Photo save skipped: permission restricted")
        case .saveFailed(let error):
            debugLog("Photo save failed: \(error.localizedDescription)")
        }
    }

    /// Attaches to an existing session in the manager, replaying accumulated events.
    /// Used when reconnecting to a background session from the Discoveries tab.
    func attachToExistingSession(sessionId: UUID, media: DiscoveryCapturedMedia) {
        let initialState = DiscoveryAnalysisState(
            statusMessage: "Reconnecting…",
            streamedText: "",
            isStreaming: true
        )
        analysisState = initialState
        pendingMedia = media
        currentSessionId = sessionId
        pollingTask?.cancel()
        pollingTask = nil

        // Subscribe — manager replays accumulated events via handleSessionEvent()
        DiscoverySessionManager.shared.subscribe(to: sessionId, subscriber: self)
        debugLog("Attached to existing session \(sessionId)")
    }

    /// Unsubscribe from session (stream continues in background).
    func unsubscribe() {
        if let sessionId = currentSessionId {
            DiscoverySessionManager.shared.unsubscribe(from: sessionId)
            currentSessionId = nil
        }
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Cancel all tasks and clean up.
    func cancel() {
        pollingTask?.cancel()
        pollingTask = nil
        analysisState = nil
        pendingMedia = nil
        analysisStartTime = nil
        currentSessionId = nil
    }

    static func messageIndicatesInsufficientCredits(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("insufficient") || lower.contains("credit") || lower.contains("no credits")
    }

    // MARK: - DiscoverySessionSubscriber

    public func handleSessionEvent(_ event: DiscoveryAnalysisEvent) {
        handle(event: event)
    }

    public func sessionDidComplete(discoveryId: Int64, summary: DiscoverySummary?) {
        debugLog("sessionDidComplete: discoveryId=\(discoveryId)")

        if let summary {
            analysisState = analysisStateUpdated { state in
                state.discoverySummary = summary
            }
            delegate?.streamingDidCompleteDiscovery(summary)
        }

        currentSessionId = nil
    }

    public func sessionDidFail(error: Error) {
        debugLog("sessionDidFail: \(error.localizedDescription)")

        // Special handling for stream interruption - start polling fallback
        if let analysisError = error as? DiscoveryAnalysisError, analysisError == .streamInterrupted {
            debugLog("Stream interrupted - starting polling fallback")
            analysisState = analysisStateUpdated { state in
                state.isStreaming = false
                state.isPolling = true
                state.statusMessage = "Connection interrupted. Checking for your discovery..."
            }
            if let analysisState {
                delegate?.streamingDidChangeFlowState(.analyzing(analysisState))
            }
            startPollingForCompletion()
            return
        }

        let message = error.localizedDescription
        if Self.messageIndicatesInsufficientCredits(message) {
            delegate?.streamingShouldReturnToConfirmation()
        } else {
            delegate?.streamingDidFail(.analysisFailed(message))
            delegate?.streamingDidChangeFlowState(.error(message: message))

            // Refresh credits to ensure we aren't out of sync
            Task { [weak self] in
                guard let self else { return }
                if let updated = try? await self.creditBalanceStore.refresh() {
                    self.delegate?.streamingDidUpdateCreditBalance(updated)
                }
            }
        }

        currentSessionId = nil
    }

    // MARK: - Event Handling

    private func handle(event: DiscoveryAnalysisEvent) {
        debugLog("Received \(debugDescription(for: event))")
        switch event {
        case let .status(message):
            analysisState = analysisStateUpdated { state in
                state.statusMessage = message
            }
        case let .metadata(title, shortDescription):
            analysisState = analysisStateUpdated { state in
                let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedShort = shortDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let trimmedTitle, !trimmedTitle.isEmpty {
                    state.metadataTitle = trimmedTitle
                }
                if let trimmedShort, !trimmedShort.isEmpty {
                    state.metadataShortDescription = trimmedShort
                }
            }
        case let .token(token):
            analysisState = analysisStateUpdated { state in
                state.streamedText.append(token)
                state.isStreaming = true
            }
        case let .complete(discoveryId, systemVersion, userVersion, serverCreditBalance):
            debugLog("Received .complete event for discoveryId: \(discoveryId)")
            analysisState = analysisStateUpdated { state in
                state.discoveryIdentifier = discoveryId
                state.isStreaming = false
                state.statusMessage = "Completed"
                state.systemPromptVersion = systemVersion
                state.userPromptVersion = userVersion
            }
            delegate?.streamingDidCreateDiscovery(discoveryId)
            cacheDiscoveryImageIfNeeded(for: discoveryId)
            handleSuccessfulCreation(discoveryId: discoveryId, serverCreditBalance: serverCreditBalance)
        case let .error(message, status):
            // Decrement intro discovery count - edge function returned error, discovery not created
            Task {
                await FreeCreditsAlertTracker.shared.decrementIntroDiscoveryCount()
            }

            if status == 402 || Self.messageIndicatesInsufficientCredits(message) {
                delegate?.streamingShouldReturnToConfirmation()
            } else {
                delegate?.streamingDidFail(.analysisFailed(message))
                delegate?.streamingDidChangeFlowState(.error(message: message))
            }
        case .end:
            // Finalize: publish a single flowState update to reflect final analysis state.
            if let analysisState {
                delegate?.streamingDidChangeFlowState(.analyzing(analysisState))
            }
        }
    }

    // MARK: - Background Polling

    private func startPollingForCompletion() {
        debugLog("startPollingForCompletion")
        pollingTask?.cancel()
        let intervals = pollingIntervals
        pollingTask = Task { [weak self] in
            var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
            backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "DiscoveryPolling") {
                if backgroundTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskId)
                    backgroundTaskId = .invalid
                }
            }
            defer {
                if backgroundTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskId)
                }
            }

            for (_, interval) in intervals.enumerated() {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }

                if let discovery = await self?.checkForCompletedDiscovery() {
                    await MainActor.run { self?.handlePollingDiscoveryReady(discovery) }
                    return
                }
            }

            await MainActor.run { self?.handlePollingTimeout() }
        }
    }

    private func checkForCompletedDiscovery() async -> DiscoverySummary? {
        #if DEBUG
        if Self.debugPollingAlwaysFails { return nil }
        #endif

        guard let startTime = analysisStartTime else { return nil }

        do {
            let searchStartTime = startTime.addingTimeInterval(-30)
            let recents = try await historyRepository.fetchRecentDiscoveries(limit: 5)
            return recents.first { $0.capturedAt >= searchStartTime }
        } catch {
            debugLog("Failed to fetch recent discoveries during polling: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    private func handlePollingDiscoveryReady(_ discovery: DiscoverySummary) {
        analysisState = DiscoveryAnalysisState(
            statusMessage: "Discovery complete!",
            streamedText: discovery.detailDescription ?? "",
            isStreaming: false,
            isPolling: false,
            discoveryIdentifier: discovery.id,
            metadataTitle: discovery.title,
            metadataShortDescription: discovery.shortDescription,
            displayMarkdown: discovery.detailDescription ?? "",
            discoverySummary: discovery
        )

        delegate?.streamingDidChangeFlowState(.analyzing(analysisState!))
        delegate?.streamingDidCompleteDiscovery(discovery)
        handleSuccessfulCreation(discoveryId: discovery.id)
    }

    @MainActor
    private func handlePollingTimeout() {
        analysisState = analysisStateUpdated { state in
            state.isPolling = false
            state.isStreaming = false
            state.statusMessage = "Connection lost"
        }

        if let analysisState {
            delegate?.streamingDidChangeFlowState(.analyzing(analysisState))
        }

        delegate?.streamingShouldShowPollingFailedAlert()
    }

    // MARK: - Success Handling

    private func handleSuccessfulCreation(discoveryId: Int64, serverCreditBalance: Int? = nil) {
        debugLog("handleSuccessfulCreation: discoveryId=\(discoveryId)")
        Task { [weak self] in
            guard let self else { return }
            let updated: Int?
            if let serverBalance = serverCreditBalance {
                updated = await self.creditBalanceStore.set(serverBalance)
            } else {
                updated = await self.creditBalanceStore.getCached()
            }
            self.delegate?.streamingDidUpdateCreditBalance(updated)

            let tracker = FreeCreditsAlertTracker.shared
            let shouldShowAudioModal = await tracker.shouldShowAudioGeneratingModal()
            if shouldShowAudioModal {
                await tracker.markAudioGeneratingModalShown()
                self.delegate?.streamingShouldShowAudioModal()
                self.debugLog("Showing audio generating modal")
            }
        }
    }

    // MARK: - Image Caching

    private func cacheDiscoveryImageIfNeeded(for discoveryId: Int64) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let recents = try await self.historyRepository.fetchRecentDiscoveries(limit: 25)
                guard let summary = recents.first(where: { $0.id == discoveryId }) else { return }

                if let capturedData = self.pendingMedia?.data {
                    let storedURL = await DiscoveryAssetCache.shared.storeImageData(
                        capturedData,
                        discoveryId: discoveryId
                    )

                    if storedURL == nil,
                       let path = summary.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                       let remoteURL = URL(string: path) {
                        _ = await DiscoveryAssetCache.shared.ensureImageCached(
                            for: discoveryId,
                            signedURL: remoteURL
                        )
                    }
                } else if let path = summary.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let remoteURL = URL(string: path) {
                    _ = await DiscoveryAssetCache.shared.ensureImageCached(
                        for: discoveryId,
                        signedURL: remoteURL
                    )
                }
            } catch {
                // Intentionally ignore fetch errors
            }
        }
    }

    // MARK: - Analysis State

    private func analysisStateUpdated(_ transform: (inout DiscoveryAnalysisState) -> Void) -> DiscoveryAnalysisState {
        var existing = analysisState ?? DiscoveryAnalysisState()
        let previousStream = existing.streamedText
        let previousTitle = existing.metadataTitle
        let previousShort = existing.metadataShortDescription
        transform(&existing)
        let streamChanged = existing.streamedText != previousStream
        let metadataChanged = existing.metadataTitle != previousTitle || existing.metadataShortDescription != previousShort

        if streamChanged || metadataChanged {
            let parsed = analysisParser.parse(existing.streamedText)
            if debugLoggingEnabled {
                if let parsed {
                    let t = parsed.metadata?.title ?? "nil"
                    let sLen = parsed.metadata?.shortDescription?.count ?? 0
                    debugLog("parser: metadata(title: \(t), shortLen: \(sLen))")
                } else {
                    let preview = String(existing.streamedText.suffix(140)).replacingOccurrences(of: "\n", with: " ")
                    debugLog("parser: no metadata yet, streamSuffix=…\(preview)")
                }
            }

            if let parsedTitle = parsed?.metadata?.title, !parsedTitle.isEmpty {
                existing.metadataTitle = parsedTitle
            }
            if let parsedShort = parsed?.metadata?.shortDescription, !parsedShort.isEmpty {
                existing.metadataShortDescription = parsedShort
            }

            let hasMetadata = (existing.metadataTitle?.isEmpty == false) || (existing.metadataShortDescription?.isEmpty == false)
            if hasMetadata {
                if let parsedMarkdown = parsed?.markdown {
                    existing.displayMarkdown = parsedMarkdown
                } else {
                    existing.displayMarkdown = DiscoveryStreamFormatter.narrative(from: existing.streamedText)
                }
            }
        }
        return existing
    }

    // MARK: - Debug

    private func debugDescription(for event: DiscoveryAnalysisEvent) -> String {
        switch event {
        case let .status(message):
            return "status(message: \(message))"
        case let .metadata(title, short):
            let titlePreview = title.map { String($0.prefix(40)) } ?? "nil"
            let shortPreview = short.map { String($0.prefix(40)) } ?? "nil"
            return "metadata(title: \(titlePreview), short: \(shortPreview))"
        case let .token(token):
            let preview = String(token.replacingOccurrences(of: "\n", with: " ").prefix(60))
            return "token(len: \(token.count), preview: \(preview))"
        case let .complete(id, system, user, credits):
            return "complete(id: \(id), system: \(system ?? "nil"), user: \(user ?? "nil"), credits: \(credits.map { String($0) } ?? "nil"))"
        case let .error(message, status):
            if let status {
                return "error(message: \(message), status: \(status))"
            } else {
                return "error(message: \(message))"
            }
        case .end:
            return "end"
        }
    }

    private func debugLog(_ message: String) {
        guard debugLoggingEnabled else { return }
        // print("[StreamingSessionHandler] \(message)")
    }
}
