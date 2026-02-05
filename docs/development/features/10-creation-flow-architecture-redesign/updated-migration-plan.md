# Updated Migration Plan

Revised from the original 6-phase plan with all onboarding revamp features accounted for, gaps addressed, and concrete implementation guidance.

---

## Prerequisite: Fix Credits Refresh Bug

**Before any architecture work**, fix the credits refresh bug independently. This bug exists today and is orthogonal to the architecture.

**Fix:** In `syncCreditBalance()`, also update `isInIntroMode`:

```swift
func syncCreditBalance(_ newValue: Int?) async {
    let normalized = await creditBalanceStore.set(newValue)
    creditBalance = normalized
    // Also update intro mode since purchase may have exited intro
    let tracker = FreeCreditsAlertTracker.shared
    isInIntroMode = await tracker.isInIntroMode
}
```

This ensures that even if `.onChange(of: activeSheet)` fails to fire, the intro state is updated during the purchase callback.

---

## Phase 1: Modal Presentation (Highest Impact, Lowest Risk)

### Goal
Replace the overlay ZStack with a `fullScreenCover` modal. Everything else stays the same.

### Changes

#### 1.1 Add modal presentation to MainTabView

```swift
// Add to MainTabView:
@State private var activeCreationFlowType: DiscoveryCreationFlowType?
@State private var pendingTabAction: PendingTabAction?

enum PendingTabAction {
    case launchCamera
    case launchUpload
}
```

#### 1.2 Present creation flow as fullScreenCover

Replace the overlay ZStack block with:

```swift
.fullScreenCover(item: $activeCreationFlowType) { flowType in
    let viewModel = flowType == .camera ? cameraViewModel : uploadViewModel
    DiscoveryCreationFlowView(
        viewModel: viewModel,
        placeholderEmoji: flowType == .camera ? "camera" : "frame",
        ctaTitle: flowType == .camera ? "Take a photo" : "Choose a photo",
        retryTitle: flowType == .camera ? "Try again" : "Select again",
        // No isOverlay parameter needed!
        makeCreditsViewModel: makeCreditsViewModel,
        fetchRecentDiscoveries: { storeObserver.discoveries },
        // ... other dependencies
    )
}
```

#### 1.3 Remove overlay infrastructure

Delete from MainTabView:
- `activeOverlayTab` state variable
- `shouldShowOverlay()` methods
- The overlay ZStack block
- `updateOverlayVisibility()` methods
- `handleAnalysisBegan()` method (no longer needed — modal is already presented)

#### 1.4 Remove `isOverlay` flag

From `DiscoveryCreationFlowView`:
- Remove the `isOverlay` parameter
- Always present the audio generating modal (no `isOverlay &&` guard)
- Remove the `onDiscoverAnother` parameter (handle differently, see below)

#### 1.5 Update tab content

Camera and Upload tabs no longer embed `DiscoveryCreationFlowView`. Instead:

```swift
// Camera tab:
DiscoveryCaptureStartView(
    emoji: "camera",
    title: "Take a photo to discover",
    action: { activeCreationFlowType = .camera }
)
.tag(Tab.camera)

// Upload tab:
DiscoveryCaptureStartView(
    emoji: "frame",
    title: "Choose a photo from your gallery",
    action: { activeCreationFlowType = .upload }
)
.tag(Tab.upload)
```

#### 1.6 Handle post-onboarding auto-launch

When coming from `PostOnboardingCarousel`, the user expects immediate camera/upload launch:

```swift
// In MainTabView:
.onAppear {
    // One-time auto-launch from post-onboarding welcome screen
    if let action = pendingTabAction {
        pendingTabAction = nil
        switch action {
        case .launchCamera:
            activeCreationFlowType = .camera
        case .launchUpload:
            activeCreationFlowType = .upload
        }
    }
}
```

In `RootContentView`, set `pendingTabAction` based on `mainTabDestination`:

```swift
MainTabView(
    // ...
    pendingTabAction: mainTabDestination == .camera ? .launchCamera
                    : mainTabDestination == .upload ? .launchUpload
                    : nil,
    // ...
)
```

#### 1.7 Simplify handleTabChange

```swift
private func handleTabChange(to tab: Tab) {
    let isSafeScreen = (tab == .discoveries || tab == .audioGuides)
    onScreenSafetyChanged?(isSafeScreen)
    // No flow starting/cancelling
    // No overlay management
}
```

#### 1.8 Move Credits Exhausted to DiscoveryCreationFlowView

Remove from MainTabView:
- `showFreeCreditsExhaustedModal` state
- `shouldPresentCreditsAfterDismiss` state
- The `.onChange(of: cameraViewModel.showFreeCreditsExhaustedAtConfirm)` handlers
- The `.fullScreenCover(isPresented: $showFreeCreditsExhaustedModal)` block

The `DiscoveryCreationFlowView` already has its own `fullScreenCover` for this. Remove the flag-interception pattern in MainTabView and let the view handle it directly.

#### 1.9 Handle modal dismiss

```swift
.fullScreenCover(item: $activeCreationFlowType, onDismiss: {
    // Navigate to discoveries after creation flow closes
    selectedTab = .discoveries
}) { flowType in
    // ...
}
```

### What This Phase Achieves

- Single instance of creation flow (modal)
- No overlay ZStack
- No `isOverlay` flag
- No `activeOverlayTab` state
- No `handleAnalysisBegan` tab switching
- Credits exhausted handled within modal
- MainTabView drops to ~400 lines

### What Still Uses Closures

The `.onAppear` closure assignments remain for now. Phase 3 converts these.

### Onboarding Features Preserved

- [x] Post-onboarding auto-launch (via pendingTabAction)
- [x] Intro mode (ViewModel unchanged)
- [x] Conditional permissions (ViewModel unchanged)
- [x] Audio generating modal (always presented, no isOverlay gate)
- [x] Credits exhausted screen (moved to DiscoveryCreationFlowView)
- [x] Post-purchase configuration (unchanged, nested in CreditsView)
- [x] Background sessions (SessionManager unchanged)

---

## Phase 2: Simplify "Discover Another"

### Goal
Replace the 10-step state machine with dismiss + re-present.

### Changes

#### 2.1 Remove state preservation from ViewModel

Delete from `DiscoveryCreationFlowViewModel`:
- `PreservedStreamingState` struct
- `preservedState` property
- `restorePreservedStateIfAvailable()` method
- `clearPreservedState()` method
- `onStateRestored` callback

Simplify `unsubscribe()` to just unsubscribe from session (no state saving).

#### 2.2 Redesign "Create Another" from audio modal

In `DiscoveryCreationFlowView`:

```swift
// "Create Another" from audio modal:
AudioGeneratingModalView(
    onCreateAnother: {
        viewModel.showAudioGeneratingModal = false
        shouldCreateAnotherAfterModalDismiss = true
    },
    onReadThisDiscovery: {
        viewModel.showAudioGeneratingModal = false
    }
)
```

On audio modal dismiss:
```swift
.sheet(isPresented: ..., onDismiss: {
    if shouldCreateAnotherAfterModalDismiss {
        shouldCreateAnotherAfterModalDismiss = false
        // Tell the coordinator to dismiss this modal and start a new flow
        onRequestNewDiscovery?()
    }
})
```

The coordinator (MainTabView or dedicated coordinator) handles:
```swift
// Dismiss current creation flow modal
activeCreationFlowType = nil
// After dismiss animation completes, start new flow
DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
    activeCreationFlowType = lastFlowType
}
```

#### 2.3 Remove "Discover Another" from streaming view

The streaming view's "Discover More" button works similarly:

```swift
onNewDiscovery: {
    viewModel.unsubscribe()  // Session continues in background
    onRequestNewDiscovery?()
}
```

### What This Phase Achieves

- 10-step state machine → 3 steps
- No PreservedStreamingState
- No restorePreservedStateIfAvailable
- No onStateRestored callback
- Simpler unsubscribe (just detach from session)

---

## Phase 3: Convert Closures to Publishers

### Goal
Eliminate stale-closure risk entirely.

### Changes

#### 3.1 Add published properties to ViewModel

```swift
// Replace onDiscoveryCreated, onDiscoverySummaryReady, onPollingDiscoveryReady
@Published private(set) var completedDiscovery: DiscoverySummary?

// Already exists:
let analysisBeganPublisher = PassthroughSubject<DiscoveryCreationFlowType, Never>()
```

#### 3.2 Replace .onAppear closures with .onReceive

In MainTabView or coordinator:

```swift
.onReceive(cameraViewModel.$completedDiscovery.compactMap { $0 }) { summary in
    Task {
        await storeObserver.upsert(summary)
        await audioServices.discoveryStore.upsert(summary)
    }
}
.onReceive(uploadViewModel.$completedDiscovery.compactMap { $0 }) { summary in
    Task {
        await storeObserver.upsert(summary)
        await audioServices.discoveryStore.upsert(summary)
    }
}
```

#### 3.3 Remove from MainTabView.onAppear

Delete all closure assignments:
- `cameraViewModel.onDiscoveryCreated = ...`
- `uploadViewModel.onDiscoveryCreated = ...`
- `cameraViewModel.onDiscoverySummaryReady = ...`
- `uploadViewModel.onDiscoverySummaryReady = ...`
- `cameraViewModel.onPollingDiscoveryReady = ...`
- `uploadViewModel.onPollingDiscoveryReady = ...`
- `cameraViewModel.onStateRestored = ...` (already removed in Phase 2)
- `uploadViewModel.onStateRestored = ...` (already removed in Phase 2)

### What This Phase Achieves

- Zero closure-based callbacks
- No stale-closure risk
- Declarative data flow (Combine publishers)

---

## Phase 4: Extract Coordinator

### Goal
MainTabView becomes pure tab routing (~100-150 lines).

### Changes

#### 4.1 Create CreationFlowCoordinator

```swift
@MainActor
final class CreationFlowCoordinator: ObservableObject {
    @Published var activeFlowType: DiscoveryCreationFlowType?
    @Published var pendingAction: PendingTabAction?

    let cameraViewModel: DiscoveryCreationFlowViewModel
    let uploadViewModel: DiscoveryCreationFlowViewModel
    let dependencies: CreationFlowDependencies

    func presentFlow(type: DiscoveryCreationFlowType) {
        activeFlowType = type
    }

    func dismissFlow() {
        activeFlowType = nil
    }

    func handleNewDiscoveryRequest() {
        let lastType = activeFlowType
        dismissFlow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.activeFlowType = lastType
        }
    }
}
```

#### 4.2 Create CreationFlowDependencies struct

```swift
struct CreationFlowDependencies {
    let makeCreditsViewModel: (() -> CreditsViewModel)?
    let fetchRecentDiscoveries: () -> [DiscoverySummary]
    let playbackController: VoiceoverPlaybackController?
    let loadVoiceoverPreferences: (() async -> VoiceoverPreferences)?
    let saveVoiceoverPreferences: ((VoiceoverPreferences) async -> Void)?
    let fetchVoiceOptions: (() async -> [VoiceModelOption])?
    let fetchVoiceSampleURL: ((String) async -> URL?)?
    let loadIPoPPreferences: (() async -> IPoPPreferences?)?
    let saveIPoPPreferences: ((IPoPPreferences) async -> Void)?
}
```

#### 4.3 Simplify MainTabView

MainTabView becomes:

```swift
struct MainTabView: View {
    @State private var selectedTab: Tab = .discoveries
    @ObservedObject var coordinator: CreationFlowCoordinator
    @ObservedObject var storeObserver: DiscoveryStoreObserver
    @ObservedObject var audioServices: AudioServicesContainer

    var body: some View {
        TabView(selection: $selectedTab) {
            cameraTab
            discoveriesTab
            audioGuidesTab
            uploadTab
        }
        .fullScreenCover(item: $coordinator.activeFlowType) { flowType in
            CreationFlowModalView(
                coordinator: coordinator,
                flowType: flowType
            )
        }
        // Mini player, toasts, etc.
    }
}
```

### What This Phase Achieves

- MainTabView: ~100-150 lines
- All creation flow logic in coordinator
- Clean dependency injection
- Testable coordinator

---

## Phase 5: Break Up ViewModel

### Goal
Split the 1700-line ViewModel into focused components.

### New Components

| Component | Responsibility | ~Lines |
|-----------|---------------|--------|
| `PhotoCaptureCoordinator` | Permissions, camera/picker, UIImagePickerController | ~200 |
| `DiscoveryConfirmationViewModel` | Location, credits, nearby places, confirmation state assembly | ~400 |
| `DiscoveryStreamingViewModel` | Session subscription, event handling, polling recovery | ~300 |
| `DiscoveryCreationFlowCoordinator` | Orchestrates the above, manages flow state | ~200 |

### What Stays in Each

**PhotoCaptureCoordinator:**
- `requestPermission()` for camera/photo library
- `capturePhoto()` / `selectPhoto()`
- `savePhotoToLibraryIfEnabled()`
- Image encoding (`makeBase64Payload`)

**DiscoveryConfirmationViewModel:**
- `prepareConfirmation()`
- Location resolution (ephemeral fresh, nearby places)
- Credit balance management
- `requestLocationPermissionIfNeeded()`
- `requestNotificationPermissionIfNeeded()`
- Intro mode state (`isInIntroMode`, `introDiscoveryCount`)
- `refreshStateAfterCreditsSheet()`

**DiscoveryStreamingViewModel:**
- `startAnalysisSession()`
- `handle(event:)` for analysis events
- `analysisParser` for stream parsing
- Polling recovery
- `DiscoverySessionSubscriber` conformance
- `handleSuccessfulCreation()`

**DiscoveryCreationFlowCoordinator:**
- `flowState` management
- `startFlow()` / `cancelFlow()` / `retake()`
- `beginAnalysis()` orchestration
- Transitions between capture → confirm → analyze → complete
- Error handling

### Migration Strategy

Do this incrementally:
1. Extract `PhotoCaptureCoordinator` first (cleanest boundary)
2. Extract `DiscoveryStreamingViewModel` (second cleanest)
3. Extract `DiscoveryConfirmationViewModel` (most intertwined)
4. Rename remaining ViewModel to coordinator

Each extraction can be a separate PR, tested independently.

---

## Phase 6: Discovery Queue

### Goal
Show in-progress discoveries on Camera/Gallery tabs.

### Prerequisites
- Phases 1-4 complete
- `DiscoverySessionManager` exposes active sessions as `@Published`

### Changes

#### 6.1 Expose active sessions

```swift
// In DiscoverySessionManager:
@Published private(set) var activeSessions: [UUID: ActiveSessionInfo] = [:]

struct ActiveSessionInfo: Identifiable {
    let id: UUID
    let thumbnailData: Data?
    let title: String?
    let status: DiscoverySessionStatus
    let startedAt: Date
}
```

#### 6.2 Build queue component

```swift
struct ActiveDiscoveriesQueue: View {
    let sessions: [ActiveSessionInfo]
    let onTap: (UUID) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("In Progress (\(sessions.count))")
                .font(.headline)
            ForEach(sessions) { session in
                ActiveDiscoveryRow(session: session)
                    .onTapGesture { onTap(session.id) }
            }
        }
    }
}
```

#### 6.3 Allow tapping to open any session

Tapping a queued discovery presents a streaming modal subscribed to that session:

```swift
.fullScreenCover(item: $selectedQueueSession) { sessionId in
    DiscoveryStreamingReconnectView(sessionId: sessionId)
}
```

The `DiscoveryStreamingReconnectView` subscribes to the session and shows its current state (in-progress or completed).

### Estimated Effort

Low-medium. The hard parts (session management, streaming view, background processing) already exist.

---

## Phase Summary

| Phase | Effort | Risk | Impact |
|-------|--------|------|--------|
| Prereq: Credits refresh fix | Small | Low | Fixes existing bug |
| 1: Modal presentation | Medium | Medium | Eliminates overlay, dual views, isOverlay flag |
| 2: Simplify "Discover Another" | Small | Low | Eliminates 10-step state machine |
| 3: Convert closures to publishers | Small | Low | Eliminates stale-closure risk |
| 4: Extract coordinator | Medium | Low | MainTabView → ~150 lines |
| 5: Break up ViewModel | Large | Medium | ViewModel 1700 → 4 components ~200-400 each |
| 6: Discovery queue | Medium | Low | New feature, builds on new architecture |

### Recommended Order

Phases 1-3 can be done in a single PR (they're interdependent). Phase 4 in a separate PR. Phase 5 as 3-4 incremental PRs. Phase 6 when ready for the new feature.

---

## Open Questions — Resolved

### Q1: Tab bar during analysis

**Decision:** Use `fullScreenCover` (hides tab bar). Rationale:
- The creation flow is a focused, modal experience
- User can dismiss to browse (session continues in background)
- Discovery queue (Phase 6) lets them return to the session
- Trying to keep the tab bar visible adds complexity (custom presentations, sheet workarounds) that contradicts the simplification goal

### Q2: Multiple concurrent sessions

**Decision:** Not needed for Phases 1-5. SessionManager already supports background continuation. Phase 6 adds visibility into background sessions. True concurrent multi-session support can be deferred.

### Q3: Photo capture trigger

**Decision:** CTA button on tabs, with auto-launch from post-onboarding welcome screen. This is more predictable for users and avoids the "tab tap = action" anti-pattern. The auto-launch covers the first-time user experience.

---

## Testing Strategy

### For Each Phase

1. **Regression test the full onboarding flow:**
   - Pre-onboarding gallery → sign up → welcome screen → camera → first discovery → audio modal → second discovery → third discovery → credits exhausted → purchase → post-purchase config → continue

2. **Test edge cases:**
   - Cancel camera picker at each stage
   - Background the app during streaming
   - Dismiss creation flow during streaming (session continues)
   - Purchase credits during confirmation
   - "Discover Another" from completed discovery

3. **Test the credits refresh path:**
   - Credits at 0 → purchase → return to confirm → credits updated
   - Audio toggle unlocked after purchase

4. **Test permissions:**
   - First camera use: camera permission prompt
   - Second camera use: location permission prompt on confirm
   - After purchase: notification permission prompt on confirm
