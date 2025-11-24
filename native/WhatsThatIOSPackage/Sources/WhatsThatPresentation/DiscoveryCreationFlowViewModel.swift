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
    private let voiceoverRepository: (any DiscoveryVoiceoverRepository)?
    private let voiceoverPreferencesStore: VoiceoverPreferencesStore?
    private let analysisParser = DiscoveryAnalysisParser()
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
        creditsRepository: DiscoveryCreditsRepository,
        creditBalanceStore: CreditBalanceStore,
        analysisClient: DiscoveryAnalysisClient,
        imageEncoder: DiscoveryImageEncodingService,
        pushService: DiscoveryPushService,
        locationService: DiscoveryLocationService,
        voiceoverRepository: (any DiscoveryVoiceoverRepository)? = nil,
        voiceoverPreferencesStore: VoiceoverPreferencesStore? = nil
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
        self.voiceoverRepository = voiceoverRepository
        self.voiceoverPreferencesStore = voiceoverPreferencesStore
    }

    func startFlow(retake: Bool = false) {
        debugLog("startFlow(retake: \(retake))")
        guard canStartFlow(retake: retake) else {
            debugLog("startFlow blocked; currentState=\(flowStateSummary(flowState))")
            return
        }
        Task {
            await beginFlow(retake: retake)
        }
    }

    func cancelFlow() {
        debugLog("cancelFlow()")
        analysisTask?.cancel()
        analysisTask = nil
        ephemeralFreshTask?.cancel()
        ephemeralFreshTask = nil
        ephemeralFreshInFlight = false
        confirmationState = nil
        analysisState = nil
        currentMedia = nil
        freshLocationForAnalysis = nil
        flowState = .cancelled
        error = nil
        flowState = .idle
    }

    func retake() {
        startFlow(retake: true)
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

        onAnalysisBegan?(configuration.type)
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.performAnalysis(media: media, confirmation: state)
        }
    }

    func clearError() {
        error = nil
    }

    // Re-check location permission when app returns to foreground and
    // update confirmation state accordingly. If permission has just been
    // granted during the confirmation stage (camera flow), kick off
    // location resolution and update the UI badges.
    func refreshLocationPermissionOnForeground() {
        // Only relevant while confirming; no-op otherwise.
        guard case .confirming = flowState else { return }

        Task { [weak self] in
            guard let self else { return }
            let granted: Bool
            if let cached = LocationPermissionCache.shared.current {
                granted = cached
            } else {
                granted = await self.locationService.isPermissionGranted()
            }
            await self.apply(permissionGranted: granted)
        }
    }

    func syncCreditBalance(_ newValue: Int?) async {
        let normalized = await creditBalanceStore.set(newValue)
        creditBalance = normalized
    }

    private func beginFlow(retake: Bool) async {
        error = nil
        analysisTask?.cancel()
        analysisTask = nil
        analysisState = nil
        confirmationState = nil
        creditBalance = nil
        freshLocationForAnalysis = nil

        switch configuration.type {
        case .camera:
            flowState = retake ? .capturingRetake : .requestingPermissions
            let granted = await captureService.requestPermission(for: .camera)
            guard granted else {
                debugLog("Camera permission denied in beginFlow(retake: \(retake))")
                error = .permissionDenied
                flowState = .error(message: FlowError.permissionDenied.errorDescription ?? "Permission denied")
                return
            }
            // Do not (re)start continuous tracking here; app-wide tracking handles it.
            // We rely on a single ephemeral strict-fresh request instead.
            // Start a single ephemeral, high-accuracy fresh request that can run up to 30s in the background.
            // Do not block UI on this; use last-known immediately where possible.
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
                        print("[Prefetch][EphemeralFresh] lat=\(fresh.latitude), lon=\(fresh.longitude)")
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
            flowState = retake ? .capturingRetake : .capturingInitial
            do {
                debugLog("Invoking captureService.capturePhoto() (retake: \(retake))")
                let media = try await captureService.capturePhoto()
                debugLog("captureService.capturePhoto() completed successfully")
                await prepareConfirmation(with: media)
            } catch {
                if DiscoveryFlowCancellationError.isCancellation(error) {
                    self.error = nil
                    flowState = .cancelled
                    flowState = .idle
                    return
                }
                debugLog("captureService.capturePhoto() failed with error: \(error)")
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
                if DiscoveryFlowCancellationError.isCancellation(error) {
                    self.error = nil
                    flowState = .cancelled
                    flowState = .idle
                    return
                }
                self.error = .selectionFailed
                flowState = .error(message: FlowError.selectionFailed.errorDescription ?? "Selection failed")
            }
        }
    }

    private func apply(permissionGranted granted: Bool) async {
        // Update current confirmation snapshot with new permission value.
        guard var current = confirmationState else { return }
        let wasGranted = current.isLocationPermissionGranted
        if wasGranted == granted {
            return
        }

        current = DiscoveryConfirmationState(
            media: current.media,
            displayImageData: current.displayImageData,
            creditBalance: current.creditBalance,
            location: current.location,
            locationDescription: current.locationDescription,
            isLocationPermissionGranted: granted,
            isResolvingLocation: current.isResolvingLocation,
            customContext: current.customContext,
            nearbyPlaces: current.nearbyPlaces,
            nearbyPlacesContext: current.nearbyPlacesContext
        )
        confirmationState = current
        if case .confirming = flowState, let state = confirmationState {
            flowState = .confirming(state)
        }

        // If permission is newly granted during camera flow and we don't yet
        // have coordinates, start resolving and update the UI badge.
        if flowType == .camera, granted, current.location == nil {
            confirmationState = confirmationState.map { existing in
                DiscoveryConfirmationState(
                    media: existing.media,
                    displayImageData: existing.displayImageData,
                    creditBalance: existing.creditBalance,
                    location: existing.location,
                    locationDescription: existing.locationDescription,
                    isLocationPermissionGranted: existing.isLocationPermissionGranted,
                    isResolvingLocation: true,
                    customContext: existing.customContext,
                    nearbyPlaces: existing.nearbyPlaces,
                    nearbyPlacesContext: existing.nearbyPlacesContext
                )
            }
            if case .confirming = flowState, let state = confirmationState {
                flowState = .confirming(state)
            }

            // Resolve location and nearby places in background using a single ephemeral fresh request.
            Task { [weak self] in
                guard let self else { return }
                self.ephemeralFreshTask?.cancel()
                self.ephemeralFreshInFlight = true
                let resolved = await self.locationService.currentLocationStrictFreshEphemeral(timeout: 30)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.ephemeralFreshInFlight = false
                    guard let coords = resolved else { return }
                    let description = Self.makeLocationDescription(from: coords)
                    if let existing = self.confirmationState {
                        self.confirmationState = DiscoveryConfirmationState(
                            media: existing.media,
                            displayImageData: existing.displayImageData,
                            creditBalance: existing.creditBalance,
                            location: coords,
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

                if let coords = resolved, let selection = await self.locationService.prepareNearbyPlaces(for: coords) {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if let existing = self.confirmationState {
                            self.confirmationState = DiscoveryConfirmationState(
                                media: existing.media,
                                displayImageData: existing.displayImageData,
                                creditBalance: existing.creditBalance,
                                location: existing.location,
                                locationDescription: existing.locationDescription,
                                isLocationPermissionGranted: existing.isLocationPermissionGranted,
                                isResolvingLocation: existing.isResolvingLocation,
                                customContext: existing.customContext,
                                nearbyPlaces: selection.snapshot.places,
                                nearbyPlacesContext: selection.context
                            )
                            if case .confirming = self.flowState, let state = self.confirmationState {
                                self.flowState = .confirming(state)
                            }
                        }
                    }
                }
            }
        }
    }

    private func prepareConfirmation(with media: DiscoveryCapturedMedia) async {
        // Determine permission once (from cached snapshot if available) to avoid showing wrong badge state.
        let permissionNow: Bool
        if let cached = LocationPermissionCache.shared.current {
            permissionNow = cached
            debugLog("Using cached location permission: \(permissionNow)")
        } else {
            let granted = await locationService.isPermissionGranted()
            permissionNow = granted
            debugLog("Queried location permission: \(permissionNow)")
        }
        // Seed initial state based on flow type:
        // - uploads use EXIF immediately
        // - camera prefers ephemeral fresh (if already available), otherwise last-known if recent/accurate
        let initialLocation: DiscoveryLocation?
        switch flowType {
        case .upload:
            initialLocation = media.location
        case .camera:
            // Prefer the already-fetched ephemeral fresh if it arrived before confirm.
            if let fresh = freshLocationForAnalysis {
                initialLocation = fresh
            } else {
                // Try to use a recent last-known fix to avoid spinner.
                initialLocation = await locationService.currentLocationIfRecent(maxAge: 30, maxAccuracyMeters: 65)
            }
        }
        if let initialLocation {
            switch flowType {
            case .upload:
                print("[Confirm] Using EXIF coordinates for upload: lat=\(initialLocation.latitude), lon=\(initialLocation.longitude)")
            case .camera:
                if freshLocationForAnalysis != nil {
                    print("[Confirm] Using ephemeral coordinates for camera: lat=\(initialLocation.latitude), lon=\(initialLocation.longitude)")
                } else {
                    print("[Confirm] Using last-known coordinates for camera: lat=\(initialLocation.latitude), lon=\(initialLocation.longitude)")
                }
            }
        }
        let initialResolving: Bool = (flowType == .camera) && permissionNow && (initialLocation == nil)
        let initialConfirmationState = DiscoveryConfirmationState(
            media: media,
            displayImageData: media.data,
            creditBalance: nil,
            location: initialLocation,
            locationDescription: Self.makeLocationDescription(from: initialLocation),
            isLocationPermissionGranted: permissionNow,
            isResolvingLocation: initialResolving,
            customContext: nil,
            nearbyPlaces: nil,
            nearbyPlacesContext: nil
        )

        confirmationState = initialConfirmationState
        flowState = .confirming(initialConfirmationState)
        currentMedia = media

        // Debug: dump nearby cache state as we enter confirmation
        await locationService.debugLogNearbyState(current: initialLocation)

        // Ensure tracking is on for camera; uploads do not need live location.
        // Tracking is started at the beginning of the camera flow, so avoid starting again here.
        // (Keeps a single start point and prevents redundant calls.)
        // if flowType == .camera { await locationService.startTrackingIfNeeded() }

        // Load cached credits immediately and refresh in background.
        if let cached = await creditBalanceStore.getCached() {
            creditBalance = cached
        }

        // Confirm-stage: resolve a fresh location (shows spinner while pending)
        // For camera flow: do not issue an additional fresh request here; rely on the single
        // ephemeral request started at camera start. It will update confirmation when it arrives.

        // Kick off nearby-places using the initial seed location only; do not refetch after fresh fix arrives.
        if let seed = initialLocation {
            Task { [weak self] in
                guard let self else { return }
                if let selection = await self.locationService.prepareNearbyPlaces(for: seed) {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if let current = self.confirmationState {
                            self.confirmationState = DiscoveryConfirmationState(
                                media: current.media,
                                displayImageData: current.displayImageData,
                                creditBalance: current.creditBalance,
                                location: current.location,
                                locationDescription: current.locationDescription,
                                isLocationPermissionGranted: current.isLocationPermissionGranted,
                                isResolvingLocation: current.isResolvingLocation,
                                customContext: current.customContext,
                                nearbyPlaces: selection.snapshot.places,
                                nearbyPlacesContext: selection.context
                            )
                            if case .confirming = self.flowState, let state = self.confirmationState {
                                self.flowState = .confirming(state)
                            }
                        }
                    }
                }
            }
        }

        // For uploads with EXIF coordinates, pre-warm nearby immediately in background.
        if flowType == .upload, let exifLocation = media.location {
            Task { [weak self] in
                guard let self else { return }
                if let selection = await self.locationService.prepareNearbyPlaces(for: exifLocation) {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if let current = self.confirmationState {
                            self.confirmationState = DiscoveryConfirmationState(
                                media: current.media,
                                displayImageData: current.displayImageData,
                                creditBalance: current.creditBalance,
                                location: current.location,
                                locationDescription: current.locationDescription,
                                isLocationPermissionGranted: current.isLocationPermissionGranted,
                                isResolvingLocation: current.isResolvingLocation,
                                customContext: current.customContext,
                                nearbyPlaces: selection.snapshot.places,
                                nearbyPlacesContext: selection.context
                            )
                            if case .confirming = self.flowState, let state = self.confirmationState {
                                self.flowState = .confirming(state)
                            }
                        }
                    }
                }
            }
        }

        async let historyTask = historyRepository.fetchRecentDiscoveries(limit: configuration.recentHistoryLimit)
        async let pushTask = pushService.requestPushAuthorizationIfNeeded()

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

        // Preserve the previously computed location permission value.
        confirmationState = confirmationState.map { current in
            DiscoveryConfirmationState(
                media: current.media,
                displayImageData: current.displayImageData,
                creditBalance: creditBalance,
                location: current.location,
                locationDescription: current.locationDescription,
                isLocationPermissionGranted: current.isLocationPermissionGranted,
                isResolvingLocation: current.isResolvingLocation,
                customContext: current.customContext,
                nearbyPlaces: current.nearbyPlaces,
                nearbyPlacesContext: current.nearbyPlacesContext
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
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if case .confirming = self.flowState {
                            self.confirmationState = effectiveConfirmation
                            self.flowState = .confirming(effectiveConfirmation)
                        }
                    }
                }
            }
            let analysisLocation = self.freshLocationForAnalysis ?? effectiveConfirmation.location
            if let loc = analysisLocation {
                let source = (self.freshLocationForAnalysis != nil) ? "fresh" : "confirmation"
                print("[ANALYSIS_LOC] source=\(source) lat=\(loc.latitude) lon=\(loc.longitude)")
            } else {
                print("[ANALYSIS_LOC] source=none")
            }
            let payload = DiscoveryAnalysisPayload(
                base64Image: try await imageEncoder.makeBase64Payload(from: media, maxDimension: configuration.maxImageDimension),
                location: analysisLocation,
                customContext: effectiveConfirmation.customContext,
                pushToken: pushToken,
                nearbyPlaces: effectiveConfirmation.nearbyPlaces,
                nearbyPlacesContext: effectiveConfirmation.nearbyPlacesContext
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
            Task { [weak self] in
                guard let self,
                      let voiceoverRepository,
                      let preferencesStore = voiceoverPreferencesStore else { return }
                let preferences = await preferencesStore.load()
                guard preferences.autoEnabled, !preferences.voiceModelId.isEmpty else { return }
                _ = await voiceoverRepository.requestVoiceover(
                    for: discoveryId,
                    voiceModelId: preferences.voiceModelId,
                    ttsModel: preferences.ttsModel,
                    prosody: preferences.prosody
                )
            }
        case let .error(message, status):
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
        flowState = .idle
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

    private func syncFlowStateWithAnalysis() {
        if let analysisState {
            flowState = .analyzing(analysisState)
        }
    }

    private func canStartFlow(retake: Bool) -> Bool {
        switch flowState {
        case .idle, .cancelled, .error:
            return true
        case .confirming:
            // Allow retake from confirmation, but do not implicitly
            // start a new capture unless the user explicitly requests it.
            return retake
        case .requestingPermissions, .capturingInitial, .capturingRetake,
             .selectingInitial, .selectingRetake, .analyzing:
            return false
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
