# Discovery Creation Flow - Architecture Redesign

## Background

During the onboarding revamp (feature #08), a critical bug was discovered where the "Audio Generating Modal" never appeared for fresh users. The root cause was **stale SwiftUI view instances** — closure-based callbacks pointed to old MainTabView instances after SwiftUI recreated the struct.

The bug was fixed with a Combine publisher, but the investigation revealed deep architectural problems. The fix was a patch; the architecture itself is the disease. This document captures the full critique and proposes a redesign.

See: `docs/development/features/08-onboarding-revamp/audio-modal-bug-investigation.md`

Additionally, two credits-related bugs from the onboarding revamp were analyzed and found to share the same architectural root cause. See the "Credits Bugs" section below.

- `docs/development/features/08-onboarding-revamp/credits-refresh-bug-investigation.md`
- `docs/development/features/08-onboarding-revamp/credits-sheet-error-investigation.md`

---

## Current Architecture

```
+-------------------------------------------------------------+
|                        ZStack                                |
|  +-------------------------------------------------------+  |
|  |                     TabView                            |  |
|  |  +---------+  +---------+  +---------+  +---------+   |  |
|  |  | Camera  |  |Discover |  |  Audio  |  | Gallery |   |  |
|  |  |  Flow   |  |  List   |  | Guides  |  |  Flow   |   |  |
|  |  +---------+  +---------+  +---------+  +---------+   |  |
|  +-------------------------------------------------------+  |
|                                                              |
|  +-------------------------------------------------------+  |
|  |         Overlay (when activeOverlayTab != nil)         |  |
|  |         DiscoveryCreationFlowView(isOverlay: true)     |  |
|  +-------------------------------------------------------+  |
+-------------------------------------------------------------+
```

### How Analysis Currently Works

1. User confirms on Camera/Upload tab
2. `handleAnalysisBegan` fires
3. `activeOverlayTab` set to `.camera` or `.upload`
4. `selectedTab` forced to `.discoveries`
5. A **third** `DiscoveryCreationFlowView` instance renders as an overlay
6. The same ViewModel drives both the tab-embedded copy and the overlay copy
7. An `isOverlay` flag gates which copy handles modal presentations

---

## Problem Inventory

### 1. Triple View Instantiation

`DiscoveryCreationFlowView` exists in three places simultaneously:

| Location | Rendered | `isOverlay` |
|---|---|---|
| Camera tab content | Always (SwiftUI keeps tab content alive) | `false` |
| Upload tab content | Always | `false` |
| ZStack overlay | When `activeOverlayTab != nil` | `true` |

The `isOverlay` flag is a code smell. It exists solely to prevent the tab-embedded shadow copies from presenting modals. The view must know "am I the real one or the shadow one?"

### 2. Stale Closure Risk

The Combine publisher fix solved `analysisBeganPublisher`, but six callbacks remain as closures assigned in `.onAppear`:

- `onDiscoveryCreated`
- `onDiscoverySummaryReady`
- `onPollingDiscoveryReady` (x2)
- `onStateRestored` (x2)

These capture `self` at assignment time. If SwiftUI recreates MainTabView, these closures point to a stale instance. Same bug class that took hours to debug.

### 3. MainTabView is a God View (~700 lines)

Responsibilities that don't belong together:
- Tab routing
- Overlay lifecycle management
- Discovery creation orchestration (wiring ViewModel callbacks)
- Credits exhaustion flow (fullScreenCover + sheet sequencing)
- Audio services (mini player positioning, voiceover triggers)
- Session manager configuration
- State restoration ("Discover Another" cancel-restore path)
- Screen safety tracking (compliance overlay deferral)
- Toast overlay management

### 4. handleTabChange Has Dangerous Side Effects

Switching tabs triggers business logic:

```swift
case .camera:
    uploadViewModel.cancelFlow()   // or unsubscribe if analyzing
    cameraViewModel.startFlow()    // always starts new flow
    activeOverlayTab = nil         // clears overlay
```

- Tapping Camera always starts a fresh flow, even if one was in progress
- Tapping any non-creation tab cancels flows (unless analyzing)
- The overlay is cleared on tab switch
- User cannot "go back" to a confirmation screen after accidentally tapping another tab

### 5. "Discover Another" Flow is a State Machine Nightmare

~10 state transitions across 3 objects for "start a new discovery while the current one finishes":

1. `shouldCreateAnotherAfterModalDismiss = true`
2. Dismiss modal
3. `onDismiss` -> `onDiscoverAnother`
4. `targetViewModel.unsubscribe()` (preserves state)
5. Switch `selectedTab` to camera/upload
6. `targetViewModel.retake()` (starts new capture)
7. `onChange(selectedTab)` -> `handleTabChange` (async, races with retake)
8. If user cancels -> `onStateRestored` fires
9. Restore `activeOverlayTab` and `selectedTab`
10. `restorePreservedStateIfAvailable()` with 3 sub-paths (completed/failed/processing)

### 6. DiscoveryCreationFlowViewModel (~1700 lines) Does Everything

- Camera/photo library permissions
- UIImagePickerController coordination
- Photo encoding
- Location permission + resolution + nearby places
- Credit balance + intro mode
- Confirmation state assembly
- Analysis session creation
- Streaming event handling
- Polling recovery (8 retries, ~79s)
- State preservation + restoration
- Audio generation modal logic
- Push token management

---

## Credits Bugs: Both Are Architecture Victims

Two persistent credits bugs from the onboarding revamp share the same root cause as the audio modal bug — they exist because the creation flow is split across MainTabView and DiscoveryCreationFlowView.

### The Shared Root Cause: Two Parallel Credits Sheet Paths

There are two completely separate paths to present the credits sheet:

**Path A** — From `DiscoveryCreationFlowView` (user taps credits badge on confirmation):
- Presents via `activeSheet = .credits(vm)`
- Has `.onChange(of: activeSheet)` that calls `refreshStateAfterCreditsSheet()` on dismiss
- This path works

**Path B** — From `MainTabView` (user hits "Unlock More Stories" on exhausted modal):
- MainTabView intercepts `showFreeCreditsExhaustedAtConfirm` via `.onChange` (line 394), resets the ViewModel flag, and presents its own `fullScreenCover`
- After fullScreenCover dismisses, creates a ViewModel and presents via `showCreditsSheetFromExhausted`
- On dismiss, the only cleanup is `creditsExhaustedCreditsViewModel = nil` (line 286)
- **There is NO call to `refreshStateAfterCreditsSheet()`**

### Bug: Credits Don't Refresh After Purchase

When user goes through the exhausted modal flow (Path B), the credits sheet is presented from MainTabView. When it dismisses, `DiscoveryCreationFlowView`'s `.onChange(of: activeSheet)` never fires because `activeSheet` was never set — a completely different state variable (`showCreditsSheetFromExhausted`) drove the presentation. So `refreshStateAfterCreditsSheet()` is never called, `creditBalance` stays at 0, `isInIntroMode` stays true.

This explains why three fix attempts failed — they all targeted the refresh logic or dismiss timing, but the refresh logic simply doesn't exist on Path B.

### Bug: Credits Sheet Shows Error on First Try

Also Path B. The sequence is: dismiss fullScreenCover -> create ViewModel in `onDismiss` -> wait 100ms -> present sheet. SwiftUI hasn't committed the ViewModel state change by the time it evaluates the sheet content, so `creditsExhaustedCreditsViewModel` is still nil and the error fallback renders.

This only happens because the credits sheet is presented from MainTabView during a dismiss animation transition — a dance that only exists because the exhausted modal was hoisted up to MainTabView in the first place.

### Why the Redesign Fixes Both

With the modal-based architecture:
- There's ONE `DiscoveryCreationFlowView` instance (the modal)
- The credits exhausted fullScreenCover is presented from that modal
- The credits sheet is presented from that modal
- **One path.** When the sheet dismisses, `.onChange(of: activeSheet)` fires reliably, `refreshStateAfterCreditsSheet()` runs
- No fullScreenCover-dismiss-then-present-sheet-from-different-view timing race

Both bugs vanish because the split presentation paths no longer exist.

---

## Proposed Architecture

### Guiding Principles

1. **Single instance, single source of truth.** The creation flow exists in one place, not duplicated.
2. **Separate "start" from "in-progress."** Tabs contain entry points. Active flows leave the tab system.
3. **Background processing is independent of UI.** SessionManager handles sessions; UI subscribes/unsubscribes cleanly.
4. **MainTabView only does tab routing.** ~100-150 lines max.

### Design

```
+-------------------------------------------------------------+
|                        MainTabView                           |
|  +----------+  +------------+  +----------+  +----------+   |
|  |  Camera   |  | Discoveries|  |  Audio   |  | Gallery  |   |
|  | (trigger) |  | + In Prog  |  | Guides   |  | (trigger)|   |
|  +----------+  +------------+  +----------+  +----------+   |
+-------------------------------------------------------------+
        |                                            |
        +---- triggers .fullScreenCover -------------+
                         |
        +----------------v--------------------------+
        |     DiscoveryCreationFlowView              |
        |  (single instance, presented modally)      |
        |                                            |
        |  Confirming -> Analyzing -> Complete        |
        |                                            |
        |  [X] -> dismiss -> land on Discoveries     |
        |  [Discover More]:                           |
        |    -> "Take a Photo" -> camera picker       |
        |    -> "Upload Another" -> photo picker      |
        +--------------------------------------------+
```

### Key Changes

1. **Camera/Upload tabs are pure action triggers.** Tapping Camera opens the camera picker immediately. Tapping Gallery opens the photo picker immediately. No CTA screen, no content — just immediate action via `fullScreenCover`.

2. **Discoveries tab is the single home for all discovery states.** Completed discoveries (existing) plus in-progress discoveries (new queue section at top). This is the ONE place users go to see what's happening with their discoveries.

3. **One DiscoveryCreationFlowView instance.** Presented modally from the picker flow. No overlay, no dual rendering, no `isOverlay` flag.

4. **Dismiss = navigate to Discoveries.** When the modal is dismissed, set `selectedTab = .discoveries`. One line.

5. **Background completion via SessionManager.** If the user dismisses during analysis, the session continues. Toast notification (already exists) tells them when it's done. The in-progress item is visible on the Discoveries tab.

6. **"Discover More" stays within the modal.** The ViewModel's `discoverMore(type:)` method opens the camera/photo picker over the streaming view — no modal dismiss needed. The streaming view stays mounted and receiving events. If the user cancels the picker, they're right back where they were. If they take a photo, the ViewModel unsubscribes from the old session and transitions to confirmation. The audio generating modal (first discovery) offers "Take a Photo" + "Upload Another"; the streaming view's button re-triggers the same flow type. See `discover-more-cancel-behavior.md` for full design.

7. **Multiple concurrent sessions.** SessionManager tracks all active sessions. Users can queue several discoveries. Each appears in the Discoveries tab's in-progress section.

### What This Eliminates

| Current Complexity | Removed By |
|---|---|
| `activeOverlayTab` state | No overlay; modal presentation |
| `isOverlay` flag on views | Single instance |
| `shouldShowOverlay()` logic | Gone |
| `handleAnalysisBegan` forced tab switch | Gone; modal stays on top |
| `unsubscribe()` / `preserveState` / `restoreState` | SessionManager handles background |
| 6 closure-based callbacks in `.onAppear` | Combine publishers or coordinator pattern |
| `handleTabChange` side effects | Tabs are just navigation |
| `shouldPresentCreditsAfterDismiss` flag | Credits sheet presented from modal directly |
| `shouldCreateAnotherAfterModalDismiss` | Dismiss modal, re-trigger from tab |

---

## Feature: Discovery Queue on Discoveries Tab

### Concept

In-progress discoveries are shown on the Discoveries tab, in a section above completed discoveries. This is the single place users go to see all their discoveries — both finished and still being analyzed. Tapping an in-progress item opens its streaming view so they can watch progress or see the completed result.

Camera and Gallery tabs have no content of their own — they are pure action triggers. This avoids the confusing duplication of showing the same in-progress items on two different tabs.

### Why This Architecture Enables It

With the current overlay-based architecture, this is essentially impossible to implement cleanly. The creation flow is tightly coupled to the tab system, and there can only be one "active" flow at a time visible through the overlay. Showing multiple in-progress discoveries would require multiple overlays or a completely different rendering approach.

With the proposed modal-based architecture, this becomes straightforward:

1. **SessionManager already tracks all active sessions.** It knows which sessions are processing, completed, or failed. This is the data source.

2. **Sessions are decoupled from UI.** A session continues running regardless of whether any view is subscribed to it. There's no "unsubscribe/preserve/restore" dance — the session just exists.

3. **Each session's streaming view is an independent modal.** Tapping a queued discovery presents a `fullScreenCover` with a `DiscoveryStreamingView` subscribed to that session. Dismissing it doesn't affect the session.

4. **No state preservation needed.** When user dismisses a streaming modal, the session keeps running. When they re-open it, they just subscribe to the session's current state (which may have progressed or completed).

### UI Sketch

```
+------------------------------------------+
|  Discoveries                    [gear]   |
|                                          |
|  IN PROGRESS                             |
|  +------------------------------------+  |
|  | [thumb] Analyzing...       *pulse* |  |
|  +------------------------------------+  |
|  | [thumb] "Sagrada Familia"  *pulse* |  |
|  +------------------------------------+  |
|                                          |
|  YOUR DISCOVERIES                        |
|  +------------------------------------+  |
|  | [thumb] "Blue Mosque"    2 min ago |  |
|  +------------------------------------+  |
|  | [thumb] "Street Art..."  yesterday |  |
|  +------------------------------------+  |
+------------------------------------------+
```

- In-progress items always show at the top, above completed discoveries
- Each shows: thumbnail (from captured photo), title if metadata has arrived, a loading pulse indicator
- Tapping one presents the streaming modal (fullScreenCover)
- When a session completes, the item moves from "In Progress" to the main list (with animation)
- If no sessions are in progress, the section is hidden entirely

### Implementation Sketch

```swift
// On Discoveries tab (DiscoveriesHomeView):
struct DiscoveriesHomeView: View {
    @ObservedObject var sessionManager: DiscoverySessionManager
    @State private var selectedSession: DiscoverySession?

    var body: some View {
        List {
            // In-progress section (only when sessions exist)
            if !sessionManager.activeSessions.isEmpty {
                Section("In Progress") {
                    ForEach(sessionManager.activeSessions) { session in
                        InProgressDiscoveryRow(session: session)
                            .onTapGesture { selectedSession = session }
                    }
                }
            }

            // Completed discoveries (existing)
            Section("Your Discoveries") {
                ForEach(discoveries) { discovery in
                    DiscoveryRow(discovery: discovery)
                }
            }
        }
        .fullScreenCover(item: $selectedSession) { session in
            DiscoveryStreamingView(session: session)
        }
    }
}
```

### Feasibility: High

This is low-effort once the modal-based architecture is in place:

- **Data source exists**: `DiscoverySessionManager` already tracks sessions
- **Streaming view exists**: `DiscoveryStreamingStageView` already renders analysis progress
- **Subscription model exists**: `DiscoverySessionSubscriber` protocol already handles event replay
- **No new state management**: Just read from SessionManager, present modal on tap

The main work is:
1. Expose active sessions from `DiscoverySessionManager` as a `@Published` array
2. Build a small `InProgressDiscoveryRow` component (thumbnail + title + status pulse)
3. Add the section to `DiscoveriesHomeView`
4. Allow the streaming view to subscribe to any session, not just the "current" one

Estimated effort: Small, once the architecture migration is complete.

---

## Gap Analysis: Onboarding Feature Interactions

The proposed architecture must preserve all onboarding revamp (Feature #08) behaviors. The following gaps were identified and resolved.

### Gap 1: Credits Exhausted Presentation Hierarchy

**Problem:** `CreditsExhaustedFullScreenView` is currently presented at MainTabView level via a flag-bouncing pattern: ViewModel sets flag → MainTabView.onChange catches → resets VM flag → sets own flag → presents.

**Solution:** Present the exhausted view as a `fullScreenCover` directly from `DiscoveryCreationFlowView`:

```swift
// In DiscoveryCreationFlowView (the modal):
.fullScreenCover(isPresented: $viewModel.showFreeCreditsExhaustedAtConfirm) {
    CreditsExhaustedFullScreenView(
        discoveries: recentDiscoveries,
        playbackController: playbackController,
        onGetCredits: { ... },
        onDismiss: { ... }
    )
}
```

This eliminates the MainTabView interception and is the primary mechanism that fixes both credits bugs.

**Dependencies:** The creation flow modal needs `recentDiscoveries` and `playbackController`. Inject via a `CreationFlowDependencies` struct (see Gap 5).

### Gap 2: "Discover More" from Streaming/Audio Modal

**Problem:** ~~Can't present a new `fullScreenCover` while dismissing the current one.~~

**Updated (2026-02-06):** This gap is resolved by the in-modal picker approach (Phase 2.2). "Discover More" no longer goes through the parent coordinator — the ViewModel's `discoverMore(type:)` method opens the picker over the streaming view within the same modal. No dismiss/re-present needed. See `discover-more-cancel-behavior.md` for details.

### Gap 3: Post-Onboarding Welcome → Direct Camera Launch

**Problem:** When a new user taps "Take a Photo" on the welcome screen, the current architecture auto-launches the camera because `handleTabChange(.camera)` calls `startFlow()`. With pure-trigger tabs, the user needs the picker to open without an extra tap.

**Solution:** Since tapping the Camera/Gallery tab immediately presents the picker, the welcome screen just sets `initialTab = .camera`. When MainTabView appears with `selectedTab = .camera`, the picker auto-presents. This falls out naturally from the pure-trigger design — no `pendingAction` flag needed.

### Gap 4: Nested Sheet Presentation After Purchase

**Problem:** After purchasing credits, the dismiss chain is: creation modal → sheet (credits) → fullScreenCover (post-purchase config) → dismiss chain back up. The credits refresh bug was caused by `.onChange(of: activeSheet)` not firing reliably.

**Assessment:** The root cause (Path B — MainTabView presenting credits separately) is eliminated by Phase 1. Path A (credits sheet from DiscoveryCreationFlowView) is the only remaining path, and it already has the refresh logic. The nested dismiss chain is identical to today's Path A, which works.

**Defensive fix (recommended):** Also update `isInIntroMode` in `syncCreditBalance()`, not just in `refreshStateAfterCreditsSheet()`. This ensures intro state is updated during the purchase callback regardless of dismiss behavior:

```swift
func syncCreditBalance(_ newValue: Int?) async {
    let normalized = await creditBalanceStore.set(newValue)
    creditBalance = normalized
    let tracker = FreeCreditsAlertTracker.shared
    isInIntroMode = await tracker.isInIntroMode
}
```

### Gap 5: Dependencies for the Creation Flow Modal

**Problem:** The creation flow modal needs access to `storeObserver.discoveries`, `audioServices.playbackController`, `makeCreditsViewModel`, and voiceover/IPoP preference closures. Currently MainTabView passes 10+ closures individually.

**Solution:** Bundle into a `CreationFlowDependencies` struct:

```swift
struct CreationFlowDependencies {
    // Credits
    let makeCreditsViewModel: (() -> CreditsViewModel)?
    let fetchRecentDiscoveries: () -> [DiscoverySummary]

    // Audio services (for mini player + toast inside modal)
    let audioServices: AudioServicesContainer
    let miniPlayerPresence: MiniPlayerPresenceStore
    let sessionManager: DiscoverySessionManager

    // Post-purchase configuration
    let loadVoiceoverPreferences: (() async -> VoiceoverPreferences)?
    let saveVoiceoverPreferences: ((VoiceoverPreferences) async -> Void)?
    let fetchVoiceOptions: (() async -> [VoiceModelOption])?
    let fetchVoiceSampleURL: ((String) async -> URL?)?
    let loadIPoPPreferences: (() async -> IPoPPreferences?)?
    let saveIPoPPreferences: ((IPoPPreferences) async -> Void)?
}
```

Note: `audioServices` and `sessionManager` are needed to render the mini player and toast overlay inside the modal (see Phase 1.8).

### Gap 6: What Replaces handleTabChange Side Effects

**Problem:** Current `handleTabChange` starts/cancels flows and manages overlays. With pure-trigger tabs, what replaces it?

**Solution:** It becomes trivial:

```swift
func handleTabChange(to tab: Tab) {
    let isSafeScreen = (tab == .discoveries || tab == .audioGuides)
    onScreenSafetyChanged?(isSafeScreen)
}
```

- Sessions continue in background automatically (SessionManager)
- No auto-starting or cancelling flows
- No overlay management
- Abandoned confirmations clean up when the user starts a new flow (ViewModel resets in `beginFlow()`)

### Gap 7: Session Manager Multi-Session Support

**Problem:** `DiscoverySessionManager` currently has a single `activeSession` slot. With concurrent sessions, only one is treated as "active."

**Assessment:** The current behavior is acceptable for Phases 1-5:
- Session 1 completes and fires `onDiscoveryCompleted` regardless of subscriber
- Toast shows for background completions
- Session 2 is the "active" session with the subscriber

For Phase 6 (queue), refactor `activeSession` into a dictionary of active sessions. This is Phase 6 work.

### Gap 8: Combine Publisher Migration Specifics

Replace closures with published state:

| Closure | Replacement |
|---------|-------------|
| `onDiscoveryCreated` | `@Published completedDiscovery: DiscoverySummary?` |
| `onDiscoverySummaryReady` | Same as above — unify |
| `onPollingDiscoveryReady` | Same as above — unify |
| `onStateRestored` | **Eliminated** — no state preservation |
| `onAnalysisBegan` | **Eliminated** — modal already presented |
| `analysisBeganPublisher` | **Eliminated** — modal already presented |

The coordinator observes:
```swift
.onReceive(viewModel.$completedDiscovery.compactMap { $0 }) { summary in
    Task { await storeObserver.upsert(summary) }
}
```

---

## Migration Plan

### Phase 1: Modal Presentation (Highest Impact)

**Goal:** Replace the overlay ZStack with a `fullScreenCover` modal. This single change eliminates the triple-view problem, both credits bugs, and the forced tab-switch pattern.

#### 1.1 Add modal presentation state to MainTabView

```swift
@State private var activeCreationFlowType: DiscoveryCreationFlowType?
```

#### 1.2 Present creation flow as fullScreenCover

Replace the overlay ZStack block with:

```swift
.fullScreenCover(item: $activeCreationFlowType, onDismiss: {
    selectedTab = .discoveries
}) { flowType in
    let viewModel = flowType == .camera ? cameraViewModel : uploadViewModel
    DiscoveryCreationFlowView(
        viewModel: viewModel,
        dependencies: creationFlowDependencies,
        onRequestNewDiscovery: { type in handleNewDiscoveryRequest(type: type) }
    )
}
```

#### 1.3 Remove overlay infrastructure from MainTabView

Delete:
- `activeOverlayTab` state variable
- `shouldShowOverlay()` methods
- The overlay ZStack block in body
- `updateOverlayVisibility()` methods
- `handleAnalysisBegan()` method
- `analysisBeganPublisher` `.onReceive` handlers

#### 1.4 Remove `isOverlay` from DiscoveryCreationFlowView

- Remove the `isOverlay` parameter
- Always present the audio generating modal (no `isOverlay &&` guard)
- Replace `onDiscoverAnother` with `onRequestNewDiscovery(type:)` that takes a flow type parameter

#### 1.5 Camera/Gallery tabs as pure triggers

```swift
// Camera tab content — minimal, tab tap triggers the picker
Color.clear
    .tag(Tab.camera)
    .tabItem { Label("Camera", systemImage: "camera.fill") }

// Upload tab content
Color.clear
    .tag(Tab.upload)
    .tabItem { Label("Gallery", systemImage: "photo.on.rectangle") }
```

When `selectedTab` changes to `.camera` or `.upload`, auto-present the creation flow:

```swift
.onChange(of: selectedTab) { _, newValue in
    if newValue == .camera || newValue == .upload {
        activeCreationFlowType = newValue == .camera ? .camera : .upload
    }
}
```

This handles both tab taps AND the post-onboarding welcome screen (`initialTab = .camera` triggers the picker immediately).

Remove `DiscoveryCreationFlowView` from tab content entirely.

#### 1.6 Move Credits Exhausted to DiscoveryCreationFlowView

Remove from MainTabView:
- `showFreeCreditsExhaustedModal` state
- `shouldPresentCreditsAfterDismiss` state
- `showCreditsSheetFromExhausted` state
- `creditsExhaustedCreditsViewModel` state
- The `.onChange(of: *.showFreeCreditsExhaustedAtConfirm)` handlers
- The `.fullScreenCover(isPresented: $showFreeCreditsExhaustedModal)` block
- The `.sheet(isPresented: $showCreditsSheetFromExhausted)` block
- The `CreditsSheetErrorView` struct

`DiscoveryCreationFlowView` already has its own `fullScreenCover` for this — just remove the MainTabView interception that steals the presentation.

#### 1.7 Simplify handleTabChange

```swift
private func handleTabChange(to tab: Tab) {
    let isSafeScreen = (tab == .discoveries || tab == .audioGuides)
    onScreenSafetyChanged?(isSafeScreen)
}
```

#### 1.8 Add mini player and toast overlay inside the modal

The mini player and toast overlay currently live in MainTabView's ZStack. With a `fullScreenCover`, they're hidden behind the modal. To preserve existing behavior, both must render inside the creation flow modal.

**Mini player:** Add `MiniPlayerVisibilityWrapper` (or equivalent logic) inside `DiscoveryCreationFlowView`'s body, in a ZStack above the main content. The visibility rules match the current behavior:
- Hidden during `.confirming`, `.capturingInitial`, `.capturingRetake`, `.selectingInitial`, `.selectingRetake`, `.requestingPermissions`
- Visible during `.analyzing` (streaming/complete)

```swift
// Inside DiscoveryCreationFlowView (the modal):
ZStack(alignment: .bottom) {
    // Main creation flow content
    flowContent

    // Mini player - same phase-based visibility as MiniPlayerVisibilityWrapper
    if viewModel.flowState.phase == .analyzing,
       let controller = dependencies.playbackController,
       controller.currentDiscovery != nil
    {
        MiniPlayerView { /* tap action */ }
            .padding(.horizontal, 16)
            .padding(.bottom, UIDevice.isIPad ? 20 : 4)
    }

    // Toasts - background session completions
    UnifiedToastOverlay(
        audioServices: dependencies.audioServices,
        miniPlayerPresence: dependencies.miniPlayerPresence,
        onViewDiscovery: { discoveryId in
            // Dismiss modal, then navigate to discovery on Discoveries tab
            pendingViewDiscoveryId = discoveryId
            dismiss()
        },
        onGenerateAudio: { summary in
            dependencies.playbackController?.requestVoiceover(for: summary)
        }
    )
}
```

**Dependencies:** `CreationFlowDependencies` must include `audioServices` (or at minimum `playbackController` + `miniPlayerPresence`) and access to `DiscoverySessionManager.pendingCompletionToasts`.

**Mini player tap action:** When user taps the mini player during the modal, dismiss the creation flow modal and navigate to Audio Guides. The session continues in background via SessionManager.

**MainTabView keeps its own mini player and toast overlay** for when no modal is showing. No changes to MainTabView's existing overlays.

#### What Phase 1 Achieves

- Single instance of creation flow (modal)
- No overlay ZStack, no `isOverlay`, no `activeOverlayTab`
- No `handleAnalysisBegan` tab switching
- Both credits bugs fixed (single presentation path)
- Credits exhausted handled within modal
- Camera/Gallery tabs are pure triggers
- Post-onboarding auto-launch works naturally
- Mini player and toasts preserved inside modal with same behavior
- MainTabView drops to ~300 lines

---

### Phase 2: Simplify "Discover Another"

**Goal:** Replace the 10-step state machine. "Discover More" stays within the same modal — no dismiss/re-present cycle.

> **Design decision (2026-02-06):** "Discover More" uses the in-modal picker approach. The streaming view never unmounts. See `discover-more-cancel-behavior.md` for full analysis of alternatives.

#### 2.1 Remove state preservation from ViewModel

Delete from `DiscoveryCreationFlowViewModel`:
- `PreservedStreamingState` struct
- `preservedState` property
- `restorePreservedStateIfAvailable()` method
- `clearPreservedState()` method
- `onStateRestored` callback

Simplify `unsubscribe()` to just detach from session (no state saving).

**Status: DONE (Phase 2 already completed this)**

#### 2.2 Add `discoverMore(type:)` to ViewModel

Instead of dismissing the modal and re-presenting, the ViewModel handles "Discover More" internally. The system camera/photo picker naturally presents over the streaming view — the streaming view stays mounted and receiving session events behind the picker.

```swift
func discoverMore(type: DiscoveryCreationFlowType) {
    Task {
        do {
            let media: DiscoveryCapturedMedia
            switch type {
            case .camera:
                guard await captureService.requestPermission(for: .camera) else {
                    error = .cameraPermissionDenied
                    return  // Streaming view stays, error alert shows over it
                }
                media = try await captureService.capturePhoto()
            case .upload:
                guard await selectionService.requestPermission() else {
                    error = .photoLibraryPermissionDenied
                    return
                }
                media = try await selectionService.selectPhoto()
            }
            // User committed to new photo — detach from old session
            if let sessionId = currentSessionId {
                DiscoverySessionManager.shared.unsubscribe(from: sessionId)
                currentSessionId = nil
            }
            analysisState = nil
            confirmationState = nil
            await prepareConfirmation(with: media)
        } catch {
            if DiscoveryFlowCancellationError.isCancellation(error) {
                // User cancelled picker — streaming view is still showing, nothing to do
                return
            }
            self.error = .captureFailed
        }
    }
}
```

**Key behavior:**
- **Cancel picker** → return silently, streaming view unchanged, session events still flowing
- **Take photo** → unsubscribe from old session, clear analysis state, transition to `.confirming` with new photo. Old session continues in background.
- **Permission denied** → set `error` (alert shows over streaming view), don't change flowState

#### 2.3 Rewire "Discover More" entry points

**Streaming view's "Discover More" button:**
```swift
// Before (goes through MainTabView dismiss/re-present):
onNewDiscovery: {
    onRequestNewDiscovery?(viewModel.flowType)
}

// After (stays in modal):
onNewDiscovery: {
    viewModel.discoverMore(type: viewModel.flowType)
}
```

**Audio generating modal path:**
```swift
// Before (goes through MainTabView):
.sheet(isPresented: $viewModel.showAudioGeneratingModal, onDismiss: {
    if let type = pendingNewDiscoveryType {
        pendingNewDiscoveryType = nil
        onRequestNewDiscovery?(type)
    }
})

// After (stays in modal):
.sheet(isPresented: $viewModel.showAudioGeneratingModal, onDismiss: {
    if let type = pendingNewDiscoveryType {
        pendingNewDiscoveryType = nil
        viewModel.discoverMore(type: type)
    }
})
```

Audio modal still has dual options ("Take a Photo" + "Upload Another") — already implemented.

#### 2.4 Remove parent coordination for "Discover More"

- Remove `onRequestNewDiscovery` callback from `DiscoveryCreationFlowView`
- Remove `handleNewDiscoveryRequest()` from MainTabView
- `pendingCreationFlowAfterDismiss` / `isDismissingModal` infrastructure stays in MainTabView (still needed for tab taps during dismiss animations)

#### 2.5 Cancel at confirmation after "Discover More"

Once the user takes a new photo, the streaming view is replaced by the confirmation screen (flowState transitions from `.analyzing` to `.confirming`). The old session (A) is unsubscribed and running in the background.

If the user cancels at confirmation: `cancelFlow()` + `dismissModal()` → Discoveries tab. Session A finishes in the background and appears in the feed. The user cannot return to session A's streaming view from here — but they made an affirmative choice (took a new photo), so this is acceptable.

#### What Phase 2 Achieves

- 10-step state machine → eliminated entirely
- No `PreservedStreamingState`
- No `restorePreservedStateIfAvailable()`
- No `onStateRestored` callback
- No dismiss/re-present cycle for "Discover More"
- No `onRequestNewDiscovery` callback or `handleNewDiscoveryRequest()` in MainTabView
- Cancel picker → back to streaming view (not kicked to Discoveries tab)
- Simpler `unsubscribe()` (just detach)

---

### Phase 3: Convert Closures to Publishers

**Status: DONE (2026-02-06)**

**Goal:** Eliminate stale-closure risk entirely.

#### 3.1 Add published properties to ViewModel

Removed 5 closure-based callbacks (`onDiscoveryCreated`, `onDiscoverySummaryReady`, `onAnalysisBegan`, `analysisBeganPublisher`, `onPollingDiscoveryReady`). Replaced with two `@Published` properties:

```swift
@Published private(set) var completedDiscovery: DiscoverySummary?
@Published private(set) var createdDiscoveryId: Int64?
```

- `createdDiscoveryId` — set when `.complete` stream event arrives (triggers fallback timer in MainTabView)
- `completedDiscovery` — set when session completes with summary or polling finds discovery (triggers store upsert)
- Both reset to nil in `beginFlow()` and `transitionToNewDiscovery()` to prevent stale values on re-subscription

#### 3.2 Replace .onAppear closures with .onReceive

```swift
.onReceive(cameraViewModel.$createdDiscoveryId.compactMap { $0 }) { discoveryId in
    handleDiscoveryCreated(discoveryId)
}
.onReceive(cameraViewModel.$completedDiscovery.compactMap { $0 }) { summary in
    handleCompletedDiscovery(summary)
}
```

#### 3.3 Unified handler

`handleDiscoverySummaryReady` and `handlePollingDiscoveryReady` merged into single `handleCompletedDiscovery` (both upsert to store + cancel fallback timer).

#### 3.4 Dead code removed

`onAnalysisBegan` and `analysisBeganPublisher` were dead code since Phase 1 (no subscribers remained in MainTabView). Removed entirely.

#### What Phase 3 Achieves

- Zero closure-based callbacks on ViewModel
- No stale-closure risk
- Declarative data flow via Combine `.onReceive`
- Session manager callbacks (`onDiscoveryCompleted`, `onDiscoveryFailed`) remain in `.onAppear` — these are on the singleton, not the ViewModel

---

### Phase 4: Extract Coordinator

**Status: DONE (2026-02-06)**

**Goal:** MainTabView becomes pure tab routing (~100-150 lines).

#### 4.1 Create CreationFlowCoordinator

```swift
@MainActor
final class CreationFlowCoordinator: ObservableObject {
    @Published var activeFlowType: DiscoveryCreationFlowType?

    let cameraViewModel: DiscoveryCreationFlowViewModel
    let uploadViewModel: DiscoveryCreationFlowViewModel
    let dependencies: CreationFlowDependencies

    func presentFlow(type: DiscoveryCreationFlowType) {
        activeFlowType = type
    }

    func dismissFlow() {
        activeFlowType = nil
    }

    func handleNewDiscoveryRequest(type: DiscoveryCreationFlowType) {
        dismissFlow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.activeFlowType = type
        }
    }
}
```

#### 4.2 Simplify MainTabView

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
            CreationFlowModalView(coordinator: coordinator, flowType: flowType)
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .camera || newValue == .upload {
                coordinator.presentFlow(type: newValue == .camera ? .camera : .upload)
            }
        }
        // Mini player, toasts
    }
}
```

#### What Phase 4 Achieves

- MainTabView: ~284 lines (body is ~155 lines of tab routing + overlays + modifiers)
- All creation flow state and logic in `CreationFlowCoordinator` (~170 lines)
- Coordinator owns: ViewModels, modal presentation state (activeFlowType, dismiss guards), discovery completion tracking (fallback timer, store upsert), session manager configuration, and all creation-flow dependency closures
- MainTabView init reduced from 18 params to 9 (creation-flow closures removed)
- `CreationFlowDependencies` struct was not needed — coordinator holds closures directly, AudioGuidesPageView accesses them via `coordinator.makeCreditsViewModel` etc.
- RootContentView creates coordinator as `@StateObject`, replacing two separate VM StateObjects

---

### Phase 5: Break Up ViewModel

**Status: DONE (2026-02-06)**

**Goal:** Split the ~1560-line ViewModel into focused helpers using internal delegation. The VM remains the single `@ObservableObject` surface — no view changes needed.

| Component | Responsibility | Target Lines | Actual Lines |
|-----------|---------------|-------------|-------------|
| `PhotoCaptureCoordinator` | Permissions, camera/picker coordination | ~150 | 103 |
| `StreamingSessionHandler` | Session subscription, event handling, polling, photo save | ~350 | 491 |
| `ConfirmationStateBuilder` | Location, credits, nearby places, intro mode, history context | ~350 | 392 |
| `DiscoveryCreationFlowViewModel` (slimmed) | Orchestrates the above, manages flow state, @Published surface | ~350-400 | 668 |

**VM at 668 lines vs 350-400 target:** The remaining logic is legitimate orchestration that cannot be extracted further — ephemeral location bridging capture→confirmation→analysis, payload building, state machine transitions gluing the 3 coordinators, and cross-cutting concerns. All extractable logic has been moved.

**Communication patterns:**
- PhotoCaptureCoordinator → VM: return values (`CaptureResult` enum)
- StreamingSessionHandler → VM: `@Published analysisState` (Combine) + `StreamingSessionDelegate` protocol (8 discrete event callbacks)
- ConfirmationStateBuilder → VM: return values (`ConfirmationResult`) + 1 callback (`onConfirmationUpdated`)

**What was done:**
1. Extracted all three in a single pass: PhotoCaptureCoordinator first, StreamingSessionHandler second, ConfirmationStateBuilder third
2. Removed dead dependencies: `creditsRepository` and `analysisClient` from VM init, `StubAnalysisClient` from tests
3. 33 new focused tests: 7 PhotoCapture + 13 StreamingHandler + 13 ConfirmationBuilder
4. All existing tests pass unchanged (pre-existing `testBeginAnalysisStreamsAndCompletes` failure unrelated)
5. No view files changed — VM remains the single `@ObservableObject` surface

See `phase-5-viewmodel-decomposition.md` for full implementation plan.

---

### Phase 6: In-Progress Discoveries on Discoveries Tab

**Goal:** Show all processing discoveries on the Discoveries tab. Tap any to reconnect via the exact same creation flow modal.

**Prerequisites:** Phases 1-2 complete (modal architecture + `discoverMore()`).

#### 6.1 Refactor SessionManager: single-slot → dictionary

The current `activeSession: ActiveDiscoverySession?` is a single slot. When a second session starts, it **overwrites** the first — the first session's Task keeps running but events are silently dropped (no accumulation, no forwarding). This must change to support parallel sessions.

```swift
// Current (broken for multi-session):
private var activeSession: ActiveDiscoverySession?

// After:
private var activeSessions: [UUID: ActiveDiscoverySession] = [:]
```

Every method changes from `guard activeSession?.id == sessionId` to `guard var session = activeSessions[sessionId]`:

| Method | Change |
|--------|--------|
| `startProcessing()` | `activeSessions[id] = session` instead of `activeSession = session` |
| `deliverEvent(for:)` | `activeSessions[sessionId]` lookup |
| `subscribe(to:)` | dictionary lookup |
| `unsubscribe(from:)` | dictionary lookup |
| `handleCompletion()` | `activeSessions.removeValue(forKey:)` |
| `handleFailure()` | same pattern |
| `cancelSession()` | dictionary lookup + remove |

**Concurrency limit:** Up to 3 concurrent sessions process in parallel (edge function handles concurrency). Additional requests go into `pendingQueue` and start when a slot opens. This bounds memory from accumulated events + thumbnails.

```swift
private let maxConcurrentSessions = 3

public func startSession(...) -> UUID {
    let request = PendingDiscoveryRequest(...)
    if activeSessions.count >= maxConcurrentSessions {
        pendingQueue.append(request)
        sessionStatuses[request.id] = .queued
    } else {
        sessionStatuses[request.id] = .processing
        startProcessing(request, subscriber: subscriber)
    }
    return request.id
}
```

**Effort:** ~50 lines changed. No new logic — data structure swap.

#### 6.2 Expose in-progress display data

```swift
// In DiscoverySessionManager:
@Published private(set) var inProgressItems: [InProgressItem] = []

public struct InProgressItem: Identifiable {
    public let id: UUID
    public let thumbnailData: Data       // from PendingDiscoveryRequest.media.data
    public let media: DiscoveryCapturedMedia  // full media for attachToSession()
    public let flowType: DiscoveryCreationFlowType
    public let title: String?            // from metadata event (if received)
    public let status: DiscoverySessionStatus
    public let startedAt: Date
}
```

Updated whenever a session starts, receives a `.metadata` event, or completes. Completed sessions stay in the list briefly (with `.completed(summary)` status) until the Discoveries list refreshes and the item appears there.

**Effort:** ~30 lines.

#### 6.3 Add "In Progress" section to Discoveries tab

A section at the top of the Discoveries list showing each in-progress session:
- Thumbnail (captured photo)
- Spinner overlay while processing, "Queued" badge if waiting
- Title if metadata has arrived, otherwise "Discovering…"
- Tapping opens the creation flow modal (see 6.4)

When a session completes:
- Status changes to `.completed(summary)`
- Discoveries list refreshes in the background to include the new discovery
- The in-progress item can remain at the top as a "completed" item with the title
- Tapping opens the normal discovery detail view (not the streaming view)
- Once the discoveries list is refreshed and the item appears, remove from `inProgressItems`
- No animated transition between in-progress and completed — just refresh

```swift
// On Discoveries tab:
if !sessionManager.inProgressItems.isEmpty {
    Section("In Progress") {
        ForEach(sessionManager.inProgressItems) { item in
            InProgressDiscoveryRow(item: item)
                .onTapGesture { handleInProgressTap(item) }
        }
    }
}

func handleInProgressTap(_ item: InProgressItem) {
    switch item.status {
    case .completed(let summary):
        // Open normal discovery detail view
        selectedDiscovery = summary
    case .processing, .queued:
        // Reconnect via the same creation flow modal (see 6.4)
        reconnectToSession(item)
    case .failed:
        // Show error or retry option
        break
    }
}
```

**Effort:** ~120 lines.

#### 6.4 Tap to reconnect: reuse the exact same modal

Tapping an in-progress (still processing) session opens the **exact same** `DiscoveryCreationFlowView` modal used during creation. Not a lightweight version — the real thing. This means the user gets all functionality: streaming view, "Discover More", audio controls, credits, X to dismiss.

**How it works:**

1. Add `attachToSession()` method to ViewModel (~25 lines):

```swift
func attachToSession(sessionId: UUID, media: DiscoveryCapturedMedia) {
    // Set up state for streaming view
    let initialState = DiscoveryAnalysisState(
        statusMessage: "Reconnecting…",
        streamedText: "",
        isStreaming: true
    )
    analysisState = initialState
    currentMedia = media

    // Streaming view reads image from confirmationState
    confirmationState = DiscoveryConfirmationState(
        media: media,
        displayImageData: media.data,
        creditBalance: nil,
        location: media.location,
        locationDescription: nil,
        isLocationPermissionGranted: false,
        isResolvingLocation: false,
        customContext: nil,
        nearbyPlaces: nil,
        nearbyPlacesContext: nil
    )

    flowState = .analyzing(initialState)

    // Subscribe — session manager replays accumulated events
    // Events flow through handleSessionEvent() → handle(event:)
    // which updates analysisState via the existing code path
    currentSessionId = sessionId
    DiscoverySessionManager.shared.subscribe(to: sessionId, subscriber: self)
}
```

2. Present from Discoveries tab via `activeCreationFlowType`:

```swift
func reconnectToSession(_ item: InProgressItem) {
    let viewModel = item.flowType == .camera ? cameraViewModel : uploadViewModel
    viewModel.attachToSession(sessionId: item.id, media: item.media)
    activeCreationFlowType = item.flowType
}
```

3. The `.task` modifier sees `flowState.phase == .analyzing` (not `.idle`) and **does not call `startFlow()`**. The modal just renders the streaming view with replayed state.

**Everything works automatically from there:**
- **X button** → `unsubscribe()` + dismiss → back to Discoveries. Session continues.
- **"Discover More"** → `viewModel.discoverMore(type:)` → picker over streaming view. Cancel returns to streaming. Full experience.
- **Session completes** → `handleSessionEvent` receives `.complete` → streaming view shows finished discovery. Audio modal may show if it's the first discovery.
- **Auto-dismiss** → `hasEnteredActivePhase` is set on `.onAppear` (phase is `.analyzing`). Works correctly.

**Effort:** ~25 lines for `attachToSession()` + ~15 lines for the tap handler.

#### 6.5 Memory management

Each active session holds in memory:
- `accumulatedEvents` — streaming tokens, metadata, status messages (~10-50 KB per session)
- `PendingDiscoveryRequest.media` — the captured photo (~2-5 MB per session)

With max 3 concurrent: ~6-15 MB total. Acceptable.

When a session completes and the discoveries list has refreshed:
- Remove from `activeSessions` dictionary
- Remove from `inProgressItems`
- `accumulatedEvents` and media data are freed
- Queued sessions (4th+) start processing as slots open

#### What Phase 6 Achieves

- All processing discoveries visible on the Discoveries tab
- Tap any in-progress session to reconnect via the same modal (full streaming view, "Discover More", audio controls)
- Tap completed sessions to open normal discovery detail
- Up to 3 concurrent sessions, rest queued
- Session manager properly tracks all sessions independently (no more single-slot overwrite bug)

---

## Phase Summary

| Phase | Effort | Risk | Impact |
|-------|--------|------|--------|
| 1: Modal presentation | Medium | Medium | Eliminates overlay, dual views, isOverlay, both credits bugs |
| 2: In-modal "Discover More" | Small | Low | Eliminates dismiss/re-present, cancel returns to streaming |
| 3: Convert closures to publishers | Small | Low | Eliminates stale-closure risk |
| 4: Extract coordinator | Medium | Low | MainTabView → ~150 lines |
| 5: Break up ViewModel | Large | Medium | 1700-line ViewModel → 4 focused components |
| 6: In-progress discoveries | Medium | Low | Multi-session support, reconnect via same modal |

**Recommended grouping:** Phases 1-2 are tightly coupled and should be done together. Phase 3 in the same or next PR. Phase 4 in a separate PR. Phase 5 as 3-4 incremental PRs. Phase 6 can be done any time after Phase 2 (needs `discoverMore()` + multi-session refactor).

---

## Design Decisions (Resolved)

1. **Multiple concurrent sessions: Yes.** Users should be able to queue several discoveries. SessionManager tracks all active sessions. Each appears in the Discoveries tab's in-progress section.

2. **Photo capture trigger: Immediate.** Tapping Camera/Gallery tab opens the picker immediately. No CTA screen or intermediate step. This matches the current Camera tab behavior and keeps the action count minimal.

3. **In-progress queue location: Discoveries tab only.** Not split across Camera/Gallery tabs. The queue shows all in-progress discoveries regardless of origin (camera or gallery). Camera and Gallery tabs are stateless action triggers.

4. **"Discover More" — dual options only on audio modal.** The audio generating modal (first discovery) offers two options: "Take a Photo" and "Upload Another". The streaming view's "Discover More" button remains a single action that re-triggers the same flow type (camera → camera, upload → upload). This keeps the streaming view simple and avoids adding UI complexity for a marginal benefit — the user already chose their preferred capture method.

5. **Tab bar during analysis: Accept fullScreenCover.** User can dismiss the modal to browse, and re-open any in-progress discovery from the Discoveries tab.

6. **Credits refresh bug: Resolved by architecture, plus defensive fix.** The root cause (Path B — MainTabView presenting credits separately) is eliminated by Phase 1. Additionally, `syncCreditBalance()` should also update `isInIntroMode` as a belt-and-suspenders fix.

7. **"Discover More" stays in-modal (2026-02-06).** The ViewModel's `discoverMore(type:)` opens the picker over the streaming view. No dismiss/re-present. Cancel returns to streaming. See `discover-more-cancel-behavior.md`.

8. **Session manager: parallel, not queued (2026-02-06).** Edge functions process requests concurrently. Up to 3 sessions run in parallel on the client. 4th+ are queued until a slot opens. The `activeSession` single-slot is replaced with `activeSessions` dictionary.

9. **Reconnect uses the same modal, not a lightweight view (2026-02-06).** Tapping an in-progress session on the Discoveries tab opens the exact same `DiscoveryCreationFlowView` modal via `attachToSession()`. Full functionality: streaming, "Discover More", audio, credits. No separate reconnect view needed.

---

## Implementation Gaps (Pre-Development Checklist)

The following gaps were identified by cross-referencing the migration plan against the actual source code. None are architectural blockers — they are implementation details and edge cases that must be addressed during development.

### Gap 1: ViewModel Lifecycle Across Modal Presentations

**Problem:** `cameraViewModel` and `uploadViewModel` are long-lived objects created in `RootContentView`. When the user dismisses a modal and starts a new flow, the same ViewModel instance is reused. The plan doesn't document the reset path.

**Code verification:** `unsubscribe()` (DiscoveryCreationFlowViewModel.swift:256) sets `flowState = .idle` at the end. `startFlow()` (line 210) has a `canStartFlow()` guard that checks `flowState` — if the previous flow left the ViewModel in `.analyzing` (now running in background via SessionManager), `canStartFlow()` could block the new flow.

**Resolution:** `unsubscribe()` already resets to `.idle`, so this works. However, implementers must ensure that every modal dismiss path calls `unsubscribe()` before the next `startFlow()`. Document this invariant: **dismiss modal → `unsubscribe()` → ViewModel is `.idle` → next `startFlow()` succeeds.**

**Risk:** Medium — if missed, the user taps Camera and nothing happens.

### Gap 2: Mini Player and Toasts Must Render Inside the Modal

**Problem:** `MiniPlayerVisibilityWrapper` and `UnifiedToastOverlay` are rendered in MainTabView's ZStack (z-indices 2 and 3). With the creation flow as a `fullScreenCover`, these are hidden behind the modal. The current behavior must be preserved:

**Current mini player behavior** (from `MiniPlayerVisibilityWrapper`):
- **Hidden** during: `.capturingInitial`, `.capturingRetake`, `.selectingInitial`, `.selectingRetake`, `.confirming`, `.requestingPermissions`
- **Visible** during: `.analyzing` (streaming) — z-index 2 puts it above the creation overlay
- The streaming view already accounts for mini player space via `MiniPlayerFillerView`

**Current toast behavior:**
- Toasts render in MainTabView's ZStack above everything
- Background session completions show toasts immediately

**Resolution:** Both the mini player and toast overlay must be rendered **inside** the creation flow modal, not left in MainTabView:

```swift
// Inside DiscoveryCreationFlowView (the modal):
ZStack {
    // Main creation flow content
    creationFlowContent

    // Mini player — same visibility logic as current MiniPlayerVisibilityWrapper
    // Hidden during confirming, visible during analyzing/streaming
    if shouldShowMiniPlayer {
        MiniPlayerOverlay(controller: dependencies.playbackController)
    }

    // Toast overlay — shows background session completions
    UnifiedToastOverlay(...)
}
```

The mini player visibility logic from `MiniPlayerVisibilityWrapper.shouldShow` carries over directly — it already checks `activeOverlayPhase` to hide during confirmation. In the modal, this becomes checking `viewModel.flowState.phase` instead.

MainTabView's mini player and toast overlay continue to exist for when no modal is showing (user is browsing tabs).

**Risk:** Medium — requires wiring `audioServices` and toast state into the modal. The `CreationFlowDependencies` struct (Gap 5 in the original plan) must include `playbackController` and `miniPlayerPresence` (it already lists `playbackController`). Toast state needs `DiscoverySessionManager.pendingCompletionToasts` access.

### Gap 3: Camera/Gallery Tab Fallback Content

**Problem:** Phase 1.5 uses `Color.clear` for Camera/Gallery tab content. If the `fullScreenCover` dismisses and `selectedTab` somehow stays on `.camera` (timing edge case), the user sees a blank screen. Also, during the dismiss animation, the blank tab is briefly visible.

**Resolution:** Use a minimal branded placeholder instead of `Color.clear` — the tab icon centered on the app background color with a subtle "Tap to discover" label. This costs nothing and prevents a blank-screen edge case.

```swift
// Camera tab content — branded fallback
CameraTriggerPlaceholder()
    .tag(Tab.camera)
    .tabItem { Label("Camera", systemImage: "camera.fill") }
```

The `onDismiss: { selectedTab = .discoveries }` callback handles the common case, but the placeholder is a safety net.

**Risk:** Low — cosmetic only.

### Gap 4: Tab Re-Selection Edge Case

**Problem:** The plan triggers modal presentation via `.onChange(of: selectedTab)`. If `selectedTab` is already `.camera` and the user taps the Camera tab icon again, `.onChange` doesn't fire (value didn't change), so the picker won't re-present.

**Resolution:** The plan's `onDismiss: { selectedTab = .discoveries }` already handles this — after every modal dismiss, the selected tab resets to Discoveries. So the next Camera tap always represents a value change (`.discoveries` → `.camera`).

**Invariant to enforce:** Every modal dismiss path MUST set `selectedTab = .discoveries`. This includes:
- Normal dismiss (X button)
- "Discover More" dismiss-and-re-present cycle
- Credits exhausted "Not now" dismiss
- Permission denied dismiss

**Risk:** Low — if the invariant holds, this is fully covered.

### Gap 5: Unused CTA Parameters After Migration

**Problem:** `DiscoveryCreationFlowView` currently takes `placeholderEmoji`, `ctaTitle`, and `retryTitle` parameters (line 82-84) for the idle/CTA screen shown before the user captures a photo. With pure-trigger tabs, the user has already captured a photo before the modal appears — these parameters are never displayed.

**Resolution:** Remove `placeholderEmoji`, `ctaTitle`, and `retryTitle` from `DiscoveryCreationFlowView`'s init in Phase 1.4. The modal starts in the confirming state, not the idle/CTA state. Also remove the idle/CTA stage view from the modal's body — it's unreachable.

**Risk:** Low — dead code removal.

### Gap 6: Tab → Modal Presentation Flash

**Problem:** When `selectedTab` changes to `.camera`, the body re-evaluates (briefly showing the Camera tab content), then `.onChange` fires and presents the `fullScreenCover`. There may be a visible flash of the tab content before the modal appears.

**Resolution:** Mitigated by Gap 3 (branded placeholder instead of blank screen). The placeholder looks intentional during the brief flash. For extra polish, consider using `withAnimation(.none)` around the tab switch to suppress the transition, or present the modal with a matched geometry transition.

**Risk:** Low — cosmetic only.

### Gap 7: Non-Creation-Flow State in MainTabView (Phase 4)

**Problem:** Phase 4's code sketch for the simplified MainTabView only shows tab routing and the creation flow fullScreenCover. But MainTabView also manages:
- `audioGuidesTargetDiscoveryId` / `audioGuidesTargetDiscoverySummary` (Audio Guides → Discovery navigation)
- `pendingDiscoveryId` / `awaitingSummaryId` / `summaryFallbackTask` (discovery ID → summary resolution)
- Audio guides display mode state
- `onScreenSafetyChanged` callback for compliance overlay deferral

**Resolution:** Phase 4 should explicitly state: "Non-creation-flow state (audio guides navigation, discovery summary resolution, screen safety tracking, toast management) remains in MainTabView. The coordinator only handles creation flow orchestration." These responsibilities could be extracted into their own coordinators in a future cleanup, but they are out of scope for this redesign.

**Risk:** Low — just a documentation gap.

### Gap 8: Scene Phase / Backgrounding During Modal

**Problem:** `DiscoveryCreationFlowView` declares `@Environment(\.scenePhase) private var scenePhase` but the plan doesn't address app backgrounding/foregrounding behavior during the modal.

**Resolution:** Already handled by existing infrastructure:
- `DiscoverySessionManager` continues processing in background
- Event accumulation captures events while UI is inactive
- `subscribe()` replays accumulated events on re-subscription

The modal itself is a SwiftUI `fullScreenCover` and survives app backgrounding. No code change needed, but add backgrounding/foregrounding scenarios to the testing checklist.

**Risk:** Low — already works, just needs testing.

### Gap 9: Permission Denied → Settings → Return Flow

**Problem:** With the creation flow as a modal, if camera permission is denied, the user sees an alert with a "Go to Settings" link. They leave the app, grant permission, and return. The modal is still presented and needs to properly retry the flow.

**Resolution:** The current code handles this in the ViewModel — `beginFlow()` checks permission state on each call. When the user returns from Settings, they can tap "Try Again" (the `retryTitle` button) which calls `startFlow()` again. This should work identically in the modal. Add to testing checklist.

**Risk:** Low — existing behavior, just needs verification in modal context.

### Gap Summary

| # | Gap | Severity | Phase | Action |
|---|-----|----------|-------|--------|
| 1 | ViewModel lifecycle / reset path | Medium | 1 | Document dismiss → unsubscribe → idle invariant |
| 2 | Mini player + toasts inside modal | Medium | 1 | Render both inside fullScreenCover, preserve phase-based visibility |
| 3 | Camera/Gallery tab fallback content | Low | 1 | Branded placeholder instead of Color.clear |
| 4 | Tab re-selection edge case | Low | 1 | Enforce selectedTab = .discoveries on all dismiss paths |
| 5 | Unused CTA parameters | Low | 1 | Remove placeholderEmoji, ctaTitle, retryTitle |
| 6 | Tab → modal presentation flash | Low | 1 | Mitigated by branded placeholder (Gap 3) |
| 7 | Non-creation-flow state in MainTabView | Low | 4 | Document what stays in MainTabView |
| 8 | Backgrounding during modal | Low | 1 | Add to testing checklist |
| 9 | Permission denied in modal | Low | 1 | Add to testing checklist |

---

## Testing Strategy

### For Each Phase

1. **Full onboarding regression:**
   - Pre-onboarding → sign up → welcome screen → camera → first discovery → audio modal → second discovery → third discovery → credits exhausted → purchase → post-purchase config → continue

2. **Edge cases:**
   - Cancel camera/photo picker at each stage
   - Background the app during streaming → return to foreground → modal still shows, events replayed
   - Dismiss creation flow during streaming (session continues, toast on background completion)
   - Purchase credits during confirmation
   - "Discover More" from streaming view (re-triggers same flow type)
   - "Discover Another" from audio modal (offers camera + upload options)

3. **Credits refresh path:**
   - Credits at 0 → purchase → return to confirm → credits updated, audio toggle unlocked
   - Credits exhausted modal → "Unlock" → purchase → return → confirm screen shows updated credits

4. **Permissions:**
   - First camera use: camera permission prompt
   - Second camera use: location permission prompt on confirm
   - After purchase: notification permission prompt on confirm
   - Camera permission denied → Settings → grant → return → tap retry → flow starts

5. **Modal lifecycle (new):**
   - Dismiss modal → tap Camera tab → modal re-presents (tab re-selection works)
   - Dismiss modal → verify selectedTab is .discoveries
   - Camera flow → dismiss → Upload flow → dismiss → Camera flow (ViewModel properly resets each time)
   - Start Camera flow → dismiss during confirmation → start another → `canStartFlow()` succeeds
   - Background app during confirmation → return → modal still showing with all state intact

6. **Mini player inside modal (new):**
   - Play audio → start camera flow → confirmation screen: mini player hidden
   - Play audio → start camera flow → streaming/analyzing: mini player visible above content
   - Mini player tap during streaming → navigates to Audio Guides (dismiss modal? or deferred?)
   - Dismiss modal while audio playing → mini player visible on MainTabView as before

7. **Toasts inside modal (new):**
   - Start discovery A → "Discover More" → start discovery B → A completes in background → toast visible inside modal
   - Toast "View Discovery" action while modal is showing → dismiss modal → navigate to discovery

8. **Visual polish (new):**
   - Tab tap → modal presentation transition (no blank screen flash)
   - Camera/Gallery tab content never visible as blank to user

---

## Supporting Document

- **[feature-preservation-checklist.md](./feature-preservation-checklist.md)** — Every feature and behavior that must survive the migration, organized by user journey, with risk ratings.
