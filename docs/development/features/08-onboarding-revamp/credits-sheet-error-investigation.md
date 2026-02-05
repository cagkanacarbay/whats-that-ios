# Credits Sheet Error Investigation

## Issue Summary

**Problem**: When a user in intro mode exhausts their free credits and taps "Unlock More Stories" on the credits exhausted modal, the credits sheet opens but almost always shows an error/fallback state on the first try. The user must tap "Try Again" (refresh) for the credits sheet to load properly.

**User Impact**: Poor first-purchase experience for users who have just exhausted their intro credits and are ready to buy more.

**Frequency**: "Almost always" on first try, works on subsequent retry.

---

## Investigation Overview

This document traces the complete flow from the credits exhausted modal to the credits sheet, identifies the root cause of the error state, and proposes solutions.

---

## Flow Analysis

### 1. How the Credits Exhausted Modal Appears

When a user in intro mode tries to create their 4th discovery (exceeding the intro limit of 3), the system shows the credits exhausted modal.

**Trigger Point** - `DiscoveryCreationFlowViewModel.swift`:
```swift
// Check intro discovery limit AFTER showing confirm stage.
if await tracker.shouldShowCreditsExhaustedForIntroLimit() {
    showFreeCreditsExhaustedAtConfirm = true
}
```

**Presentation** - `MainTabView.swift` (lines 385-397):
```swift
// Watch for free credits exhausted modal from either viewModel
.onChange(of: cameraViewModel.showFreeCreditsExhaustedAtConfirm) { _, show in
    if show {
        // Reset viewModel flag immediately to prevent duplicate presentation
        cameraViewModel.showFreeCreditsExhaustedAtConfirm = false
        showFreeCreditsExhaustedModal = true
    }
}
```

The `CreditsExhaustedFullScreenView` is presented as a fullScreenCover showing the user's recent discoveries with two CTAs:
- "Unlock More Stories" → Opens credits sheet
- "Maybe later" → Dismisses and cancels flow

### 2. How "Unlock More Stories" Opens the Credits Sheet

**The Critical Flow** - `MainTabView.swift` (lines 399-430):

```swift
.fullScreenCover(isPresented: $showFreeCreditsExhaustedModal, onDismiss: {
    // Present credits sheet AFTER fullScreenCover is fully dismissed
    if shouldPresentCreditsAfterDismiss {
        shouldPresentCreditsAfterDismiss = false
        if let maker = makeCreditsViewModel {
            creditsExhaustedCreditsViewModel = maker()  // Step 1: Create ViewModel
            // Small delay to ensure clean presentation after dismiss animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showCreditsSheetFromExhausted = true    // Step 2: Show sheet
            }
        }
    }
}) {
    CreditsExhaustedFullScreenView(
        discoveries: Array(storeObserver.discoveries.prefix(3)),
        playbackController: audioServices.playbackController,
        onGetCredits: {
            // Set flag to present credits sheet after this fullScreenCover dismisses
            shouldPresentCreditsAfterDismiss = true
            showFreeCreditsExhaustedModal = false
        },
        onDismiss: { ... }
    )
}
```

**Sequence of Events**:
1. User taps "Unlock More Stories"
2. `onGetCredits` callback sets `shouldPresentCreditsAfterDismiss = true`
3. `showFreeCreditsExhaustedModal = false` triggers fullScreenCover dismiss
4. fullScreenCover begins dismiss animation
5. `onDismiss` callback fires (during/after dismiss animation)
6. `creditsExhaustedCreditsViewModel = maker()` creates the ViewModel
7. 100ms delay via `asyncAfter`
8. `showCreditsSheetFromExhausted = true` triggers sheet presentation

### 3. The Credits Sheet Content

**Sheet Presentation** - `MainTabView.swift` (lines 283-313):

```swift
.sheet(isPresented: $showCreditsSheetFromExhausted, onDismiss: {
    creditsExhaustedCreditsViewModel = nil
}) {
    if let viewModel = creditsExhaustedCreditsViewModel {
        NavigationStack {
            CreditsView(
                viewModel: viewModel,
                loadVoiceoverPreferences: ...,
                // ... other closures
            )
        }
        .presentationDetents([.fraction(0.8), .large])
    } else {
        // Fallback view if credits view model failed to initialize
        CreditsSheetErrorView(
            onRetry: {
                if let maker = makeCreditsViewModel {
                    creditsExhaustedCreditsViewModel = maker()
                }
            },
            onDismiss: {
                showCreditsSheetFromExhausted = false
            }
        )
        .presentationDetents([.fraction(0.5)])
    }
}
```

**Key Observation**: The sheet content checks `if let viewModel = creditsExhaustedCreditsViewModel`. If this is `nil` when evaluated, the fallback `CreditsSheetErrorView` is shown instead of `CreditsView`.

### 4. The Fallback Error View

**CreditsSheetErrorView** - `MainTabView.swift` (lines 699-756):

```swift
private struct CreditsSheetErrorView: View {
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle")

            Text("Something went wrong")
            Text("We couldn't load the credits page. Please try again.")

            // "Try Again" button - calls onRetry
            Button(action: onRetry) {
                Text("Try Again")
            }

            // "Close" button - calls onDismiss
            Button(action: onDismiss) {
                Text("Close")
            }
        }
    }
}
```

When the user taps "Try Again":
```swift
onRetry: {
    if let maker = makeCreditsViewModel {
        creditsExhaustedCreditsViewModel = maker()  // Creates VM directly
    }
}
```

This creates the ViewModel while the sheet is already stable (not mid-transition), and SwiftUI re-evaluates the sheet content, now showing `CreditsView` instead of the fallback.

---

## Root Cause Analysis

### The Timing Problem

The root cause is a **SwiftUI state timing issue during fullScreenCover dismiss animation**.

**Timeline of What Happens**:

```
T+0ms:   User taps "Unlock More Stories"
         → shouldPresentCreditsAfterDismiss = true
         → showFreeCreditsExhaustedModal = false

T+0ms:   SwiftUI begins fullScreenCover dismiss animation

T+~200ms: fullScreenCover dismiss animation completes
         → onDismiss callback fires
         → creditsExhaustedCreditsViewModel = maker()  ← STATE CHANGE QUEUED

T+~300ms: asyncAfter(0.1) fires
         → showCreditsSheetFromExhausted = true
         → SwiftUI evaluates sheet content
         → Checks: if let viewModel = creditsExhaustedCreditsViewModel
         → ⚠️ MAY STILL BE NIL due to state update timing
```

**The Problem**: The `onDismiss` callback runs during or immediately after the fullScreenCover dismiss animation. When `creditsExhaustedCreditsViewModel = maker()` executes, SwiftUI queues a state update. However, the view body re-evaluation (and the sheet content closure evaluation) may happen before that state update is fully committed to the view hierarchy.

The 100ms delay was intended to give the fullScreenCover animation time to complete, but it doesn't guarantee the state change from creating the ViewModel is visible to the sheet's content closure when it's evaluated.

### Why the Second Try (Retry) Works

When the user taps "Try Again" in `CreditsSheetErrorView`:

1. The sheet is already presented and stable (no transitions in progress)
2. `creditsExhaustedCreditsViewModel = maker()` executes
3. SwiftUI immediately processes this state change
4. The sheet content closure is re-evaluated
5. Now `creditsExhaustedCreditsViewModel` is non-nil
6. `CreditsView` is shown

The key difference: **no concurrent animation/transition is interfering with state updates**.

### Evidence Supporting This Theory

1. **"Almost always" on first try** - The timing race is consistent because the fullScreenCover dismiss animation takes roughly the same time each time.

2. **Always works on retry** - No animation interference when the sheet is stable.

3. **Pattern matches known SwiftUI behavior** - SwiftUI batches state updates and may not process them immediately during view transitions.

---

## Relevant Code Files

| File | Location | Relevance |
|------|----------|-----------|
| `MainTabView.swift` | `WhatsThatPresentation/App/` | Sheet presentation, fullScreenCover, error view |
| `CreditsView.swift` | `WhatsThatPresentation/Features/Credits/` | The actual credits UI |
| `CreditsViewModel.swift` | `WhatsThatPresentation/Features/Credits/` | Loading logic, StoreKit integration |
| `StoreKitCreditsStore.swift` | `WhatsThatInfrastructure/Services/Credits/` | StoreKit product fetching |
| `CreditBalanceStore.swift` | `WhatsThatDomain/Credits/` | Balance caching and fetching |
| `CreditsExhaustedFullScreenView.swift` | `WhatsThatPresentation/Features/Credits/` | The exhausted modal UI |

---

## State Variables Involved

In `MainTabView.swift`:

```swift
// Credits sheet state (opened from various triggers)
@State private var showCreditsSheetFromExhausted: Bool = false
@State private var creditsExhaustedCreditsViewModel: CreditsViewModel?

// Free credits exhausted full-screen modal
@State private var showFreeCreditsExhaustedModal: Bool = false

// Flag to present credits sheet AFTER fullScreenCover dismisses
@State private var shouldPresentCreditsAfterDismiss: Bool = false

// Factory for creating CreditsViewModel (passed from RootContentView)
private let makeCreditsViewModel: (() -> CreditsViewModel)?
```

**State Modification Points**:

| Variable | Set to non-nil/true | Set to nil/false |
|----------|---------------------|------------------|
| `creditsExhaustedCreditsViewModel` | fullScreenCover.onDismiss (line 404), CreditsSheetErrorView.onRetry (line 304) | sheet.onDismiss (line 284) |
| `showCreditsSheetFromExhausted` | asyncAfter in fullScreenCover.onDismiss (line 407) | CreditsSheetErrorView.onDismiss (line 308) |
| `showFreeCreditsExhaustedModal` | onChange handlers (lines 389, 396) | onGetCredits callback (line 418), onDismiss callback (lines 421, 422) |
| `shouldPresentCreditsAfterDismiss` | onGetCredits callback (line 417) | fullScreenCover.onDismiss (line 402), onDismiss callback (line 421) |

---

## Proposed Solutions

### Solution 1: Move VM Creation Inside asyncAfter (Recommended)

Move the ViewModel creation to happen after the delay, then trigger the sheet in the next runloop:

```swift
.fullScreenCover(isPresented: $showFreeCreditsExhaustedModal, onDismiss: {
    if shouldPresentCreditsAfterDismiss {
        shouldPresentCreditsAfterDismiss = false
        // Wait for dismiss animation to fully complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let maker = makeCreditsViewModel {
                creditsExhaustedCreditsViewModel = maker()
                // Let SwiftUI process the state change before showing sheet
                DispatchQueue.main.async {
                    showCreditsSheetFromExhausted = true
                }
            }
        }
    }
})
```

**Why This Works**:
1. 200ms delay ensures fullScreenCover animation is completely done
2. VM is created in a stable state (no animations)
3. `DispatchQueue.main.async` puts the sheet presentation in the next runloop, after SwiftUI has processed the VM state change

**Pros**: Minimal code change, addresses the timing issue directly
**Cons**: Still relies on timing (though more robust)

### Solution 2: Lazy VM Creation in Sheet Content

Remove the separate state variable and create the VM on-demand:

```swift
.sheet(isPresented: $showCreditsSheetFromExhausted, onDismiss: { }) {
    if let maker = makeCreditsViewModel {
        let viewModel = maker()  // Create fresh VM when sheet content evaluates
        NavigationStack {
            CreditsView(viewModel: viewModel, ...)
        }
        .presentationDetents([.fraction(0.8), .large])
    } else {
        // Only show error if makeCreditsViewModel itself is nil
        CreditsSheetErrorView(...)
    }
}
```

**Why This Works**: The VM is created exactly when SwiftUI evaluates the sheet content, so there's no race condition.

**Pros**: Eliminates the race condition entirely, simpler state management
**Cons**: Creates a new VM every time the sheet is presented (not an issue in practice since we want fresh data anyway)

### Solution 3: Use onChange to Trigger Sheet

Instead of triggering the sheet in onDismiss, use a dedicated state variable:

```swift
@State private var readyToShowCreditsSheet: Bool = false

// In fullScreenCover's onDismiss:
.fullScreenCover(isPresented: $showFreeCreditsExhaustedModal, onDismiss: {
    if shouldPresentCreditsAfterDismiss {
        shouldPresentCreditsAfterDismiss = false
        readyToShowCreditsSheet = true
    }
})

// Separate onChange to handle the presentation:
.onChange(of: readyToShowCreditsSheet) { _, ready in
    if ready {
        readyToShowCreditsSheet = false
        if let maker = makeCreditsViewModel {
            creditsExhaustedCreditsViewModel = maker()
            showCreditsSheetFromExhausted = true
        }
    }
}
```

**Why This Works**: The onChange fires after SwiftUI has fully processed the view update from the fullScreenCover dismiss.

**Pros**: Uses SwiftUI's own lifecycle for timing
**Cons**: More complex, adds another state variable

---

## Verification Steps

To verify this issue and the fix:

1. **Reproduce the issue**:
   - Create a fresh install or reset onboarding
   - Create 3 discoveries (exhaust intro credits)
   - Attempt to create a 4th discovery
   - When credits exhausted modal appears, tap "Unlock More Stories"
   - Observe: Does the fallback error view ("Something went wrong") appear?
   - Tap "Try Again" - Does it work on retry?

2. **Add logging** to verify the timing:
   ```swift
   .fullScreenCover(isPresented: $showFreeCreditsExhaustedModal, onDismiss: {
       print("[Credits] onDismiss fired at \(Date())")
       if shouldPresentCreditsAfterDismiss {
           shouldPresentCreditsAfterDismiss = false
           if let maker = makeCreditsViewModel {
               creditsExhaustedCreditsViewModel = maker()
               print("[Credits] VM created at \(Date()), vm=\(creditsExhaustedCreditsViewModel != nil)")
               DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                   print("[Credits] asyncAfter fired at \(Date()), vm=\(creditsExhaustedCreditsViewModel != nil)")
                   showCreditsSheetFromExhausted = true
               }
           }
       }
   })

   // In sheet content:
   .sheet(isPresented: $showCreditsSheetFromExhausted, ...) {
       let _ = print("[Credits] Sheet content evaluated, vm=\(creditsExhaustedCreditsViewModel != nil)")
       if let viewModel = creditsExhaustedCreditsViewModel {
           // ...
       }
   }
   ```

3. **Test the fix**: Apply one of the proposed solutions and repeat the reproduction steps. The fallback should no longer appear on first try.

---

## Additional Context

### Why This Only Happens in Intro Mode Flow

This issue is specific to the flow:
1. Credits exhausted modal (fullScreenCover)
2. → Credits sheet

Other places where the credits sheet is opened (e.g., from Settings) don't have this issue because they don't involve dismissing a fullScreenCover first.

### CreditsViewModel Loading Behavior

Once `CreditsView` is shown with a valid ViewModel, the loading works as follows:

1. `CreditsView.task` calls `viewModel.loadIfNeeded()`
2. `CreditsViewModel.load()`:
   - Pre-populates with cached balance (if available)
   - Fetches StoreKit products via `store.loadProducts()`
   - Refreshes balance from Supabase via `balanceStore.refreshIfStale()`
3. If any step fails, an alert is shown (not the fallback error view)

The fallback error view (`CreditsSheetErrorView`) ONLY appears when `creditsExhaustedCreditsViewModel` is `nil` at the time the sheet content is evaluated - it has nothing to do with StoreKit or balance loading failures.

---

## Summary

| Aspect | Details |
|--------|---------|
| **Issue** | Credits sheet shows error fallback on first open from credits exhausted modal |
| **Root Cause** | SwiftUI state timing race during fullScreenCover dismiss |
| **Why Retry Works** | No animation interference when sheet is stable |
| **Recommended Fix** | Solution 1: Move VM creation inside asyncAfter with additional runloop delay |
| **Files to Modify** | `MainTabView.swift` (lines 399-410) |

---

## Document History

- **Created**: 2026-02-05
- **Author**: Claude Code investigation
- **Status**: Investigation complete, fix pending implementation
