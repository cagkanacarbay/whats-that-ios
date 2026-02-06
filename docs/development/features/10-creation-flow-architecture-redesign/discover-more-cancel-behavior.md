# Discover More: Cancel Picker Behavior

> **Decision: Approach 1 selected.** See "Selected Design" section at the bottom for the finalized behavior.

## Problem

When a user is viewing a streaming discovery and taps "Discover More", a camera or photo picker opens. If they cancel the picker (change their mind), the modal dismisses entirely and they land on the Discoveries tab. They've been kicked out of their streaming view with no way back.

The discovery continues in the background and eventually appears in the feed, but the user lost their live view of it for no reason — they just decided not to take a second photo.

**Before Phase 2:** `PreservedStreamingState` (~135 lines) captured the analysis state, confirmation state, media, and session ID before starting the new capture. On cancel, it re-subscribed to the session manager, replayed accumulated events, handled race conditions for sessions that completed or failed during the gap, and restored the streaming view. This worked but was fragile — race windows between status checks and re-subscribing, multiple code paths for completed/failed/processing states, and tight coupling between the ViewModel's local state and the session manager.

**After Phase 2:** PreservedStreamingState was removed. Cancel picker = dismiss modal = Discoveries tab. Simpler code, worse UX.

## Desired Feature

Cancel picker after "Discover More" should return the user to the streaming view showing their current discovery. The session is already running in the background — the data is there. The question is how to get the UI back to showing it.

## Architectural Issue

The current "Discover More" flow goes through the parent coordinator (MainTabView):

```
Streaming View → "Discover More" button
  → onRequestNewDiscovery(type) callback to MainTabView
  → MainTabView dismisses current modal (unsubscribe, ViewModel destroyed)
  → MainTabView creates new ViewModel + presents new modal
  → New modal starts camera/picker
  → Cancel picker → flow goes idle → auto-dismiss → Discoveries tab
```

The problem is structural: the old modal is destroyed before the picker even opens. By the time the user cancels, there's nothing to go back to. Any solution needs to either:

1. Not destroy the old modal in the first place, or
2. Be able to recreate it from session data

## Potential Approaches

### Approach 1: Present picker within the same modal

The streaming view stays mounted. "Discover More" presents the camera/photo picker **over** the streaming view (system camera/picker UI naturally overlays everything). The session stays subscribed — events keep flowing to `analysisState` behind the picker.

- **Cancel picker** → picker dismisses, streaming view is right there, fully up-to-date
- **Take photo** → unsubscribe from old session, transition to confirmation with new photo

```
[fullScreenCover Modal]
  └── [Streaming View] ← stays mounted, keeps receiving session events
        └── [System Camera/Picker] ← presented over it
             Cancel → just dismiss picker, streaming view unchanged
             Photo  → unsubscribe old session, proceed to confirmation
```

**Implementation:** Add a `discoverMore(type:)` method to the ViewModel that calls `captureService.capturePhoto()` or `selectionService.selectPhoto()` directly without going through `startFlow()` / `beginFlow()`. No flowState change — the streaming view stays visible. On success, clear old state and call `prepareConfirmation()`. On cancellation, do nothing.

```swift
func discoverMore(type: DiscoveryCreationFlowType) {
    Task {
        do {
            let media: DiscoveryCapturedMedia
            switch type {
            case .camera:
                guard await captureService.requestPermission(for: .camera) else { return }
                media = try await captureService.capturePhoto()
            case .upload:
                guard await selectionService.requestPermission() else { return }
                media = try await selectionService.selectPhoto()
            }
            // User committed to new photo — detach from old session
            if let sessionId = currentSessionId {
                DiscoverySessionManager.shared.unsubscribe(from: sessionId)
                currentSessionId = nil
            }
            // Proceed with new flow
            analysisState = nil
            confirmationState = nil
            await prepareConfirmation(with: media)
        } catch {
            if DiscoveryFlowCancellationError.isCancellation(error) {
                // User cancelled picker — streaming view is still showing, nothing to do
                return
            }
            // Handle real errors
        }
    }
}
```

**Changes required:**
- New `discoverMore(type:)` method on ViewModel (~20 lines)
- Streaming view's "Discover More" button calls ViewModel directly instead of `onRequestNewDiscovery`
- Remove `onNewDiscovery` callback from `DiscoveryStreamingStageView` (or repurpose)
- `canStartFlow` unchanged — `discoverMore` bypasses it entirely

**Pros:**
- Zero state preservation — streaming view literally never unmounts
- No re-subscribing, no replay, no race conditions
- Session events flow naturally with no gap
- Simplest implementation

**Cons:**
- "Discover More" no longer goes through parent coordinator — lives in ViewModel/FlowView
- ViewModel handles capture from analyzing state (new code path alongside `beginFlow`)
- If "Discover More" should offer camera/upload choice, the streaming view needs UI for that
- Permission denied handling needs to work without changing flowState

---

### Approach 2: Dismiss and recreate from session data

"Discover More" works as today — dismiss modal, present new one. But if the user cancels the picker, MainTabView checks for a previous running session and recreates a modal pointed at it.

Session manager would need to store enough to recreate the streaming view:
- Session ID (already stored)
- Captured image data (new — for the streaming view header)
- Flow type (new)
- Media metadata like `createdAt` (new)

```
[Modal A: Streaming] → "Discover More" → dismiss Modal A
[Modal B: Camera]    → cancel picker
  → MainTabView checks for previous session
  → creates new ViewModel, calls attachToSession(sessionId)
[Modal A': Streaming] ← re-subscribes, replays events
```

**Implementation:** Expand `DiscoverySessionManager` to store per-session display data. Add an `attachToSession()` method on ViewModel that subscribes and rebuilds state from replayed events. MainTabView tracks "previous session ID" and recreates on cancel.

**Pros:**
- Clean separation — each modal is single-purpose
- MainTabView orchestrates, ViewModel stays a single-session entity
- Session manager as source of truth

**Cons:**
- Session manager scope grows (stores image bytes, UI metadata)
- Re-subscribing triggers full event replay — brief content flash as `analysisState` rebuilds
- Race window between Modal B dismiss and Modal A' present (animation timing)
- More orchestration code in MainTabView
- Image data held in session manager memory (several MB per session)
- Essentially rebuilds PreservedStreamingState's complexity but in a different location

---

### Approach 3: Modal stack

Keep the streaming modal presented. "Discover More" presents a second modal **over** the first. Cancel dismisses the second; the first is untouched underneath.

```
[Modal A: fullScreenCover, Streaming] ← stays presented
  └── [Modal B: sheet/cover, Camera] ← presented over Modal A
       Cancel → dismiss Modal B, Modal A still showing
       Photo  → dismiss both, present fresh Modal C
```

**Pros:**
- Streaming view survives in the hierarchy — no state management needed
- No re-subscribing or replay

**Cons:**
- SwiftUI doesn't support stacking `fullScreenCover` on `fullScreenCover` reliably
- Would need `.sheet` for the second modal (doesn't cover full screen)
- Dismissing both modals for the new flow path is awkward (dismiss inner, then outer, then present new)
- Deep view hierarchy, fragile presentation stack
- Platform behavior varies across iOS versions

---

## Recommendation

**Approach 1** is the strongest option. It eliminates the problem at the root — the streaming view never goes away, so there's nothing to preserve or recreate. The implementation is small, the mental model is simple ("picker overlays the streaming view"), and it avoids all the race conditions that made PreservedStreamingState complex.

The main trade-off is that "Discover More" becomes a ViewModel-level operation rather than a parent-coordinated flow. This is arguably correct — starting a new capture while viewing results is a ViewModel concern, not a navigation concern.

---

## Selected Design: Approach 1 — Present Picker Within Same Modal

**Decision date:** 2026-02-06

Approach 1 was selected after analysis of all three options. The key insight is that system camera and photo picker view controllers naturally present *over* the current SwiftUI view, so the streaming view never needs to unmount.

### Exact Behavior

**Cancel at picker (no photo taken):**
```
Streaming view (session A running, events flowing)
  → "Discover More" → picker opens OVER streaming view
  → Cancel picker → discoverMore() catches cancellation, returns silently
  → Streaming view is still there, still receiving session A events
  → Nothing changed. User is right where they were.
```

**Take a photo (commit to new discovery):**
```
Streaming view (session A running)
  → "Discover More" → picker opens OVER streaming view
  → Take photo → discoverMore() unsubscribes from session A, clears analysis state
  → prepareConfirmation() → flowState = .confirming(newPhotoState)
  → Same modal now shows confirmation screen for the new photo
  → Session A continues in background, appears in feed when done
```

**Cancel at confirmation (after taking new photo):**
```
Confirmation screen (session A running in background, unsubscribed)
  → Cancel (X button) → cancelFlow() + dismissModal()
  → User lands on Discoveries tab
  → Session A finishes in background, appears in feed
  → Cannot return to session A's streaming view (acceptable — user made an affirmative choice to take a new photo)
```

### Two Entry Points

1. **Streaming view's "Discover More" button** — calls `viewModel.discoverMore(type: viewModel.flowType)` directly. Re-triggers the same flow type (camera→camera, upload→upload).

2. **Audio generating modal's buttons** — "Take a Photo" / "Upload Another" dismiss the audio modal sheet. On sheet dismiss, calls `viewModel.discoverMore(type: chosenType)`. The picker then opens over the streaming view.

### Implementation Changes

1. **New `discoverMore(type:)` method on ViewModel** (~25 lines):
   - Requests permission (camera or photo library)
   - On permission denied: set `error`, return (streaming view stays, alert shows over it)
   - Calls capture/selection service directly (no flowState change — streaming view stays visible)
   - On cancel: return silently
   - On success: unsubscribe from old session, clear analysis state, call `prepareConfirmation(with:)`
   - On real error: set `error` (streaming view stays)

2. **DiscoveryCreationFlowView changes**:
   - Streaming view's `onNewDiscovery` callback calls `viewModel.discoverMore(type: viewModel.flowType)` instead of `onRequestNewDiscovery?(viewModel.flowType)`
   - Audio modal's `onDismiss` calls `viewModel.discoverMore(type:)` instead of `onRequestNewDiscovery?(type)`
   - Remove `onRequestNewDiscovery` callback from init (no longer needed)

3. **MainTabView changes**:
   - Remove `handleNewDiscoveryRequest()` method
   - Remove `onRequestNewDiscovery` parameter from DiscoveryCreationFlowView instantiation
   - `pendingCreationFlowAfterDismiss` / `isDismissingModal` infrastructure stays (still needed for tab taps during dismiss animations)

### Why Not the Others

- **Approach 2** (recreate from session data) rebuilds PreservedStreamingState's complexity in a different location. Same race conditions, different address.
- **Approach 3** (modal stack) relies on stacking `fullScreenCover` on `fullScreenCover`, which is unreliable in SwiftUI across iOS versions.
