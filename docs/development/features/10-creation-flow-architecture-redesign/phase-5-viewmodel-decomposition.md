# Phase 5: Break Up DiscoveryCreationFlowViewModel

**Status: DONE (2026-02-06)**

## Context

The `DiscoveryCreationFlowViewModel` (~1560 lines) is a god-ViewModel handling the entire discovery creation lifecycle: photo capture, confirmation assembly, analysis streaming, polling fallback, credits, location, and permissions. Phases 1-4 cleaned up the view layer and extracted `CreationFlowCoordinator` for modal lifecycle, but the VM itself remains monolithic. Phase 5 decomposes it into focused helpers while keeping the VM as the single `@ObservableObject` surface — **no view changes needed**.

## Design Approach: Internal Delegation

Each extracted component is a plain `@MainActor` class (not ObservableObject). The VM owns them, delegates work to them, and remains the sole publisher of `@Published` state. Views continue observing a single VM.

```
DiscoveryCreationFlowViewModel (orchestrator, ~350-400 lines)
  ├── PhotoCaptureCoordinator (~150 lines)
  ├── ConfirmationStateBuilder (~350 lines)
  └── StreamingSessionHandler (~350 lines)
```

### Communication Patterns

Two different patterns based on frequency:

- **Continuous state** (analysisState — updated every token): `@Published` on the handler, bridged via a single Combine subscription in the VM.
- **Discrete events** (completion, error, audio modal, polling alert): Delegate protocol on StreamingSessionHandler. Callbacks on ConfirmationStateBuilder (only 2 needed).

This avoids the 9-closure anti-pattern (same coupling problem inverted) while keeping the wiring clean.

## Files to Create

| File | Location |
|------|----------|
| `PhotoCaptureCoordinator.swift` | `Features/DiscoveryCreation/Coordinators/` |
| `ConfirmationStateBuilder.swift` | `Features/DiscoveryCreation/Coordinators/` |
| `StreamingSessionHandler.swift` | `Features/DiscoveryCreation/Coordinators/` |

## Files to Modify

| File | Change |
|------|--------|
| `DiscoveryCreationFlowViewModel.swift` | Slim down from ~1560 to ~350-400 lines; delegate to helpers |
| `DiscoveryCreationFlowViewModelTests.swift` | Existing tests pass unchanged; add focused tests for extracted components |

## No Changes Needed (view layer stays untouched)

- `DiscoveryCreationFlowView.swift`
- `DiscoveryStreamingStageView.swift`
- `MainTabView.swift`
- `CreationFlowCoordinator.swift`
- `RootContentView.swift`

---

## Step 1: Extract PhotoCaptureCoordinator

**Cleanest boundary — no shared mutable state with other clusters.**

### What moves

| From VM | To PhotoCaptureCoordinator |
|---------|---------------------------|
| Permission request logic from `beginFlow()` (lines 463-556) | `capture(type:) async -> CaptureResult` |
| Permission + capture logic from `discoverMore()` (lines 288-333) | `captureForDiscoverMore(type:) async -> CaptureResult` |
| `captureService` / `selectionService` dependencies | Stored properties |
| `isDiscoveringMore` guard (line 149) | Internal state |
| `FreeCreditsAlertTracker.incrementCameraUseCount()` calls | Called internally after successful camera capture |

### Interface

```swift
@MainActor
final class PhotoCaptureCoordinator {
    enum CaptureResult {
        case captured(DiscoveryCapturedMedia)
        case cancelled
        case permissionDenied(DiscoveryCreationFlowType)
        case failed(DiscoveryCreationFlowType)
    }

    init(captureService: DiscoveryCaptureService, selectionService: DiscoverySelectionService)

    /// Main capture flow — requests permission then invokes camera/picker.
    func capture(type: DiscoveryCreationFlowType) async -> CaptureResult

    /// "Discover More" capture — guards against double invocation.
    /// Returns nil if already in progress (guard tripped).
    func captureForDiscoverMore(type: DiscoveryCreationFlowType) async -> CaptureResult?
}
```

### VM becomes

```swift
// beginFlow() shrinks to:
private func beginFlow(retake: Bool) async {
    resetStateForNewFlow()

    if configuration.type == .camera {
        startEphemeralLocationRequest()  // stays in VM — cross-cutting
        flowState = retake ? .capturingRetake : .capturingInitial
    } else {
        flowState = retake ? .selectingRetake : .selectingInitial
    }

    let result = await photoCaptureCoordinator.capture(type: configuration.type)
    switch result {
    case .captured(let media):
        await prepareConfirmation(with: media)
    case .cancelled:
        flowState = .cancelled; flowState = .idle
    case .permissionDenied(let type):
        error = type == .camera ? .cameraPermissionDenied : .photoLibraryPermissionDenied
    case .failed(let type):
        error = type == .camera ? .captureFailed : .selectionFailed
        flowState = .error(message: error!.errorDescription ?? "Failed")
    }
}

// discoverMore() shrinks to:
func discoverMore(type: DiscoveryCreationFlowType) {
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
```

### What stays in VM

- `flowState` transitions (`.requestingPermissions`, `.capturingInitial`, etc.)
- Ephemeral location kickoff (cross-cutting concern — started at capture, consumed at confirmation+analysis)
- `currentMedia` storage (needed by streaming handler later)
- `transitionToNewDiscovery(with:)` — orchestrates session cleanup + confirmation transition

### Build & test checkpoint
- Build project
- Run existing tests (should pass unchanged)
- Manual test: camera capture, gallery upload, cancel flows, discoverMore from streaming

---

## Step 2: Extract StreamingSessionHandler

**Second cleanest — clear input/output boundary with delegate protocol.**

### What moves

| From VM | To StreamingSessionHandler |
|---------|---------------------------|
| `startAnalysisSession()` (lines 910-1031) | `startSession(payload:media:generateAudioGuide:) async` |
| `handle(event:)` (lines 1033-1107) | Internal event processing |
| `analysisStateUpdated()` (lines 1260-1304) | Internal state mutation |
| `DiscoverySessionSubscriber` conformance (lines 1431-1521) | Conforms to protocol directly |
| `startPollingForCompletion()` (lines 1111-1142) | Internal polling |
| `checkForCompletedDiscovery()` (lines 1144-1163) | Internal polling |
| `handlePollingDiscoveryReady()` (lines 1165-1190) | Internal |
| `handlePollingTimeout()` (lines 1192-1209) | Calls delegate method |
| `handleSuccessfulCreation()` (lines 1212-1245) | Internal, calls delegate |
| `cacheDiscoveryImageIfNeeded()` (lines 1376-1414) | Internal |
| `savePhotoToLibraryIfEnabled()` (lines 1527-1558) | Internal |
| `analysisParser` (line 116) | Internal dependency |
| `analysisTask`, `pollingTask`, `pendingMedia`, `analysisStartTime`, `currentSessionId` | Internal state |
| `messageIndicatesInsufficientCredits()` (line 1255) | Static helper on handler |
| `debugPollingAlwaysFails`, `debugUseShortPollingIntervals` debug flags | Static on handler |

### Delegate Protocol

```swift
/// Discrete events from StreamingSessionHandler → VM.
/// The VM conforms to this protocol to receive completion, error, and UI trigger events.
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
```

### Interface

```swift
@MainActor
final class StreamingSessionHandler: DiscoverySessionSubscriber {
    /// Continuous state — VM bridges to its @Published via Combine subscription.
    @Published private(set) var analysisState: DiscoveryAnalysisState?

    /// Delegate for discrete events (completion, error, UI triggers).
    weak var delegate: StreamingSessionDelegate?

    init(
        historyRepository: DiscoveryHistoryRepository,
        creditBalanceStore: CreditBalanceStore,
        photoSavePreferencesStore: PhotoSavePreferencesStore?,
        photoLibrarySaveService: (any PhotoLibrarySaveServiceProtocol)?
    )

    /// Start analysis with the given payload. Subscribes to session manager.
    func startSession(
        payload: DiscoveryAnalysisPayload,
        media: DiscoveryCapturedMedia,
        generateAudioGuide: Bool,
        flowType: DiscoveryCreationFlowType
    ) async

    /// Save photo to library if enabled (camera captures only).
    func savePhotoIfEnabled(media: DiscoveryCapturedMedia) async

    /// Unsubscribe from session (stream continues in background).
    func unsubscribe()

    /// Cancel all tasks and clean up.
    func cancel()

    /// Media from the last analysis start (for retry).
    var pendingMedia: DiscoveryCapturedMedia? { get }

    /// Current session ID (for unsubscribing during discoverMore transition).
    var currentSessionId: UUID? { get }
}
```

### VM becomes

```swift
// In init — wire delegate + Combine subscription:
streamingHandler.delegate = self
streamingHandler.$analysisState
    .sink { [weak self] state in self?.analysisState = state }
    .store(in: &cancellables)

// beginAnalysis() shrinks to:
func beginAnalysis() {
    guard case let .confirming(state) = flowState, let media = currentMedia else { return }
    guard (creditBalance ?? 0) > 0 else { error = .noCredits; return }

    // Save photo if enabled (fire and forget)
    if configuration.type == .camera {
        Task { await streamingHandler.savePhotoIfEnabled(media: media) }
    }

    // Build payload (stays in VM — bridges confirmation + streaming)
    Task {
        let payload = await buildAnalysisPayload(media: media, confirmation: state)

        // Optimistic credit decrement + intro count
        await optimisticallyDecrementCredits()

        // Initial analysis state
        let initialState = DiscoveryAnalysisState(
            statusMessage: "Preparing analysis…", streamedText: "", isStreaming: true
        )
        flowState = .analyzing(initialState)

        // Delegate to handler
        await streamingHandler.startSession(
            payload: payload, media: media,
            generateAudioGuide: generateAudioGuide, flowType: configuration.type
        )
    }
}

// VM conforms to StreamingSessionDelegate:
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
```

### Credits-exhausted shared helper

The "return to confirmation on credits exhausted" logic appears in both the VM (payload building error in `buildAnalysisPayload`) and the StreamingSessionHandler (stream error + session failure). Extract a shared handler in the VM:

```swift
/// Called from both buildAnalysisPayload error handling and StreamingSessionDelegate.
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
```

The handler calls `delegate?.streamingShouldReturnToConfirmation()` which routes to this shared method. The VM's payload error path calls it directly. No duplication.

### Payload building stays in VM

The `buildAnalysisPayload()` method stays in the VM orchestrator since it reads `freshLocationForAnalysis` (ephemeral location from capture phase), `confirmationState`, `pushToken`, and calls `imageEncoder` — it bridges confirmation and streaming. The `imageEncoder` dependency stays in VM for this reason.

### Build & test checkpoint
- Build project
- Run existing tests (should pass unchanged)
- Add `StreamingSessionHandlerTests` — test event handling, polling, completion delegate calls
- Manual test: full analysis flow, stream interruption → polling, credits exhausted mid-analysis

---

## Step 3: Extract ConfirmationStateBuilder

**Most intertwined — handles location, credits, nearby, permissions, history context.**

### Design Decision: Ephemeral location stays in VM

The ephemeral fresh location request starts in `beginFlow()` *before the photo is captured* (camera path) and resolves asynchronously during capture + confirmation. It's a cross-cutting concern consumed at analysis time. Moving it to the builder would create a misleading lifecycle (builder doing work before the confirmation exists). It's only ~35 lines and stays in the VM as the bridge between capture and analysis.

The builder receives the already-resolved `freshLocationForAnalysis` as a parameter to `build()` for the initial seed, and the VM updates confirmation state directly when the ephemeral request completes (same as current behavior).

### What moves

| From VM | To ConfirmationStateBuilder |
|---------|----------------------------|
| `prepareConfirmation(with:)` (lines 702-906) | `build(media:flowType:freshLocation:) async -> ConfirmationResult` |
| `requestLocationPermissionIfNeeded()` (lines 564-582) | Internal |
| `requestNotificationPermissionIfNeeded()` (lines 586-597) | Internal |
| `apply(permissionGranted:)` (lines 599-700) | `applyPermission(granted:) async` (updates internal state, calls `onConfirmationUpdated`) |
| `syncCreditBalance()` (lines 419-422) | `syncCreditBalance(_ newValue:) async -> Int?` |
| `refreshStateAfterCreditsSheet()` (lines 424-445) | `refreshAfterCreditsSheet() async -> (balance: Int?, isIntroMode: Bool)` |
| `locationService`, `creditBalanceStore`, `historyRepository`, `pushService`, `voiceoverPreferencesStore`, `ipopPreferencesStore` | Stored dependencies |
| `makeLocationDescription()` static helper (lines 1416-1428) | Static method on builder |

### What does NOT move (stays in VM)

| Stays in VM | Reason |
|-------------|--------|
| `freshLocationForAnalysis`, `ephemeralFreshTask`, `ephemeralFreshInFlight` | Cross-cutting concern spanning capture→confirmation→analysis |
| `startEphemeralLocationRequest()` logic (~35 lines) | Called from `beginFlow()` before confirmation exists |
| `refreshLocationPermissionOnForeground()` | Thin wrapper — calls builder, updates VM state |

### Interface

```swift
@MainActor
final class ConfirmationStateBuilder {
    /// Called when background tasks (nearby places, location) update the confirmation state.
    var onConfirmationUpdated: ((DiscoveryConfirmationState) -> Void)?

    init(
        locationService: DiscoveryLocationService,
        creditBalanceStore: CreditBalanceStore,
        historyRepository: DiscoveryHistoryRepository,
        pushService: DiscoveryPushService,
        voiceoverPreferencesStore: VoiceoverPreferencesStore?,
        ipopPreferencesStore: IPoPPreferencesStore?
    )

    /// Build initial confirmation state and kick off async enrichment (credits, nearby, permissions).
    /// `freshLocation` is the ephemeral location from the VM (may be nil if not yet resolved).
    func build(
        media: DiscoveryCapturedMedia,
        flowType: DiscoveryCreationFlowType,
        freshLocation: DiscoveryLocation?,
        recentHistoryLimit: Int
    ) async -> ConfirmationResult

    struct ConfirmationResult {
        let state: DiscoveryConfirmationState
        let isIntroMode: Bool
        let generateAudio: Bool
        let pushToken: String?
        let creditBalance: Int?
        let showCreditsExhausted: Bool
    }

    /// Apply updated location permission to current confirmation state.
    /// May kick off background location resolution + nearby places.
    /// Updates flow through onConfirmationUpdated callback.
    func applyPermission(granted: Bool) async

    /// Refresh credits and intro mode after credits sheet closes.
    func refreshAfterCreditsSheet() async -> (balance: Int?, isIntroMode: Bool)

    /// Sync credit balance (called from onBalanceUpdated callback).
    func syncCreditBalance(_ newValue: Int?) async -> Int?

    /// The current confirmation state being built/enriched.
    private(set) var currentState: DiscoveryConfirmationState?

    /// Cancel in-flight background tasks (nearby resolution, etc.).
    func cancel()

    static func makeLocationDescription(from location: DiscoveryLocation?) -> String?
}
```

### VM becomes

```swift
// prepareConfirmation shrinks to:
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
    }
}

// Thin forwarding methods (views call these on the VM):
func syncCreditBalance(_ newValue: Int?) async {
    creditBalance = await confirmationBuilder.syncCreditBalance(newValue)
}

func refreshStateAfterCreditsSheet() async {
    let result = await confirmationBuilder.refreshAfterCreditsSheet()
    creditBalance = result.balance
    isInIntroMode = result.isIntroMode
}

func refreshLocationPermissionOnForeground() {
    guard case .confirming = flowState else { return }
    Task { [weak self] in
        guard let self else { return }
        await self.confirmationBuilder.applyPermission(
            granted: await self.confirmationBuilder.checkLocationPermission()
        )
        // confirmationBuilder calls onConfirmationUpdated which updates VM state
    }
}
```

### Wiring (in VM init)

Only 1 callback needed (vs StreamingSessionHandler's delegate protocol):

```swift
confirmationBuilder.onConfirmationUpdated = { [weak self] state in
    self?.confirmationState = state
    if case .confirming = self?.flowState {
        self?.flowState = .confirming(state)
    }
}
```

### Build & test checkpoint
- Build project
- Run existing tests (should pass unchanged)
- Add `ConfirmationStateBuilderTests` — test location resolution, credit loading, intro mode, nearby places
- Manual test: camera with location, upload with EXIF, credits exhausted at confirm, foreground return

---

## Step 4: Final Cleanup — Slim Down VM to Orchestrator

After steps 1-3, the VM should be ~350-400 lines.

### What remains in VM

**Types & Properties (~95 lines)**
- `Configuration` struct
- `FlowError` enum (kept for public API — views reference it for alerts)
- All `@Published` properties (15 — VM is still the single observable surface)

**Init & Wiring (~50 lines)**
- `init()` — creates the 3 helpers, sets `streamingHandler.delegate = self`, wires Combine subscription + `confirmationBuilder.onConfirmationUpdated` callback
- `private var cancellables = Set<AnyCancellable>()`

**Orchestration Methods (~120 lines)**
- `startFlow()` / `beginFlow()` — orchestration skeleton with capture delegation
- `cancelFlow()` / `unsubscribe()` — delegates to all 3 helpers + resets state
- `discoverMore()` — delegates capture to coordinator, handles session cleanup + confirmation
- `transitionToNewDiscovery(with:)` — session cleanup + confirmation transition
- `beginAnalysis()` — bridges confirmation → streaming
- `buildAnalysisPayload()` — bridges ephemeral location + confirmation with streaming handler
- `optimisticallyDecrementCredits()` — credit adjustment on analysis start
- `retake()` / `retryWithPendingMedia()` / `clearError()`
- `canStartFlow()` guard logic

**Ephemeral Location (~35 lines)**
- `freshLocationForAnalysis`, `ephemeralFreshTask`, `ephemeralFreshInFlight`
- Ephemeral request start + completion handler that updates confirmation state

**Forwarding Methods (~20 lines)**
- `syncCreditBalance(_:)` → builder
- `refreshStateAfterCreditsSheet()` → builder
- `refreshLocationPermissionOnForeground()` → builder

**StreamingSessionDelegate Conformance (~25 lines)**
- 8 protocol methods, each 1-3 lines

**Shared Helpers (~15 lines)**
- `handleCreditsExhaustedDuringAnalysis()` — shared by payload error + delegate callback
- `resetStateForNewFlow()` — consolidated state reset

**Debug (~20 lines)**
- `flowStateSummary()`, `debugLog()`, `debugLoggingEnabled`

### What each helper owns

| Helper | Lines | Dependencies | Communication |
|--------|-------|-------------|---------------|
| `PhotoCaptureCoordinator` | ~150 | captureService, selectionService | Return values (CaptureResult enum) |
| `StreamingSessionHandler` | ~350 | historyRepository, creditBalanceStore, photoSave* | @Published analysisState + delegate protocol |
| `ConfirmationStateBuilder` | ~350 | locationService, creditBalanceStore, historyRepository, pushService, voiceover*, ipop* | Return values + 1 callback |

---

## Implementation Strategy

### Single Pass (not separate PRs)

Since we're on a feature branch, all three extractions happen in sequence in a single implementation pass:

1. Extract `PhotoCaptureCoordinator` → build + test
2. Extract `StreamingSessionHandler` → build + test
3. Extract `ConfirmationStateBuilder` → build + test
4. Final cleanup → build + test
5. Full manual regression

Each step must compile and pass tests before proceeding to the next. If step N breaks something, fix it before starting step N+1.

### Dependency Distribution After Extraction

Current VM init takes 15 dependencies. After extraction:

| Dependency | Goes to |
|-----------|---------|
| `captureService` | PhotoCaptureCoordinator |
| `selectionService` | PhotoCaptureCoordinator |
| `historyRepository` | ConfirmationStateBuilder + StreamingSessionHandler (shared) |
| `creditsRepository` | *(unused after Phase 3 — verify and remove)* |
| `creditBalanceStore` | ConfirmationStateBuilder + StreamingSessionHandler (shared) |
| `analysisClient` | *(unused — session manager owns the stream)* |
| `imageEncoder` | VM (for buildAnalysisPayload) |
| `pushService` | ConfirmationStateBuilder |
| `locationService` | ConfirmationStateBuilder + VM (ephemeral location) |
| `voiceoverRepository` | StreamingSessionHandler (for cacheDiscoveryImage TTS path) |
| `voiceoverPreferencesStore` | ConfirmationStateBuilder |
| `ipopPreferencesStore` | ConfirmationStateBuilder |
| `photoSavePreferencesStore` | StreamingSessionHandler |
| `photoLibrarySaveService` | StreamingSessionHandler |

Note: `historyRepository` and `creditBalanceStore` are needed by both ConfirmationStateBuilder and StreamingSessionHandler. The VM creates both helpers with the same instance — no duplication, just shared references.

Verify whether `creditsRepository` and `analysisClient` are still used. If not (session manager took over), remove from VM init.

## Testing Strategy

### Existing tests pass unchanged

The 3 existing VM tests (`testBeginAnalysisStreamsAndCompletes`, `testUploadCancellationReturnsToIdleState`, `testCameraCancellationReturnsToIdleState`) exercise the full flow through the VM orchestrator. They must continue passing without modification — the VM's public API hasn't changed.

Note: `testBeginAnalysisStreamsAndCompletes` is a pre-existing failure (session manager singleton not configured in tests). Don't regress it further; don't block on fixing it.

### New focused tests for extracted components

Each component is testable with fewer stubs (3-5 instead of 15):

**PhotoCaptureCoordinatorTests**
- Camera permission granted → capture succeeds → returns `.captured(media)`
- Camera permission denied → returns `.permissionDenied(.camera)`
- Photo picker cancelled → returns `.cancelled`
- Gallery permission denied → returns `.permissionDenied(.upload)`
- `captureForDiscoverMore` double-invocation guard → returns `nil`
- Dependencies: only `captureService` + `selectionService` stubs

**StreamingSessionHandlerTests**
- Event handling: `.token` → updates analysisState
- Event handling: `.metadata` → updates title/shortDescription
- Event handling: `.complete` → calls `delegate.streamingDidCreateDiscovery` + `streamingDidCompleteDiscovery`
- Event handling: `.error` with credits message → calls `delegate.streamingShouldReturnToConfirmation`
- Session failure with `.streamInterrupted` → starts polling
- Polling timeout → calls `delegate.streamingShouldShowPollingFailedAlert`
- Audio modal trigger on first discovery
- Dependencies: `historyRepository`, `creditBalanceStore`, mock delegate

**ConfirmationStateBuilderTests**
- Build with upload + EXIF location → state includes location
- Build with camera + no location → state has nil location, isResolvingLocation depends on permission
- Credit loading from cache
- Intro mode detection
- `applyPermission(granted: true)` when location is nil → kicks off resolution, calls `onConfirmationUpdated`
- `refreshAfterCreditsSheet()` → returns updated balance + intro mode
- Dependencies: `locationService`, `creditBalanceStore`, `historyRepository`, `pushService` stubs

## Verification

After all steps:
1. **Build**: `USE_REMOTE_DEPS=1 xcodebuild -workspace native/WhatsThatIOS.xcworkspace -scheme WhatsThatIOS -destination 'platform=iOS Simulator,name=iPhone 16' build`
2. **Tests**: `USE_REMOTE_DEPS=1 xcodebuild test -workspace native/WhatsThatIOS.xcworkspace -scheme WhatsThatIOS -destination 'platform=iOS Simulator,name=iPhone 16' -testPlan WhatsThatIOS`
3. **Manual flows**: Camera capture → confirm → analyze → stream completes; Gallery upload → confirm → analyze; Cancel at each stage; "Discover More" from streaming; Credits exhausted at confirm; Credits exhausted mid-analysis; Permission denied; Stream interruption → polling fallback; Foreground return during confirmation; Credits sheet dismiss → balance refresh

Final state:
- VM at 668 lines (down from ~1560). Target was 350-400 but remaining logic is legitimate orchestration: ephemeral location bridging, payload building, state machine transitions, cross-cutting concerns
- PhotoCaptureCoordinator: 103 lines, StreamingSessionHandler: 491 lines, ConfirmationStateBuilder: 392 lines
- 33 new focused tests (7 PhotoCapture + 13 StreamingHandler + 13 ConfirmationBuilder)
- `creditsRepository` and `analysisClient` dependencies removed from VM; `StubAnalysisClient` removed from tests
- All existing tests pass (no regressions; pre-existing `testBeginAnalysisStreamsAndCompletes` failure unrelated)
- No view files changed
- Each helper is independently testable with focused stubs
- `StreamingSessionDelegate` protocol provides clean discrete-event communication
- `@Published analysisState` on handler provides efficient continuous-state bridging
