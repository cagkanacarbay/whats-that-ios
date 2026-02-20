import Combine
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
        case permissionDenied // Legacy - kept for compatibility
        case cameraPermissionDenied
        case photoLibraryPermissionDenied
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
            case .cameraPermissionDenied:
                return "To take photos of things you want to discover, allow camera access in Settings."
            case .photoLibraryPermissionDenied:
                return "To select photos from your library, allow photo access in Settings."
            case .captureFailed, .selectionFailed:
                return "We couldn't get that photo. Try again."
            case .encodingFailed:
                return "We had trouble preparing your photo for analysis."
            case .locationUnavailable:
                return "We couldn't access your location."
            case .noCredits:
                return "You need at least 1 credit to continue."
            case let .analysisFailed(message):
                return message
            }
        }

        var isPermissionError: Bool {
            switch self {
            case .permissionDenied, .cameraPermissionDenied, .photoLibraryPermissionDenied:
                return true
            default:
                return false
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
    /// Incremented each time a new analysis session begins, used to force view re-creation.
    @Published private(set) var analysisSessionId: Int = 0
    @Published private(set) var creditBalance: Int?
    @Published private(set) var error: FlowError?
    @Published private(set) var pushToken: String?
    @Published var showPollingFailedAlert: Bool = false
    @Published var showFreeCreditsExhaustedAtConfirm: Bool = false

    /// Audio generating modal to show after first discovery stream completes.
    @Published var showAudioGeneratingModal: Bool = false

    /// Whether to generate an audio guide for this discovery. Defaults to the user's global setting
    /// from VoiceoverPreferences but can be overridden per-discovery without affecting the global setting.
    @Published var generateAudioGuide: Bool = true

    /// Whether the user is in intro mode (audio toggle should be locked ON).
    @Published private(set) var isInIntroMode: Bool = true

    /// The most recently completed discovery summary. Set when streaming completes
    /// or when polling finds the completed discovery. Observed by MainTabView via .onReceive.
    @Published private(set) var completedDiscovery: DiscoverySummary?

    /// Set when the .complete stream event arrives with the discovery ID.
    /// Observed by MainTabView to start the summary fallback timer.
    @Published private(set) var createdDiscoveryId: Int64?

    // Note: Audio generation is now triggered exclusively via DiscoverySessionManager.onDiscoveryCompleted
    // (configured in MainTabView) rather than through a ViewModel callback.

    private let configuration: Configuration
    private let photoCaptureCoordinator: PhotoCaptureCoordinator
    private let streamingHandler: StreamingSessionHandler
    private let confirmationBuilder: ConfirmationStateBuilder
    private let creditBalanceStore: CreditBalanceStore
    private let imageEncoder: DiscoveryImageEncodingService
    private let locationService: DiscoveryLocationService
    private var cancellables = Set<AnyCancellable>()
    #if DEBUG
    private let debugLoggingEnabled = true
    #else
    private let debugLoggingEnabled = false
    #endif

    private var currentMedia: DiscoveryCapturedMedia?
    private var analysisTask: Task<Void, Never>?
    private var freshLocationForAnalysis: DiscoveryLocation?
    private var ephemeralFreshTask: Task<Void, Never>?
    private var ephemeralFreshInFlight = false

    var flowType: DiscoveryCreationFlowType {
        configuration.type
    }

    public init(
        configuration: Configuration,
        captureService: DiscoveryCaptureService,
        selectionService: DiscoverySelectionService,
        historyRepository: DiscoveryHistoryRepository,
        creditBalanceStore: CreditBalanceStore,
        imageEncoder: DiscoveryImageEncodingService,
        pushService: DiscoveryPushService,
        locationService: DiscoveryLocationService,
        voiceoverPreferencesStore: VoiceoverPreferencesStore? = nil,
        ipopPreferencesStore: IPoPPreferencesStore? = nil,
        photoSavePreferencesStore: PhotoSavePreferencesStore? = nil,
        photoLibrarySaveService: (any PhotoLibrarySaveServiceProtocol)? = nil
    ) {
        self.configuration = configuration
        self.photoCaptureCoordinator = PhotoCaptureCoordinator(
            captureService: captureService,
            selectionService: selectionService
        )
        self.streamingHandler = StreamingSessionHandler(
            historyRepository: historyRepository,
            creditBalanceStore: creditBalanceStore,
            photoSavePreferencesStore: photoSavePreferencesStore,
            photoLibrarySaveService: photoLibrarySaveService
        )
        self.confirmationBuilder = ConfirmationStateBuilder(
            locationService: locationService,
            creditBalanceStore: creditBalanceStore,
            historyRepository: historyRepository,
            pushService: pushService,
            voiceoverPreferencesStore: voiceoverPreferencesStore,
            ipopPreferencesStore: ipopPreferencesStore
        )
        self.creditBalanceStore = creditBalanceStore
        self.imageEncoder = imageEncoder
        self.locationService = locationService

        // Wire streaming handler
        streamingHandler.delegate = self
        streamingHandler.$analysisState
            .sink { [weak self] state in self?.analysisState = state }
            .store(in: &cancellables)

        // Wire confirmation builder
        confirmationBuilder.onConfirmationUpdated = { [weak self] state in
            self?.confirmationState = state
            if case .confirming = self?.flowState {
                self?.flowState = .confirming(state)
            }
        }
    }

    func startFlow(retake: Bool = false) {
        debugLog("startFlow(retake: \(retake))")
        guard canStartFlow(retake: retake) else {
            debugLog("startFlow blocked; currentState=\(flowStateSummary(flowState))")
            return
        }

        // Update flowState synchronously BEFORE scheduling async work to prevent race condition.
        // Without this, multiple startFlow() calls could pass the guard before the first
        // beginFlow() runs and updates the state, causing duplicate capturePhoto() calls.
        flowState = .requestingPermissions

        DispatchQueue.main.async { [weak self] in
            Task {
                await self?.beginFlow(retake: retake)
            }
        }
    }

    func cancelFlow() {
        debugLog("cancelFlow()")
        analysisTask?.cancel()
        analysisTask = nil
        ephemeralFreshTask?.cancel()
        ephemeralFreshTask = nil
        ephemeralFreshInFlight = false
        streamingHandler.cancel()
        confirmationBuilder.cancel()

        // Update flowState FIRST to remove the active view from hierarchy
        flowState = .cancelled

        // Then clear the state data
        confirmationState = nil
        currentMedia = nil
        freshLocationForAnalysis = nil
        error = nil

        // Finally reset to idle
        flowState = .idle
    }

    /// Unsubscribe from the current session and clean up local state.
    /// The session continues running in the background - only event forwarding stops.
    /// Call this when the modal closes mid-stream.
    func unsubscribe() {
        debugLog("unsubscribe()")
        streamingHandler.unsubscribe()

        // Cancel local tasks that are no longer needed
        analysisTask?.cancel()
        analysisTask = nil
        ephemeralFreshTask?.cancel()
        ephemeralFreshTask = nil
        ephemeralFreshInFlight = false

        // Update flowState FIRST to remove the active view from hierarchy
        flowState = .cancelled

        // Then clear the state data
        confirmationState = nil
        currentMedia = nil
        freshLocationForAnalysis = nil
        error = nil

        // Finally reset to idle
        flowState = .idle
    }

    func retake() {
        startFlow(retake: true)
    }

    /// Reconnects to an in-progress session from the Discoveries tab.
    /// Sets up UI state for the streaming view, then delegates to the handler
    /// which subscribes and receives replayed events.
    func attachToSession(sessionId: UUID, media: DiscoveryCapturedMedia) {
        debugLog("attachToSession(\(sessionId))")
        error = nil
        confirmationState = DiscoveryConfirmationState(
            media: media,
            displayImageData: media.data,
            isLocationPermissionGranted: false
        )
        currentMedia = media

        let initialState = DiscoveryAnalysisState(
            statusMessage: "Reconnecting…",
            streamedText: "",
            isStreaming: true
        )
        analysisSessionId += 1
        analysisState = initialState
        flowState = .analyzing(initialState)

        // Delegate to handler — events flow through existing handleSessionEvent path
        streamingHandler.attachToExistingSession(sessionId: sessionId, media: media)
    }

    /// Presents the camera or photo picker over the current streaming view.
    /// On cancel, returns silently — the streaming view stays unchanged.
    /// On success, unsubscribes from the old session and transitions to confirmation.
    func discoverMore(type: DiscoveryCreationFlowType) {
        debugLog("discoverMore(type: \(type))")

        Task { [weak self] in
            guard let self else { return }
            guard let result = await self.photoCaptureCoordinator.captureForDiscoverMore(type: type) else { return }
            switch result {
            case .captured(let media):
                await self.transitionToNewDiscovery(with: media)
            case .cancelled:
                self.debugLog("discoverMore: picker cancelled — returning to streaming view")
            case .permissionDenied(let type):
                self.error = type == .camera ? .cameraPermissionDenied : .photoLibraryPermissionDenied
            case .failed(let type):
                self.error = type == .camera ? .captureFailed : .selectionFailed
            }
        }
    }

    /// Cleans up the current session and transitions to confirmation with a new photo.
    /// Called from discoverMore after a successful capture/selection.
    private func transitionToNewDiscovery(with media: DiscoveryCapturedMedia) async {
        debugLog("transitionToNewDiscovery: unsubscribing from old session")

        // Unsubscribe from old session (continues in background)
        streamingHandler.unsubscribe()

        // Clear old state
        confirmationState = nil
        analysisTask?.cancel()
        analysisTask = nil
        ephemeralFreshTask?.cancel()
        ephemeralFreshTask = nil
        ephemeralFreshInFlight = false
        freshLocationForAnalysis = nil
        completedDiscovery = nil
        createdDiscoveryId = nil

        // Transition to confirmation with the new photo
        await prepareConfirmation(with: media)
    }

    func beginAnalysis() {
        debugLog("beginAnalysis()")
        // Once analysis begins, we don't block on ephemeral location.
        ephemeralFreshTask?.cancel()
        ephemeralFreshTask = nil
        guard case let .confirming(state) = flowState else { return }
        guard let media = currentMedia else {
            error = .captureFailed
            return
        }

        if let balance = creditBalance, balance <= 0 {
            error = .noCredits
            return
        }

        // Save photo to library if enabled (camera captures only)
        if configuration.type == .camera {
            Task { [weak self] in
                guard let self else { return }
                await self.streamingHandler.savePhotoIfEnabled(media: media)
            }
        }

        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.startAnalysisSession(media: media, confirmation: state)
        }
    }

    func clearError() {
        error = nil
    }

    // Re-check location permission when app returns to foreground and
    // update confirmation state accordingly.
    func refreshLocationPermissionOnForeground() {
        guard case .confirming = flowState else { return }

        Task { [weak self] in
            guard let self else { return }
            let granted = await self.confirmationBuilder.checkLocationPermission()
            await self.confirmationBuilder.applyPermission(granted: granted, flowType: self.flowType)
        }
    }

    func syncCreditBalance(_ newValue: Int?) async {
        creditBalance = await confirmationBuilder.syncCreditBalance(newValue)
        let tracker = FreeCreditsAlertTracker.shared
        isInIntroMode = await tracker.isInIntroMode
    }

    func refreshStateAfterCreditsSheet() async {
        let result = await confirmationBuilder.refreshAfterCreditsSheet()
        creditBalance = result.balance
        isInIntroMode = result.isIntroMode
        debugLog("refreshStateAfterCreditsSheet: balance=\(result.balance.map(String.init) ?? "nil"), isIntroMode=\(result.isIntroMode)")
    }

    private func beginFlow(retake: Bool) async {
        error = nil
        analysisTask?.cancel()
        analysisTask = nil
        analysisState = nil
        confirmationState = nil
        creditBalance = nil
        freshLocationForAnalysis = nil
        completedDiscovery = nil
        createdDiscoveryId = nil

        // For camera flow, start ephemeral location request before capture
        // (cross-cutting concern: consumed at confirmation + analysis)
        if configuration.type == .camera {
            startEphemeralLocationRequest()
        }

        // Set intermediate flowState for UI (spinner/placeholder)
        switch configuration.type {
        case .camera:
            flowState = retake ? .capturingRetake : .requestingPermissions
        case .upload:
            flowState = retake ? .selectingRetake : .requestingPermissions
        }

        let result = await photoCaptureCoordinator.capture(type: configuration.type)
        switch result {
        case .captured(let media):
            await prepareConfirmation(with: media)
        case .cancelled:
            self.error = nil
            flowState = .cancelled
            flowState = .idle
        case .permissionDenied(let type):
            debugLog("\(type) permission denied in beginFlow(retake: \(retake))")
            error = type == .camera ? .cameraPermissionDenied : .photoLibraryPermissionDenied
            // Don't set flowState to .idle — the error alert needs to present first.
            // The modal will dismiss after the user handles the alert (via cancelFlow).
        case .failed(let type):
            let flowError: FlowError = type == .camera ? .captureFailed : .selectionFailed
            error = flowError
            flowState = .error(message: flowError.errorDescription ?? "Failed")
        }
    }

    /// Starts a single ephemeral, high-accuracy fresh location request (up to 30s in background).
    /// Does not block UI; result is consumed at confirmation and analysis time.
    private func startEphemeralLocationRequest() {
        ephemeralFreshInFlight = true
        ephemeralFreshTask?.cancel()
        ephemeralFreshTask = Task { [weak self] in
            guard let self else { return }
            self.debugLog("Ephemeral fresh location request (30s) started")
            let fresh = await self.locationService.currentLocationStrictFreshEphemeral(timeout: 30)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.ephemeralFreshInFlight = false
                if let fresh {
                    self.freshLocationForAnalysis = fresh
                    self.debugLog("[EphemeralFresh] lat=\(fresh.latitude), lon=\(fresh.longitude)")
                    // If we are still on confirm, update coordinates without blocking.
                    if let existing = self.confirmationState {
                        let description = Self.makeLocationDescription(from: fresh)
                        self.confirmationState = DiscoveryConfirmationState(
                            media: existing.media,
                            displayImageData: existing.displayImageData,
                            creditBalance: existing.creditBalance,
                            location: fresh,
                            locationDescription: description,
                            isLocationPermissionGranted: existing.isLocationPermissionGranted,
                            isResolvingLocation: false,
                            customContext: existing.customContext,
                            nearbyPlaces: existing.nearbyPlaces,
                            nearbyPlacesContext: existing.nearbyPlacesContext
                        )
                        if case .confirming = self.flowState, let state = self.confirmationState {
                            self.flowState = .confirming(state)
                        }
                    }
                }
            }
        }
    }

    private func prepareConfirmation(with media: DiscoveryCapturedMedia) async {
        let result = await confirmationBuilder.build(
            media: media,
            flowType: flowType,
            freshLocation: freshLocationForAnalysis,
            recentHistoryLimit: configuration.recentHistoryLimit
        )
        confirmationState = result.state
        flowState = .confirming(result.state)
        currentMedia = media
        isInIntroMode = result.isIntroMode
        generateAudioGuide = result.generateAudio
        pushToken = result.pushToken
        creditBalance = result.creditBalance
        if result.showCreditsExhausted {
            showFreeCreditsExhaustedAtConfirm = true
            debugLog("Showing credits exhausted modal - intro discovery limit reached")
        }
    }

    /// Build the analysis payload and delegate streaming to the handler.
    private func startAnalysisSession(media: DiscoveryCapturedMedia, confirmation: DiscoveryConfirmationState) async {
        defer { analysisTask = nil }

        // Set initial analysis state and flow.
        // Use withAnimation so the confirming → analyzing view swap crossfades
        // instead of flashing the bare background for a frame.
        let initialState = DiscoveryAnalysisState(
            statusMessage: "Preparing analysis…",
            streamedText: "",
            isStreaming: true
        )
        withAnimation(.easeInOut(duration: 0.3)) {
            analysisSessionId += 1
            flowState = .analyzing(initialState)
        }

        // Optimistically decrement credits
        optimisticallyDecrementCredits()

        // Optimistically increment intro discovery count
        Task {
            await FreeCreditsAlertTracker.shared.incrementIntroDiscoveryCount()
        }

        // Build payload (stays in VM — bridges ephemeral location + confirmation)
        guard let payload = await buildAnalysisPayload(media: media, confirmation: confirmation) else {
            return // Error already handled in buildAnalysisPayload
        }

        // Delegate to streaming handler
        streamingHandler.startSession(
            payload: payload,
            media: media,
            generateAudioGuide: generateAudioGuide,
            flowType: configuration.type
        )
    }

    /// Builds the analysis payload, handling nearby places resolution and error cases.
    /// Returns nil if payload building fails (error state is set internally).
    private func buildAnalysisPayload(media: DiscoveryCapturedMedia, confirmation: DiscoveryConfirmationState) async -> DiscoveryAnalysisPayload? {
        do {
            // Deterministic confirm-stage path: if coordinates exist and nearby are missing,
            // ask locationService to prepare nearby and wait (bounded by config timeout).
            var effectiveConfirmation = confirmation
            if let coords = confirmation.location, (confirmation.nearbyPlaces == nil || confirmation.nearbyPlaces?.isEmpty == true) {
                if let selection = await locationService.prepareNearbyPlaces(for: coords) {
                    effectiveConfirmation = DiscoveryConfirmationState(
                        media: confirmation.media,
                        displayImageData: confirmation.displayImageData,
                        creditBalance: confirmation.creditBalance,
                        location: confirmation.location,
                        locationDescription: confirmation.locationDescription,
                        isLocationPermissionGranted: confirmation.isLocationPermissionGranted,
                        isResolvingLocation: confirmation.isResolvingLocation,
                        customContext: confirmation.customContext,
                        nearbyPlaces: selection.snapshot.places,
                        nearbyPlacesContext: selection.context
                    )
                    if case .confirming = self.flowState {
                        self.confirmationState = effectiveConfirmation
                        self.flowState = .confirming(effectiveConfirmation)
                    }
                }
            }
            let analysisLocation = self.freshLocationForAnalysis ?? effectiveConfirmation.location
            if let loc = analysisLocation {
                let source = (self.freshLocationForAnalysis != nil) ? "fresh" : "confirmation"
                debugLog("[ANALYSIS_LOC] source=\(source) lat=\(loc.latitude) lon=\(loc.longitude)")
            }
            return DiscoveryAnalysisPayload(
                base64Image: try await imageEncoder.makeBase64Payload(from: media, maxDimension: configuration.maxImageDimension),
                location: analysisLocation,
                customContext: effectiveConfirmation.customContext,
                pushToken: pushToken,
                nearbyPlaces: effectiveConfirmation.nearbyPlaces,
                nearbyPlacesContext: effectiveConfirmation.nearbyPlacesContext
            )
        } catch {
            debugLog("Error building payload: \(type(of: error)) - \(error.localizedDescription)")
            let message = (error as? FlowError)?.errorDescription ?? error.localizedDescription
            if StreamingSessionHandler.messageIndicatesInsufficientCredits(message) {
                handleCreditsExhaustedDuringAnalysis()
            } else {
                self.error = .analysisFailed(message)
                self.flowState = .error(message: message)

                // Refresh credits to ensure we aren't out of sync
                Task { [weak self] in
                    guard let self else { return }
                    if let updated = try? await self.creditBalanceStore.refresh() {
                        self.creditBalance = updated
                    }
                }
            }
            return nil
        }
    }

    /// Optimistically decrement credits when analysis begins.
    private func optimisticallyDecrementCredits() {
        Task { [weak self] in
            guard let self else { return }
            let adjusted = await self.creditBalanceStore.adjust(by: -1)
            self.creditBalance = adjusted
        }
    }

    /// Shared handler for credits exhausted during analysis (both payload error + streaming delegate).
    private func handleCreditsExhaustedDuringAnalysis() {
        Task { [weak self] in
            guard let self else { return }
            let updated = await self.creditBalanceStore.set(0)
            self.creditBalance = updated
            if let confirmState = self.confirmationState {
                self.flowState = .confirming(confirmState)
                self.showFreeCreditsExhaustedAtConfirm = true
            } else {
                self.error = .noCredits
                self.flowState = .error(message: FlowError.noCredits.errorDescription ?? "No credits")
            }
        }
    }

    func retryWithPendingMedia() {
        guard let media = streamingHandler.pendingMedia else { return }
        debugLog("Retrying with pending media")
        Task {
            await prepareConfirmation(with: media)
        }
    }

    // MARK: - Debug & Utilities

    private func debugLog(_ message: String) {
        guard debugLoggingEnabled else { return }
        // print("[DiscoveryCreationFlowViewModel] \(message)")
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

    private func canStartFlow(retake: Bool) -> Bool {
        switch flowState {
        case .idle, .cancelled, .error:
            return true
        case .confirming:
            return retake
        case .requestingPermissions, .capturingInitial, .capturingRetake,
             .selectingInitial, .selectingRetake, .analyzing:
            return false
        }
    }

    static func makeLocationDescription(from location: DiscoveryLocation?) -> String? {
        ConfirmationStateBuilder.makeLocationDescription(from: location)
    }
}

// MARK: - StreamingSessionDelegate Conformance

extension DiscoveryCreationFlowViewModel: StreamingSessionDelegate {
    func streamingDidCreateDiscovery(_ discoveryId: Int64) {
        createdDiscoveryId = discoveryId
    }

    func streamingDidCompleteDiscovery(_ summary: DiscoverySummary) {
        completedDiscovery = summary
    }

    func streamingDidFail(_ error: FlowError) {
        self.error = error
    }

    func streamingDidUpdateCreditBalance(_ balance: Int?) {
        creditBalance = balance
    }

    func streamingDidChangeFlowState(_ state: DiscoveryCreationFlowState) {
        flowState = state
    }

    func streamingShouldShowAudioModal() {
        showAudioGeneratingModal = true
    }

    func streamingShouldShowPollingFailedAlert() {
        showPollingFailedAlert = true
    }

    func streamingShouldReturnToConfirmation() {
        handleCreditsExhaustedDuringAnalysis()
    }
}
