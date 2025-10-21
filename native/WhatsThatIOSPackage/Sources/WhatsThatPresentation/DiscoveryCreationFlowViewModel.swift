import Foundation
import SwiftUI
import WhatsThatDomain
import WhatsThatShared

@MainActor
public final class DiscoveryCreationFlowViewModel: ObservableObject {
    public struct Configuration {
        let type: DiscoveryCreationFlowType
        let maxImageDimension: Int
        let recentHistoryLimit: Int

        public init(
            type: DiscoveryCreationFlowType,
            maxImageDimension: Int,
            recentHistoryLimit: Int
        ) {
            self.type = type
            self.maxImageDimension = maxImageDimension
            self.recentHistoryLimit = recentHistoryLimit
        }
    }

    enum FlowError: LocalizedError, Equatable {
        case permissionDenied
        case captureFailed
        case selectionFailed
        case encodingFailed
        case locationUnavailable
        case noCredits
        case analysisFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Permission denied. Update your settings to continue."
            case .captureFailed, .selectionFailed:
                return "We couldn’t get that photo. Try again."
            case .encodingFailed:
                return "We had trouble preparing your photo for analysis."
            case .locationUnavailable:
                return "We couldn’t access your location."
            case .noCredits:
                return "You need at least 1 credit to continue."
            case let .analysisFailed(message):
                return message
            }
        }
    }

    @Published private(set) var flowState: DiscoveryCreationFlowState = .idle {
        didSet {
            debugLog("flowState -> \(flowStateSummary(flowState))")
        }
    }
    @Published private(set) var confirmationState: DiscoveryConfirmationState?
    @Published private(set) var analysisState: DiscoveryAnalysisState?
    @Published private(set) var creditBalance: Int?
    @Published private(set) var error: FlowError?
    @Published private(set) var pushToken: String?

    var onDiscoveryCreated: ((Int64) -> Void)?
    var onDiscoverySummaryReady: ((DiscoverySummary) -> Void)?
    var onAnalysisBegan: ((DiscoveryCreationFlowType) -> Void)?

    private let configuration: Configuration
    private let captureService: DiscoveryCaptureService
    private let selectionService: DiscoverySelectionService
    private let historyRepository: DiscoveryHistoryRepository
    private let creditsRepository: DiscoveryCreditsRepository
    private let creditBalanceStore: CreditBalanceStore
    private let analysisClient: DiscoveryAnalysisClient
    private let imageEncoder: DiscoveryImageEncodingService
    private let pushService: DiscoveryPushService
    private let locationService: DiscoveryLocationService
    private let analysisParser = DiscoveryAnalysisParser()
    #if DEBUG
    private let debugLoggingEnabled = true
    #else
    private let debugLoggingEnabled = false
    #endif

    private var currentMedia: DiscoveryCapturedMedia?
    private var analysisTask: Task<Void, Never>?

    var flowType: DiscoveryCreationFlowType {
        configuration.type
    }

    public init(
        configuration: Configuration,
        captureService: DiscoveryCaptureService,
        selectionService: DiscoverySelectionService,
        historyRepository: DiscoveryHistoryRepository,
        creditsRepository: DiscoveryCreditsRepository,
        creditBalanceStore: CreditBalanceStore,
        analysisClient: DiscoveryAnalysisClient,
        imageEncoder: DiscoveryImageEncodingService,
        pushService: DiscoveryPushService,
        locationService: DiscoveryLocationService
    ) {
        self.configuration = configuration
        self.captureService = captureService
        self.selectionService = selectionService
        self.historyRepository = historyRepository
        self.creditsRepository = creditsRepository
        self.creditBalanceStore = creditBalanceStore
        self.analysisClient = analysisClient
        self.imageEncoder = imageEncoder
        self.pushService = pushService
        self.locationService = locationService
    }

    func startFlow(retake: Bool = false) {
        debugLog("startFlow(retake: \(retake))")
        Task {
            await beginFlow(retake: retake)
        }
    }

    func cancelFlow() {
        debugLog("cancelFlow()")
        analysisTask?.cancel()
        analysisTask = nil
        confirmationState = nil
        analysisState = nil
        currentMedia = nil
        flowState = .cancelled
        error = nil
        locationService.stopTracking()
    }

    func retake() {
        startFlow(retake: true)
    }

    func beginAnalysis() {
        debugLog("beginAnalysis()")
        guard case let .confirming(state) = flowState else { return }
        guard let media = currentMedia else {
            error = .captureFailed
            return
        }

        if let balance = creditBalance, balance <= 0 {
            error = .noCredits
            return
        }

        onAnalysisBegan?(configuration.type)
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.performAnalysis(media: media, confirmation: state)
        }
    }

    func clearError() {
        error = nil
    }

    private func beginFlow(retake: Bool) async {
        error = nil
        analysisTask?.cancel()
        analysisTask = nil
        analysisState = nil
        confirmationState = nil
        creditBalance = nil

        switch configuration.type {
        case .camera:
            flowState = retake ? .capturingRetake : .requestingPermissions
            let granted = await captureService.requestPermission(for: .camera)
            guard granted else {
                error = .permissionDenied
                flowState = .error(message: FlowError.permissionDenied.errorDescription ?? "Permission denied")
                return
            }
            flowState = retake ? .capturingRetake : .capturingInitial
            do {
                let media = try await captureService.capturePhoto()
                await prepareConfirmation(with: media)
            } catch {
                self.error = .captureFailed
                flowState = .error(message: FlowError.captureFailed.errorDescription ?? "Capture failed")
            }
        case .upload:
            flowState = retake ? .selectingRetake : .requestingPermissions
            let granted = await selectionService.requestPermission()
            guard granted else {
                error = .permissionDenied
                flowState = .error(message: FlowError.permissionDenied.errorDescription ?? "Permission denied")
                return
            }
            flowState = retake ? .selectingRetake : .selectingInitial
            do {
                let media = try await selectionService.selectPhoto()
                await prepareConfirmation(with: media)
            } catch {
                self.error = .selectionFailed
                flowState = .error(message: FlowError.selectionFailed.errorDescription ?? "Selection failed")
            }
        }
    }

    private func prepareConfirmation(with media: DiscoveryCapturedMedia) async {
        let initialConfirmationState = DiscoveryConfirmationState(
            media: media,
            displayImageData: media.data,
            creditBalance: nil,
            location: nil,
            locationDescription: nil,
            isLocationPermissionGranted: false,
            customContext: nil
        )

        confirmationState = initialConfirmationState
        flowState = .confirming(initialConfirmationState)
        currentMedia = media

        await locationService.startTrackingIfNeeded()

        // Load cached credits immediately and refresh in background.
        if let cached = await creditBalanceStore.getCached() {
            creditBalance = cached
        }

        async let locationTask = locationService.currentLocation()
        async let historyTask = historyRepository.fetchRecentDiscoveries(limit: configuration.recentHistoryLimit)
        async let pushTask = pushService.requestPushAuthorizationIfNeeded()

        var location: DiscoveryLocation? = nil
        var locationDescription: String? = nil
        var permissionGranted = false

        let locationValue = await locationTask
        location = media.location ?? locationValue
        permissionGranted = locationValue != nil
        locationDescription = DiscoveryCreationFlowViewModel.makeLocationDescription(from: location)

        // Refresh credits if stale; if it fails, keep the cached value.
        do {
            let balance = try await creditBalanceStore.refreshIfStale()
            creditBalance = balance
        } catch {
            // Keep existing cached value
        }

        do {
            let discoveries = try await historyTask
            let builder = DiscoveryContextBuilder()
            confirmationState?.customContext = builder.buildContext(from: discoveries)
        } catch {
            confirmationState?.customContext = nil
        }

        do {
            let token = try await pushTask
            pushToken = token
        } catch {
            pushToken = nil
        }

        confirmationState = confirmationState.map { current in
            DiscoveryConfirmationState(
                media: current.media,
                displayImageData: current.displayImageData,
                creditBalance: creditBalance,
                location: location,
                locationDescription: locationDescription,
                isLocationPermissionGranted: permissionGranted,
                customContext: current.customContext
            )
        }
        // Only re-emit confirming if we are still in the confirmation step.
        // If analysis has already begun, do not bounce the UI back to confirmation.
        if case .confirming = flowState {
            flowState = .confirming(confirmationState!)
        }
    }

    private func performAnalysis(media: DiscoveryCapturedMedia, confirmation: DiscoveryConfirmationState) async {
        defer { analysisTask = nil }
        let initialState = DiscoveryAnalysisState(
            statusMessage: "Preparing analysis…",
            streamedText: "",
            isStreaming: true
        )
        analysisState = initialState
        flowState = .analyzing(initialState)

        do {
            let payload = DiscoveryAnalysisPayload(
                base64Image: try await imageEncoder.makeBase64Payload(from: media, maxDimension: configuration.maxImageDimension),
                location: confirmation.location,
                customContext: confirmation.customContext,
                pushToken: pushToken
            )

            let sessionId = UUID()
            let stream = analysisClient.startAnalysis(
                payload: payload,
                sessionId: sessionId,
                cancellationHandler: { [weak self] in
                    await self?.handleAnalysisCancellation()
                }
            )

            for try await event in stream {
                handle(event: event)
            }
        } catch is CancellationError {
            await handleAnalysisCancellation()
        } catch {
            let message = (error as? FlowError)?.errorDescription ?? error.localizedDescription
            locationService.stopTracking()
            if Self.messageIndicatesInsufficientCredits(message) {
                // Normalize to friendly no-credits error and sync local cache.
                self.error = .noCredits
                self.flowState = .error(message: FlowError.noCredits.errorDescription ?? message)
                Task { [weak self] in
                    guard let self else { return }
                    let updated = await self.creditBalanceStore.set(0)
                    await MainActor.run {
                        self.creditBalance = updated
                    }
                }
            } else {
                self.error = .analysisFailed(message)
                self.flowState = .error(message: message)
            }
        }
    }

    private func handle(event: DiscoveryAnalysisEvent) {
        debugLog("Received \(debugDescription(for: event))")
        switch event {
        case let .status(message):
            analysisState = analysisStateUpdated { state in
                state.statusMessage = message
            }
            // Coarse phase: do not republish flowState during streaming/status updates.
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
            // Coarse phase: do not republish flowState during streaming/metadata updates.
        case let .token(token):
            analysisState = analysisStateUpdated { state in
                state.streamedText.append(token)
                state.isStreaming = true
            }
            // Coarse phase: do not republish flowState for each token.
        case let .complete(discoveryId, systemVersion, userVersion):
            analysisState = analysisStateUpdated { state in
                state.discoveryIdentifier = discoveryId
                state.isStreaming = false
                state.statusMessage = "Completed"
                state.systemPromptVersion = systemVersion
                state.userPromptVersion = userVersion
            }
            // Do not republish flowState here; wait for the final end signal.
            locationService.stopTracking()
            onDiscoveryCreated?(discoveryId)
            hydrateDiscoverySummaryIfNeeded(for: discoveryId)
            // Optimistically decrement credits on success.
            Task { [weak self] in
                guard let self else { return }
                let updated = await self.creditBalanceStore.adjust(by: -1)
                await MainActor.run {
                    self.creditBalance = updated
                }
            }
        case let .error(message, status):
            locationService.stopTracking()
            if status == 402 || Self.messageIndicatesInsufficientCredits(message) {
                // Normalize to a friendly no-credits error and sync local cache.
                error = .noCredits
                flowState = .error(message: FlowError.noCredits.errorDescription ?? message)
                Task { [weak self] in
                    guard let self else { return }
                    let updated = await self.creditBalanceStore.set(0)
                    await MainActor.run {
                        self.creditBalance = updated
                    }
                }
            } else {
                error = .analysisFailed(message)
                flowState = .error(message: message)
            }
        case .end:
            // Finalize: publish a single flowState update to reflect final analysis state.
            if let analysisState {
                flowState = .analyzing(analysisState)
            }
        }
    }

    private static func messageIndicatesInsufficientCredits(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("insufficient") || lower.contains("credit") || lower.contains("no credits")
    }

    private func handleAnalysisCancellation() async {
        analysisTask?.cancel()
        analysisTask = nil
        analysisState = nil
        flowState = .cancelled
        locationService.stopTracking()
    }

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

            // Update metadata as soon as it is fully available in the stream
            if let parsedTitle = parsed?.metadata?.title, !parsedTitle.isEmpty {
                existing.metadataTitle = parsedTitle
            }
            if let parsedShort = parsed?.metadata?.shortDescription, !parsedShort.isEmpty {
                existing.metadataShortDescription = parsedShort
            }

            // Gate narrative rendering until metadata has been parsed, to avoid
            // rendering raw metadata JSON into the description area during streaming.
            let hasMetadata = (existing.metadataTitle?.isEmpty == false) || (existing.metadataShortDescription?.isEmpty == false)
            if hasMetadata {
                if let parsedMarkdown = parsed?.markdown {
                    existing.displayMarkdown = parsedMarkdown
                } else {
                    existing.displayMarkdown = DiscoveryStreamFormatter.narrative(from: existing.streamedText)
                }
            } else {
                // Keep whatever is currently shown (typically empty) until metadata arrives.
            }
        }
        return existing
    }

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
        case let .complete(id, system, user):
            return "complete(id: \(id), system: \(system ?? "nil"), user: \(user ?? "nil"))"
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
        print("[DiscoveryCreationFlowViewModel] \(message)")
    }

    private func flowStateSummary(_ state: DiscoveryCreationFlowState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .requestingPermissions:
            return "requestingPermissions"
        case .capturingInitial:
            return "capturingInitial"
        case .capturingRetake:
            return "capturingRetake"
        case .selectingInitial:
            return "selectingInitial"
        case .selectingRetake:
            return "selectingRetake"
        case .confirming(let confirmation):
            let balance = confirmation.creditBalance.map(String.init) ?? "nil"
            return "confirming(hasImage: \(confirmation.displayImageData.isEmpty == false), creditBalance: \(balance))"
        case .analyzing(let analysis):
            return "analyzing(streamLen: \(analysis.streamedText.count), markdownLen: \(analysis.displayMarkdown.count), metadata: \(analysis.metadataTitle != nil), summary: \(analysis.discoverySummary != nil), isStreaming: \(analysis.isStreaming))"
        case .cancelled:
            return "cancelled"
        case let .error(message):
            return "error(\(message))"
        }
    }

    private func syncFlowStateWithAnalysis() {
        if let analysisState {
            flowState = .analyzing(analysisState)
        }
    }

    private func hydrateDiscoverySummaryIfNeeded(for discoveryId: Int64) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let recents = try await self.historyRepository.fetchRecentDiscoveries(limit: max(self.configuration.recentHistoryLimit, 25))
                guard let summary = recents.first(where: { $0.id == discoveryId }) else { return }

                let capturedData = await MainActor.run { self.currentMedia?.data }
                if let capturedData {
                    let storedURL = await DiscoveryAssetCache.shared.storeImageData(
                        capturedData,
                        discoveryId: discoveryId
                    )
                    await MainActor.run { self.currentMedia = nil }

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

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.analysisState = self.analysisStateUpdated { state in
                        state.discoverySummary = summary
                    }
                    self.onDiscoverySummaryReady?(summary)
                }
            } catch {
                // Intentionally ignore fetch errors; the detail view can defer to the feed refresh.
            }
        }
    }

    static func makeLocationDescription(from location: DiscoveryLocation?) -> String? {
        guard let location else { return nil }
        if let closest = location.closestPlace {
            return closest
        }
        if let locality = location.locality, let country = location.country {
            return "\(locality), \(country)"
        }
        if let country = location.country {
            return country
        }
        return String(format: "%.4f, %.4f", location.latitude, location.longitude)
    }
}
