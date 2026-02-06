import Foundation
import WhatsThatDomain
import WhatsThatShared

/// Builds and enriches the confirmation state for the discovery creation flow.
/// Handles location resolution, credit loading, nearby places, permissions, and history context.
@MainActor
final class ConfirmationStateBuilder {
    struct ConfirmationResult {
        let state: DiscoveryConfirmationState
        let isIntroMode: Bool
        let generateAudio: Bool
        let pushToken: String?
        let creditBalance: Int?
        let showCreditsExhausted: Bool
    }

    /// Called when background tasks (nearby places, location) update the confirmation state.
    var onConfirmationUpdated: ((DiscoveryConfirmationState) -> Void)?

    /// The current confirmation state being built/enriched.
    private(set) var currentState: DiscoveryConfirmationState?

    private let locationService: DiscoveryLocationService
    private let creditBalanceStore: CreditBalanceStore
    private let historyRepository: DiscoveryHistoryRepository
    private let pushService: DiscoveryPushService
    private let voiceoverPreferencesStore: VoiceoverPreferencesStore?
    private let ipopPreferencesStore: IPoPPreferencesStore?

    private var nearbyTask: Task<Void, Never>?
    private var locationResolutionTask: Task<Void, Never>?

    init(
        locationService: DiscoveryLocationService,
        creditBalanceStore: CreditBalanceStore,
        historyRepository: DiscoveryHistoryRepository,
        pushService: DiscoveryPushService,
        voiceoverPreferencesStore: VoiceoverPreferencesStore?,
        ipopPreferencesStore: IPoPPreferencesStore?
    ) {
        self.locationService = locationService
        self.creditBalanceStore = creditBalanceStore
        self.historyRepository = historyRepository
        self.pushService = pushService
        self.voiceoverPreferencesStore = voiceoverPreferencesStore
        self.ipopPreferencesStore = ipopPreferencesStore
    }

    /// Build initial confirmation state and kick off async enrichment.
    func build(
        media: DiscoveryCapturedMedia,
        flowType: DiscoveryCreationFlowType,
        freshLocation: DiscoveryLocation?,
        recentHistoryLimit: Int
    ) async -> ConfirmationResult {
        // Determine permission once
        let permissionNow: Bool
        if let cached = LocationPermissionCache.shared.current {
            permissionNow = cached
        } else {
            permissionNow = await locationService.isPermissionGranted()
        }

        // Seed initial location
        let initialLocation: DiscoveryLocation?
        switch flowType {
        case .upload:
            initialLocation = media.location
        case .camera:
            if let fresh = freshLocation {
                initialLocation = fresh
            } else {
                initialLocation = await locationService.currentLocationIfRecent(maxAge: 30, maxAccuracyMeters: 65)
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

        currentState = initialConfirmationState

        // Check intro mode state
        let tracker = FreeCreditsAlertTracker.shared
        let isIntroMode = await tracker.isInIntroMode

        // Load audio guide preference
        let generateAudio: Bool
        if isIntroMode {
            generateAudio = true
        } else if let store = voiceoverPreferencesStore {
            let prefs = await store.load()
            generateAudio = prefs.autoEnabled
        } else {
            generateAudio = true
        }

        // Debug: dump nearby cache state
        await locationService.debugLogNearbyState(current: initialLocation)

        // Load cached credits
        var creditBalance: Int? = nil
        if let cached = await creditBalanceStore.getCached() {
            creditBalance = cached
        }

        // Kick off nearby-places in background
        if let seed = initialLocation {
            kickOffNearbyPlaces(for: seed)
        }

        // For uploads with EXIF coordinates, also pre-warm nearby
        if flowType == .upload, let exifLocation = media.location {
            kickOffNearbyPlaces(for: exifLocation)
        }

        // Concurrent tasks: history + ipop preferences
        async let historyTask = historyRepository.fetchRecentDiscoveries(limit: recentHistoryLimit)
        let ipopPreferences = await ipopPreferencesStore?.load()

        // Conditional permission requests
        if flowType == .camera {
            await requestLocationPermissionIfNeeded()
        }
        await requestNotificationPermissionIfNeeded()

        // Get push token
        var pushToken: String? = nil
        do {
            pushToken = try await pushService.getPushTokenIfAuthorized()
        } catch {
            pushToken = nil
        }

        // Refresh credits if stale
        do {
            let balance = try await creditBalanceStore.refreshIfStale()
            creditBalance = balance
        } catch {
            // Keep existing cached value
        }

        // Build context from history
        do {
            let discoveries = try await historyTask
            let contextBuilder = DiscoveryContextBuilder()
            currentState?.customContext = contextBuilder.buildContext(
                from: discoveries,
                limit: recentHistoryLimit,
                ipopPreferences: ipopPreferences,
                imageSource: flowType.rawValue
            )
        } catch {
            currentState?.customContext = nil
        }

        // Update state with final credit balance
        currentState = currentState.map { current in
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

        // Check intro discovery limit
        let showCreditsExhausted = await tracker.shouldShowCreditsExhaustedForIntroLimit()

        return ConfirmationResult(
            state: currentState!,
            isIntroMode: isIntroMode,
            generateAudio: generateAudio,
            pushToken: pushToken,
            creditBalance: creditBalance,
            showCreditsExhausted: showCreditsExhausted
        )
    }

    /// Apply updated location permission. May kick off background location resolution.
    func applyPermission(granted: Bool, flowType: DiscoveryCreationFlowType) async {
        guard var current = currentState else { return }
        let wasGranted = current.isLocationPermissionGranted
        if wasGranted == granted { return }

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
        currentState = current
        onConfirmationUpdated?(current)

        // If permission newly granted during camera flow and no coords yet, resolve location
        if flowType == .camera, granted, current.location == nil {
            currentState = currentState.map { existing in
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
            if let state = currentState {
                onConfirmationUpdated?(state)
            }

            locationResolutionTask?.cancel()
            locationResolutionTask = Task { [weak self] in
                guard let self else { return }
                let resolved = await self.locationService.currentLocationStrictFreshEphemeral(timeout: 30)
                guard !Task.isCancelled else { return }

                if let coords = resolved {
                    let description = Self.makeLocationDescription(from: coords)
                    if let existing = self.currentState {
                        self.currentState = DiscoveryConfirmationState(
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
                        if let state = self.currentState {
                            self.onConfirmationUpdated?(state)
                        }
                    }
                }

                if let coords = resolved, let selection = await self.locationService.prepareNearbyPlaces(for: coords) {
                    if let existing = self.currentState {
                        self.currentState = DiscoveryConfirmationState(
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
                        if let state = self.currentState {
                            self.onConfirmationUpdated?(state)
                        }
                    }
                }
            }
        }
    }

    /// Sync credit balance.
    func syncCreditBalance(_ newValue: Int?) async -> Int? {
        await creditBalanceStore.set(newValue)
    }

    /// Refresh credits and intro mode after credits sheet closes.
    func refreshAfterCreditsSheet() async -> (balance: Int?, isIntroMode: Bool) {
        var balance: Int?
        do {
            balance = try await creditBalanceStore.refresh(force: true)
        } catch {
            balance = await creditBalanceStore.getCached()
        }

        let tracker = FreeCreditsAlertTracker.shared
        let isIntroMode = await tracker.isInIntroMode
        return (balance: balance, isIntroMode: isIntroMode)
    }

    /// Check current location permission.
    func checkLocationPermission() async -> Bool {
        if let cached = LocationPermissionCache.shared.current {
            return cached
        }
        return await locationService.isPermissionGranted()
    }

    /// Cancel in-flight background tasks.
    func cancel() {
        nearbyTask?.cancel()
        nearbyTask = nil
        locationResolutionTask?.cancel()
        locationResolutionTask = nil
        currentState = nil
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

    // MARK: - Private

    private func kickOffNearbyPlaces(for location: DiscoveryLocation) {
        nearbyTask = Task { [weak self] in
            guard let self else { return }
            if let selection = await self.locationService.prepareNearbyPlaces(for: location) {
                if let current = self.currentState {
                    self.currentState = DiscoveryConfirmationState(
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
                    if let state = self.currentState {
                        self.onConfirmationUpdated?(state)
                    }
                }
            }
        }
    }

    private func requestLocationPermissionIfNeeded() async {
        let tracker = FreeCreditsAlertTracker.shared
        let cameraCount = await tracker.cameraUseCount
        let hasRequested = await tracker.hasRequestedLocationPermission

        guard cameraCount >= 2, !hasRequested else { return }

        let isGranted = await locationService.isPermissionGranted()
        guard !isGranted else { return }

        await tracker.markLocationPermissionRequested()
        await locationService.requestLocationAuthorization()
        await locationService.startTrackingIfNeeded()
        print("[Permissions] Requesting location permission (camera use #\(cameraCount))")
    }

    private func requestNotificationPermissionIfNeeded() async {
        let tracker = FreeCreditsAlertTracker.shared
        let hasPurchased = await tracker.hasMadePurchase
        let hasRequested = await tracker.hasRequestedNotificationPermission

        guard hasPurchased, !hasRequested else { return }

        await tracker.markNotificationPermissionRequested()
        _ = try? await pushService.requestPushAuthorizationIfNeeded()
        print("[Permissions] Requesting notification permission (post-purchase)")
    }
}
