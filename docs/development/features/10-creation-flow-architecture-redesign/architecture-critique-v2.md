# Architecture Critique v2 — With Onboarding Revamp Analysis

This document extends the original `architecture-critique.md` with a thorough analysis of the onboarding revamp (Feature #08) interactions, specific gaps in the migration plan, and concrete solutions.

---

## Original Critique: Still Valid

Everything in `architecture-critique.md` stands. The problems are real:

1. **Triple view instantiation** — DiscoveryCreationFlowView in 3 places
2. **Stale closure risk** — 6 callbacks assigned in `.onAppear`
3. **God view** — MainTabView at ~700 lines with 9+ responsibilities
4. **Dangerous side effects** — `handleTabChange` starts/cancels flows
5. **"Discover Another" nightmare** — 10-step state machine
6. **God ViewModel** — DiscoveryCreationFlowViewModel at ~1700 lines

The proposed modal-based architecture solves all of these. But the migration plan has gaps that, if not addressed, will break the onboarding revamp features.

---

## Gap 1: Credits Exhausted Presentation Hierarchy

### The Problem

The `CreditsExhaustedFullScreenView` is currently presented at MainTabView level:

```
MainTabView
  .fullScreenCover(isPresented: $showFreeCreditsExhaustedModal)
    → CreditsExhaustedFullScreenView
```

The migration plan says "Credits sheet presented from modal directly" but doesn't address that this is a `fullScreenCover` (not a sheet) and it needs to be presented from within the creation flow modal.

### Why It Matters

The credits exhausted screen is the primary conversion mechanism. It shows the user's 3 recent discoveries and offers "Unlock 100 Discoveries." If this breaks or looks wrong, conversion drops.

### Solution

Present the exhausted view as a `fullScreenCover` from `DiscoveryCreationFlowView`:

```swift
// In DiscoveryCreationFlowView (the modal):
.fullScreenCover(isPresented: $viewModel.showFreeCreditsExhaustedAtConfirm) {
    CreditsExhaustedFullScreenView(
        discoveries: recentDiscoveries,  // passed as dependency
        playbackController: playbackController,  // passed as dependency
        onGetCredits: { ... },
        onDismiss: { ... }
    )
}
```

This eliminates the MainTabView interception (`onChange` of `showFreeCreditsExhaustedAtConfirm`) and the flag-bouncing pattern where MainTabView resets the ViewModel flag immediately.

**Dependencies needed:** The creation flow modal needs `recentDiscoveries` and `playbackController`. These should be injected when the modal is presented, not captured via closures.

### Current (Complex)
```
ViewModel sets flag → MainTabView.onChange catches → resets VM flag → sets own flag → presents
```

### New (Simple)
```
ViewModel sets flag → DiscoveryCreationFlowView presents directly
```

---

## Gap 2: "Create Another" from Audio Modal

### The Problem

The migration plan says: "Discover Another = dismiss + re-present. No state preservation needed."

This is correct in principle but missing the specific mechanics. The audio generating modal appears WITHIN the creation flow modal. User flow:

```
Creation flow modal (fullScreenCover)
  → Discovery streaming completes
  → Audio modal appears (sheet)
    → User taps "Create Another"
```

### The Tricky Part

You can't present a new `fullScreenCover` while dismissing the current one. The dismiss animation must complete first.

### Solution

```swift
// In the creation flow modal:
.sheet(isPresented: $viewModel.showAudioGeneratingModal, onDismiss: {
    if shouldCreateAnother {
        shouldCreateAnother = false
        // Tell the coordinator to start a new flow
        // The coordinator dismisses this modal and presents a new one
        onRequestNewDiscovery?()
    }
}) {
    AudioGeneratingModalView(
        onCreateAnother: {
            shouldCreateAnother = true
            viewModel.showAudioGeneratingModal = false
        },
        onReadThisDiscovery: {
            viewModel.showAudioGeneratingModal = false
        }
    )
}
```

The coordinator (the view presenting the fullScreenCover) handles the sequencing:

```swift
// In the presenting view (camera/upload tab or coordinator):
.fullScreenCover(item: $activeCreationSession) { session in
    DiscoveryCreationFlowView(...)
        .onRequestNewDiscovery {
            // Dismiss current modal
            activeCreationSession = nil
            // After dismiss animation, start new flow
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                startNewDiscoveryFlow()
            }
        }
}
```

---

## Gap 3: Post-Onboarding Welcome Screen → Direct Camera Launch

### The Problem

When a new user taps "Take a Photo" on the welcome screen:

```
PostOnboardingCarousel
  → onLaunchCamera
  → mainTabDestination = .camera
  → viewModel.completePostOnboarding()
  → MainTabView appears with initialTab = .camera
  → handleTabChange(.camera, isInitial: true) auto-starts camera flow
```

In the new architecture, the camera tab shows a CTA button. The user would need to tap AGAIN to open the camera. This is one extra tap of friction during the most critical moment — the user's first discovery.

### Solution

Add a `pendingAction` property to the tab coordinator:

```swift
enum PendingTabAction {
    case launchCamera
    case launchUpload
}

// When tab appears and pendingAction is set:
.onAppear {
    if let action = pendingAction {
        pendingAction = nil
        switch action {
        case .launchCamera:
            presentCreationFlow(type: .camera)
        case .launchUpload:
            presentCreationFlow(type: .upload)
        }
    }
}
```

This preserves the zero-friction experience. The user taps "Take a Photo" on the welcome screen and the camera modal appears immediately.

---

## Gap 4: Nested Sheet Presentation After Purchase

### The Problem

After purchasing credits, the flow is:
```
Creation modal (fullScreenCover)
  → Credits sheet (sheet)
    → StoreKit purchase
    → Post-purchase config (fullScreenCover from credits sheet)
      → Voice selection
      → IPoP preferences
      → Done → dismiss post-purchase
    → Done → dismiss credits sheet
  → Back to creation modal
  → refreshStateAfterCreditsSheet() must fire
```

The credits refresh bug (documented in Feature #08) happens because the `.onChange(of: activeSheet)` doesn't always fire when dismissing nested presentations.

### This Bug Exists Today

The architecture redesign doesn't make this worse. The dismiss chain is identical:
- sheet (credits) → fullScreenCover (post-purchase) → dismiss post-purchase → dismiss credits

### Recommendation

1. **Don't try to fix this during the architecture migration.** The bug is independent.
2. **Add the defensive fix from credits-refresh-bug-investigation.md:** Update `isInIntroMode` in `syncCreditBalance()` as well, not just in `refreshStateAfterCreditsSheet()`.
3. **Track as a separate bug fix** that can be done before or after the architecture migration.

---

## Gap 5: What Replaces handleTabChange Side Effects

### The Problem

The migration plan says "Tabs are just navigation" but doesn't specify what replaces the side effects:

```swift
case .camera:
    uploadViewModel.cancelFlow()   // Cancel upload if in progress
    cameraViewModel.startFlow()    // Auto-start camera
    activeOverlayTab = nil         // Clear overlay
```

### What Must Still Happen

When user switches tabs, we need to:
1. **Not lose in-progress sessions.** If upload is analyzing, it should continue in background.
2. **Not auto-start flows.** The user taps a CTA to start.
3. **Clean up abandoned confirmations.** If user was confirming on upload tab and switches to camera, the upload confirmation should be discarded.

### Solution

```swift
// Simplified handleTabChange:
func handleTabChange(to tab: Tab) {
    // Sessions continue in background automatically (SessionManager)
    // No auto-starting flows
    // No overlay management
    // Just track screen safety for compliance
    let isSafeScreen = (tab == .discoveries || tab == .audioGuides)
    onScreenSafetyChanged?(isSafeScreen)
}
```

Abandoned confirmations clean up naturally: when the user starts a new flow (by tapping the CTA), the previous ViewModel state is reset by `beginFlow()`. No explicit cleanup needed.

---

## Gap 6: DiscoveryStoreObserver and AudioServices in Modal

### The Problem

The creation flow modal needs access to:
- `storeObserver.discoveries` — for CreditsExhaustedFullScreenView
- `audioServices.playbackController` — for CreditsExhaustedFullScreenView audio playback
- `makeCreditsViewModel` — for credits sheet
- Voiceover/IPoP preference closures — for credits sheet post-purchase config

Currently, MainTabView passes all of these. In the new architecture, the presenting coordinator must pass them.

### Solution

Create a `CreationFlowDependencies` struct:

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

Pass this when presenting the modal. This is cleaner than the current approach where 10+ closures are passed through `DiscoveryCreationFlowView`'s init.

---

## Gap 7: Session Manager Multi-Session Support

### The Problem

The migration plan's Phase 6 (Discovery Queue) mentions multiple concurrent sessions. But `DiscoverySessionManager` currently has a single `activeSession` slot and a serial `pendingQueue`.

### Why It Matters Now

Even before the queue feature, "Discover Another" creates a second session while the first is still processing (if audio is generating). The current architecture handles this because `unsubscribe()` + `startSession()` effectively replaces the active session.

In the new architecture, dismissing the modal and presenting a new one creates a genuinely concurrent scenario: session 1 runs in background, session 2 starts in a new modal.

### Current State

`DiscoverySessionManager.startSession()` immediately starts processing and sets `activeSession`. If a session is already active, the new one doesn't queue — it starts immediately too (the queue is only used if `processNextIfAvailable` is called). Wait, looking more carefully: `startProcessing` is called directly, not via the queue. This means multiple sessions CAN run concurrently already.

The issue is that `handleCompletion` checks `activeSession?.id == request.id` and only notifies the subscriber if it matches. With concurrent sessions, only one will be treated as "active."

### Recommendation

This is fine for Phase 1-5. The current behavior works because:
1. Session 1 completes and fires `onDiscoveryCompleted` regardless of subscriber
2. Toast shows for background completions
3. Session 2 is the "active" session with the subscriber

For Phase 6 (queue), refactor `activeSession` into a dictionary of active sessions. But this is Phase 6 work, not needed initially.

---

## Gap 8: Combine Publisher Migration for Callbacks

### The Problem

Phase 3 says "Convert closures to publishers" but doesn't specify which publishers exist vs. which need to be created.

### Current Publishers
- `analysisBeganPublisher` — Already Combine (PassthroughSubject)

### Closures to Convert

| Closure | Purpose | Replacement |
|---------|---------|-------------|
| `onDiscoveryCreated` | Notify when discovery ID received | `@Published discoveryId: Int64?` or `PassthroughSubject` |
| `onDiscoverySummaryReady` | Notify when summary fetched | `@Published latestSummary: DiscoverySummary?` |
| `onPollingDiscoveryReady` | Notify when polling finds discovery | Same as above — unify with summary |
| `onStateRestored` | Restore overlay after cancel | **Eliminated** in new architecture |
| `onAnalysisBegan` | Switch to overlay mode | **Eliminated** — modal is already presented |

### Simplified Observable State

```swift
// On DiscoveryCreationFlowViewModel:
@Published private(set) var completedDiscovery: DiscoverySummary?

// The coordinator observes this and handles upsert/refresh
.onReceive(viewModel.$completedDiscovery.compactMap { $0 }) { summary in
    Task { await storeObserver.upsert(summary) }
}
```

This replaces `onDiscoveryCreated`, `onDiscoverySummaryReady`, and `onPollingDiscoveryReady` with a single published property.

---

## Updated Migration Plan

See `updated-migration-plan.md` for the revised phase-by-phase plan with all gaps addressed.
