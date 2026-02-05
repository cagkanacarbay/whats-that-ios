# Feature Preservation Checklist

Every behavior, feature, and edge case that the new architecture MUST preserve. Organized by the user journey from onboarding through long-term usage.

---

## Pre-Onboarding (No Risk - Independent of Creation Flow)

These features are independent of the creation flow architecture and will not be affected:

| Feature | Current Location | Risk Level |
|---------|-----------------|------------|
| Interactive sample discovery gallery | `PreOnboardingDiscoveriesContainer` | None |
| Bottom sheet (expanded/collapsed) | `PreOnboardingBottomSheetView` | None |
| Sample audio playback | `PreOnboardingMiniPlayer` | None |
| "Create Your Own" → sign-up flow | `PreOnboardingCarousel` | None |
| "Account - Sign in" → sign-in flow | `PreOnboardingCarousel` | None |
| Legacy carousel fallback | `LegacyPreOnboardingCarousel` | None |

---

## Post-Onboarding Welcome Screen (LOW RISK)

| Feature | Current Behavior | Migration Notes |
|---------|-----------------|-----------------|
| Welcome copy variants | "Now it's your turn" (new) / "Welcome back" (returning) | No change needed |
| Camera CTA → direct camera launch | `onLaunchCamera` sets `mainTabDestination = .camera` | In new arch: `mainTabDestination = .camera` triggers CTA on camera tab. User must tap one more time unless we auto-present the modal on first visit. **Decision needed.** |
| Gallery CTA → direct gallery launch | `onLaunchUpload` sets `mainTabDestination = .upload` | Same as camera - one extra tap unless auto-triggered. |
| Skip all configuration | No voice/IPoP setup during onboarding | No change needed |

### Migration Decision: First-Time Auto-Launch

Currently, selecting "Take a Photo" from the welcome screen immediately opens the camera picker because `handleTabChange(.camera)` calls `cameraViewModel.startFlow()`.

In the new architecture, the camera tab shows a CTA. Options:
1. **Auto-present modal on first visit** — Check a "hasSeenCameraTab" flag, auto-trigger modal. Simple but adds a flag.
2. **Accept the extra tap** — User sees the CTA and taps it. Consistent behavior but one more tap on first use.
3. **Keep auto-start for camera/upload tabs only on initial tab selection** — `mainTabDestination` triggers one-time auto-start.

**Recommendation:** Option 3. When `mainTabDestination` is `.camera` or `.upload` (set by PostOnboardingCarousel), auto-present the modal on tab appear, then reset the flag. This preserves the zero-friction first discovery experience.

---

## Intro Mode System (HIGH RISK - Core Business Logic)

The intro mode system is deeply woven into `DiscoveryCreationFlowViewModel`. Every item below MUST work identically after migration.

### FreeCreditsAlertTracker State

| State Variable | Purpose | Used In |
|----------------|---------|---------|
| `isInIntroMode` | Audio toggle locked ON, discovery limit enforced | `prepareConfirmation()`, `refreshStateAfterCreditsSheet()` |
| `introDiscoveryCount` | Tracks discoveries during intro (limit = 3) | `shouldShowCreditsExhaustedForIntroLimit()` |
| `hasMadePurchase` | Exit intro mode on purchase | `markPurchaseMade()` |
| `hasShownCreditsExhausted` | Primary intro-complete flag | `isInIntroMode` computed property |
| `hasSeenAudioGeneratingModal` | Show audio modal only once | `shouldShowAudioGeneratingModal()` |
| `hasCompletedPostPurchaseConfig` | Voice + IPoP config done | `shouldShowPostPurchaseConfig()` |
| `cameraUseCount` | Count camera uses for location permission | `requestLocationPermissionIfNeeded()` |
| `hasRequestedLocationPermission` | Location asked once | `requestLocationPermissionIfNeeded()` |
| `hasRequestedNotificationPermission` | Notifications asked once | `requestNotificationPermissionIfNeeded()` |

**Risk:** All of this state lives in `FreeCreditsAlertTracker` (a global actor) and is read by `DiscoveryCreationFlowViewModel`. The architecture redesign doesn't change the tracker or ViewModel internals, so these are safe IF the ViewModel's lifecycle and callbacks are preserved.

### Intro Discovery Limit Check

```
Current flow:
prepareConfirmation() → ... → shouldShowCreditsExhaustedForIntroLimit()
  → showFreeCreditsExhaustedAtConfirm = true
  → MainTabView.onChange catches this → showFreeCreditsExhaustedModal = true
  → CreditsExhaustedFullScreenView presented at MainTabView level
```

**Risk in new architecture:** The fullScreenCover is currently presented at MainTabView level to ensure it appears above everything. In the modal architecture, the creation flow IS a fullScreenCover. Presenting a fullScreenCover from within a fullScreenCover requires careful handling.

**Solution:** Present `CreditsExhaustedFullScreenView` from within the creation flow modal instead of from MainTabView. The creation flow modal IS the top-level presentation, so a fullScreenCover from it will work. This is actually SIMPLER than the current approach.

---

## Conditional Permissions (MEDIUM RISK)

### Camera Permission
| When | Current | New Architecture |
|------|---------|-----------------|
| First camera use | `beginFlow()` → `captureService.requestPermission()` | Same - no change |
| If denied | `error = .cameraPermissionDenied` → alert with Settings link | Same |

### Photo Library Permission
| When | Current | New Architecture |
|------|---------|-----------------|
| First gallery use | `beginFlow()` → `selectionService.requestPermission()` | Same - no change |
| If denied | `error = .photoLibraryPermissionDenied` → alert with Settings link | Same |

### Location Permission (Second Camera Use)
| When | Current | New Architecture |
|------|---------|-----------------|
| 2nd+ camera use, on confirm page | `requestLocationPermissionIfNeeded()` in `prepareConfirmation()` | Same - lives inside ViewModel |
| Check | `cameraUseCount >= 2 && !hasRequestedLocationPermission` | Same |
| After grant | `locationService.requestLocationAuthorization()` + `startTrackingIfNeeded()` | Same |

### Notification Permission (After Purchase)
| When | Current | New Architecture |
|------|---------|-----------------|
| After purchase, on confirm page | `requestNotificationPermissionIfNeeded()` in `prepareConfirmation()` | Same - lives inside ViewModel |
| Check | `hasPurchased && !hasRequestedNotificationPermission` | Same |

**All permission logic lives inside ViewModel methods, not in MainTabView.** No migration risk.

---

## Audio Generating Modal (HIGH RISK)

### Current Behavior
1. First discovery stream completes
2. `handleSuccessfulCreation()` → `shouldShowAudioGeneratingModal()`
3. `showAudioGeneratingModal = true` on ViewModel
4. `DiscoveryCreationFlowView` presents it (only when `isOverlay: true`)
5. "Create Another" → `shouldCreateAnotherAfterModalDismiss = true` → dismiss modal → `onDismiss` → `onDiscoverAnother`
6. "Read This Discovery" → dismiss modal, stay on current view

### Migration Risk

The `isOverlay` flag that gates modal presentation is eliminated. In the new architecture, there's only one instance of `DiscoveryCreationFlowView` (the modal), so it always presents the audio modal. **This is simpler and correct.**

However, "Create Another" flow changes:

| Current | New Architecture |
|---------|-----------------|
| `onDiscoverAnother` → `unsubscribe()` + `selectedTab = targetTab` + `retake()` | Dismiss audio modal → dismiss creation flow modal → present new creation flow modal |

**Key concern:** Dismissing the creation flow modal WHILE the discovery is still showing means the user loses the streaming view of their first discovery. This is acceptable because:
- The discovery is already saved in the backend
- It appears in the Discoveries tab
- The session continues in background
- In the future, the "queue" feature lets them return to it

**Solution:** "Create Another" should:
1. Dismiss audio modal
2. Dismiss creation flow modal (session continues in background via SessionManager)
3. After dismiss animation completes, present new creation flow modal
4. Use `DispatchQueue.main.asyncAfter` for timing safety

---

## Credits Exhausted Full-Screen (HIGH RISK)

### Current Flow
```
prepareConfirmation()
  → shouldShowCreditsExhaustedForIntroLimit() returns true
  → showFreeCreditsExhaustedAtConfirm = true (on ViewModel)
  → MainTabView.onChange intercepts → showFreeCreditsExhaustedModal = true
  → .fullScreenCover(isPresented: $showFreeCreditsExhaustedModal) at MainTabView level
```

### What It Shows
- User's 3 most recent discoveries (from `storeObserver.discoveries`)
- Audio playback controller for those discoveries
- "Unlock 100 Discoveries" → credits sheet
- "Not now" → dismiss + cancel flows + go to discoveries

### Migration Plan
In the new architecture, this fullScreenCover should be presented FROM the creation flow modal:

```
DiscoveryCreationFlowView (fullScreenCover from tab)
  → CreditsExhaustedFullScreenView (fullScreenCover from creation flow)
    → CreditsView (sheet from exhausted view or creation flow)
```

**Complication:** The exhausted view needs `storeObserver.discoveries` and `audioServices.playbackController`. Currently these come from MainTabView. In the new architecture, they need to be passed into the creation flow modal.

**Solution:** Pass these as dependencies when presenting the creation flow modal. The modal coordinator (Phase 4) holds references to `storeObserver` and `audioServices`.

---

## Post-Purchase Configuration (HIGH RISK)

### Current Flow
```
CreditsView (sheet)
  → Purchase completes
  → shouldShowPostPurchaseConfig = true
  → .fullScreenCover → PostPurchaseConfigurationFlow
    → Voice selection slide
    → IPoP preferences slide
    → Complete → dismiss fullScreenCover
    → close() → dismiss CreditsView sheet
```

### Nesting Problem
In the new architecture:
```
Tab → fullScreenCover (creation flow)
       → sheet (credits)
         → fullScreenCover (post-purchase config)
```

Three levels of modal nesting. SwiftUI can handle this, but dismiss ordering matters. The current code already handles this with `shouldCloseAfterPostPurchaseConfig` flag.

**Risk:** The credits refresh bug (see `credits-refresh-bug-investigation.md`) is caused by nested dismiss not properly triggering `.onChange(of: activeSheet)`. This bug exists in the current architecture and is NOT made worse by the redesign. In fact, it may improve because the creation flow is now the top-level modal and has simpler dismiss semantics.

**Recommendation:** Keep the existing PostPurchaseConfigurationFlow nesting as-is within CreditsView. It works (with the known bug caveat). Fix the credits refresh bug independently.

---

## "Discover Another" Flow (SIMPLIFIED)

### Current: 10-Step State Machine
1. `shouldCreateAnotherAfterModalDismiss = true`
2. Dismiss audio modal
3. `onDismiss` → `onDiscoverAnother`
4. `targetViewModel.unsubscribe()` (preserves state)
5. Switch `selectedTab` to camera/upload
6. `targetViewModel.retake()` (starts new capture)
7. `onChange(selectedTab)` → `handleTabChange` (async, races with retake)
8. If user cancels → `onStateRestored` fires
9. Restore `activeOverlayTab` and `selectedTab`
10. `restorePreservedStateIfAvailable()` with 3 sub-paths

### New: 3-Step Flow
1. Dismiss creation flow modal (session continues in background)
2. Present camera/gallery picker
3. If photo selected → present new creation flow modal

### What About State Restoration?

The "restore previous discovery" feature (showing the completed discovery if user cancels the new capture) is eliminated. Instead:
- Session continues in background (already implemented)
- Toast notifies when complete
- User can find it in Discoveries tab
- Future: Discovery queue on Camera/Gallery tab

**This is acceptable.** The state preservation mechanism is the single most complex piece of the current architecture. Removing it dramatically simplifies the codebase. The user doesn't lose any data — just the ability to return to the streaming view of a completed discovery after cancelling a new capture.

---

## Closure-Based Callbacks (HIGH RISK IN CURRENT, ELIMINATED IN NEW)

### Current Problem
6 closures assigned in `MainTabView.onAppear`:
- `onDiscoveryCreated`
- `onDiscoverySummaryReady`
- `onPollingDiscoveryReady` (x2)
- `onStateRestored` (x2)

These capture `self` and can go stale if SwiftUI recreates MainTabView.

### New Architecture
Replace all closures with Combine publishers or direct observation:
- `onDiscoveryCreated` → `DiscoveryCreationFlowViewModel` publishes via Combine
- `onDiscoverySummaryReady` → Direct observation of ViewModel state
- `onPollingDiscoveryReady` → Direct observation of ViewModel state
- `onStateRestored` → Eliminated (no state preservation needed)

---

## Background Session Management (NO RISK)

`DiscoverySessionManager` is already designed to be UI-independent. The new architecture leverages this existing design:

| Feature | Status |
|---------|--------|
| Session continues when UI dismissed | Already works |
| Event accumulation for replay | Already works |
| Subscribe/unsubscribe model | Already works |
| Completion toast | Already works |
| Background polling recovery | Already works |

---

## Tab Bar Visibility During Analysis (MEDIUM RISK)

### Current Behavior
The overlay leaves the tab bar visible during analysis. Users can:
- Switch to Discoveries tab to browse while waiting
- Switch to Audio Guides tab
- Tab bar provides navigation context

### New Architecture
A `fullScreenCover` hides the tab bar. Options:

1. **Use `.sheet(.large)` instead of `fullScreenCover`** — Tab bar remains visible. But `.sheet` has drag-to-dismiss which could accidentally close the creation flow.
2. **Accept hidden tab bar** — User taps [X] to dismiss and browse. Re-opens from queue.
3. **Custom presentation** — Build a custom half-sheet or overlay (complex, fragile).

**Recommendation:** Option 1 with `interactiveDismissDisabled(true)` during analysis phase. The sheet covers the full screen but can't be accidentally dismissed. Tab bar remains visible. After analysis completes, enable interactive dismiss.

**Alternative:** Use `fullScreenCover` but add a persistent mini tab bar or "Go to Discoveries" button within the analysis view.

---

## Credits Sheet from Confirmation (MEDIUM RISK)

### Current Behavior
User taps credits badge on confirmation screen → `presentCreditsSheet()` → opens CreditsView as sheet.

### Migration
In the new architecture:
```
Tab → fullScreenCover (creation flow)
       → sheet (credits)
```

This is standard SwiftUI nesting and works correctly. No change needed to `presentCreditsSheet()` logic.

### Credits Refresh After Sheet Dismiss
The `.onChange(of: activeSheet)` mechanism for triggering `refreshStateAfterCreditsSheet()` stays the same. It's within `DiscoveryCreationFlowView`, which is now the modal.

---

## Photo Save to Library (NO RISK)

`savePhotoToLibraryIfEnabled()` is called from `beginAnalysis()` in the ViewModel. No dependency on view hierarchy.

---

## Image Caching (NO RISK)

`cacheDiscoveryImageIfNeeded()` is called from `handle(event:)` in the ViewModel. No dependency on view hierarchy.

---

## Intro State Resolution for Reinstalls (NO RISK)

`resolveIntroStateIfNeeded()` runs during app startup in `AppRootViewModel`. Independent of creation flow architecture.

---

## Summary: Risk Matrix

| Feature | Risk | Action Required |
|---------|------|-----------------|
| Pre-onboarding gallery | None | No change |
| Post-onboarding welcome | Low | Handle auto-launch from welcome screen |
| Intro mode state tracking | High | Verify all FreeCreditsAlertTracker integration |
| Conditional permissions | None | All in ViewModel, no change |
| Audio generating modal | High | Redesign "Create Another" dismiss flow |
| Credits exhausted screen | High | Move from MainTabView to creation flow modal |
| Post-purchase configuration | High | Verify nested presentation works |
| "Discover Another" | Simplified | State preservation removed, replaced by background sessions |
| Closure callbacks | Eliminated | Replace with Combine publishers |
| Background sessions | None | Already designed for this |
| Tab bar during analysis | Medium | Choose presentation strategy |
| Credits sheet | Medium | Standard nested sheet, verify refresh bug |
| Photo save / caching | None | ViewModel-internal |
