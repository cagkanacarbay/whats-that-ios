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

6. **"Discover More" offers both entry points.** From the streaming/complete view, the user gets two options: "Take a Photo" (opens camera picker) and "Upload Another" (opens photo picker). This starts a new creation flow directly — no need to dismiss and navigate to a tab. The current discovery continues via SessionManager in the background. Implementation: dismiss the current modal, present the appropriate picker as a new fullScreenCover. The previous session keeps running and appears in the Discoveries queue.

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

## Migration Plan

### Phase 1: fullScreenCover Presentation (Highest Impact)

- Present creation flow as `fullScreenCover` when user captures/selects a photo
- Remove the overlay ZStack from MainTabView
- Remove `activeOverlayTab`, `isOverlay`, `shouldShowOverlay()`
- Remove `handleAnalysisBegan` tab-switch logic
- On modal dismiss, set `selectedTab = .discoveries`
- This also fixes both credits bugs (single presentation path)

### Phase 2: Camera/Gallery Tabs as Pure Triggers

- Tapping Camera tab immediately opens camera picker (fullScreenCover)
- Tapping Gallery tab immediately opens photo picker (fullScreenCover)
- Remove `DiscoveryCreationFlowView` from tab content entirely
- Remove `handleTabChange` side effects (no more auto-starting/cancelling flows)
- Tab content is minimal (empty/placeholder shown only during transitions)

### Phase 3: Discovery Queue on Discoveries Tab

- Expose active sessions from `DiscoverySessionManager` as `@Published` array
- Add "In Progress" section to `DiscoveriesHomeView` above completed discoveries
- Tapping an in-progress item presents streaming modal for that session
- Support multiple concurrent sessions

### Phase 4: Convert Closures to Publishers

- Replace remaining `.onAppear` closure assignments with Combine publishers or `.onReceive`
- Eliminate stale-closure risk entirely

### Phase 5: Extract MainTabView Orchestration

- Move creation flow coordination into a dedicated coordinator
- MainTabView becomes pure tab routing (~100-150 lines)

### Phase 6: Break Up ViewModel

- `PhotoCaptureCoordinator` — permissions, camera/picker, encoding
- `DiscoveryConfirmationViewModel` — location, credits, nearby places
- `DiscoveryStreamingViewModel` — session subscription, events, polling
- `DiscoveryCreationFlowCoordinator` — orchestrates the above

---

## Design Decisions (Resolved)

1. **Multiple concurrent sessions: Yes.** Users should be able to queue several discoveries. SessionManager tracks all active sessions. Each appears in the Discoveries tab's in-progress section.

2. **Photo capture trigger: Immediate.** Tapping Camera/Gallery tab opens the picker immediately. No CTA screen or intermediate step. This matches the current Camera tab behavior and keeps the action count minimal.

3. **In-progress queue location: Discoveries tab only.** Not split across Camera/Gallery tabs. The queue shows all in-progress discoveries regardless of origin (camera or gallery). Camera and Gallery tabs are stateless action triggers.

4. **"Discover More" offers both camera and upload.** The streaming/complete view shows two options: "Take a Photo" and "Upload Another". The user can start a new discovery via either method directly from the modal without navigating back to the tabs. The current discovery continues in the background.

5. **Tab bar during analysis: Accept fullScreenCover.** User can dismiss the modal to browse, and re-open any in-progress discovery from the Discoveries queue.

## Open Questions

All major design questions have been resolved (see Design Decisions above). No open questions remain.

---

## Follow-Up Documents

This critique has been extended with detailed onboarding revamp analysis:

- **[architecture-critique-v2.md](./architecture-critique-v2.md)** — Gaps in the migration plan when accounting for Feature #08 (onboarding revamp), with concrete solutions for each gap.
- **[feature-preservation-checklist.md](./feature-preservation-checklist.md)** — Every feature and behavior that must survive the migration, organized by user journey, with risk ratings.
- **[updated-migration-plan.md](./updated-migration-plan.md)** — Revised 6-phase migration plan with all gaps addressed, concrete code examples, and testing strategy.
