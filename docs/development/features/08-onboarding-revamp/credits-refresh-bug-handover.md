# Task Handover: Credits & Intro Mode State Refresh Bug

## Issue Description

When a user is in the **Confirm Image Selection** stage of discovery creation and:
1. Sees the "Free Credits Exhausted" modal (because they have 0 credits)
2. Navigates to the Credits page via "Get Credits" button
3. Successfully purchases credits
4. Completes the Post-Purchase Configuration flow (voice selection, IPoP preferences)
5. Returns to the Confirm Image Selection stage

**The UI does not update:**
- Credits still display as **0** (should show the new purchased amount)
- Audio toggle remains **locked** (should be unlocked since user exited intro mode by purchasing)

---

## Technical Context

### Relevant Files
- `DiscoveryCreationFlowView.swift` - Parent view that presents the credits sheet
- `DiscoveryCreationFlowViewModel.swift` - View model with `creditBalance` and `isInIntroMode` @Published properties
- `CreditsView.swift` - Credits page with purchase flow
- `CreditsViewModel.swift` - Handles purchase and balance refresh
- `PostPurchaseConfigurationFlow.swift` - Post-purchase config shown after first purchase
- `FreeCreditsAlertTracker.swift` - Actor that tracks intro mode state
- `CreditBalanceStore.swift` - Actor that caches credit balance
- `DiscoveryConfirmationView.swift` - The confirm stage UI that displays credits and audio toggle

### Data Flow (Expected)

1. **During Purchase** (`CreditsViewModel.purchase()`):
   - `tracker.markPurchaseMade()` is called → sets `hasShownCreditsExhausted = true` in UserDefaults
   - `balanceStore.refresh(force: true)` fetches new balance from server
   - `updateBalance(newValue)` calls `onBalanceUpdated?(value)` callback
   - Callback triggers `flowViewModel.syncCreditBalance(newBalance)` which updates `creditBalance`

2. **After Sheet Dismisses** (`refreshStateAfterCreditsSheet()`):
   - Should refresh `creditBalance` from server/cache
   - Should re-check `isInIntroMode` from `FreeCreditsAlertTracker`

3. **UI Update**:
   - `DiscoveryConfirmationView` receives `creditBalance: viewModel.creditBalance` and `isAudioToggleLocked: viewModel.isInIntroMode`
   - SwiftUI should re-render when these @Published properties change

### Key State Properties

```swift
// DiscoveryCreationFlowViewModel
@Published private(set) var creditBalance: Int?        // Shown in UI
@Published private(set) var isInIntroMode: Bool = true // Controls audio toggle lock

// FreeCreditsAlertTracker (actor)
var isInIntroMode: Bool { !hasShownCreditsExhaustedAlert }
// markPurchaseMade() sets hasShownCreditsExhausted = true
```

---

## Attempted Fixes (All Failed)

### Attempt 1: Fix Dismiss Race Condition in CreditsView

**Hypothesis**: Calling `close()` immediately after `showPostPurchaseConfig = false` in `PostPurchaseConfigurationFlow.onComplete` caused a race condition where SwiftUI was handling two dismiss operations simultaneously, potentially skipping the sheet's `onDismiss` callback.

**Changes Made** (`CreditsView.swift`):
```swift
// Added state flag
@State private var shouldCloseAfterPostPurchaseConfig = false

// Changed fullScreenCover to use onDismiss
.fullScreenCover(isPresented: $showPostPurchaseConfig, onDismiss: {
    // Close the credits sheet AFTER fullScreenCover is fully dismissed
    if shouldCloseAfterPostPurchaseConfig {
        shouldCloseAfterPostPurchaseConfig = false
        close()
    }
}) {
    PostPurchaseConfigurationFlow(
        // ...
        onComplete: {
            Task {
                await FreeCreditsAlertTracker.shared.markPostPurchaseConfigCompleted()
            }
            // Set flag instead of calling close() directly
            shouldCloseAfterPostPurchaseConfig = true
            showPostPurchaseConfig = false
        }
    )
}
```

**Result**: Did not fix the issue.

---

### Attempt 2: Force Server Refresh in refreshStateAfterCreditsSheet()

**Hypothesis**: The cached balance was stale because the `onBalanceUpdated` callback might not have fired (e.g., if balance refresh failed during purchase).

**Changes Made** (`DiscoveryCreationFlowViewModel.swift`):
```swift
func refreshStateAfterCreditsSheet() async {
    // Changed from reading cache to forcing server refresh
    do {
        let freshBalance = try await creditBalanceStore.refresh(force: true)
        creditBalance = freshBalance
        debugLog("refreshStateAfterCreditsSheet: balance refreshed to \(freshBalance)")
    } catch {
        // Fall back to cached value if server refresh fails
        if let cached = await creditBalanceStore.getCached() {
            creditBalance = cached
            debugLog("refreshStateAfterCreditsSheet: using cached balance \(cached)")
        }
    }

    let tracker = FreeCreditsAlertTracker.shared
    isInIntroMode = await tracker.isInIntroMode
    debugLog("refreshStateAfterCreditsSheet: isInIntroMode = \(isInIntroMode)")
}
```

**Result**: Did not fix the issue.

---

### Attempt 3: Replace onDismiss with .onChange(of: activeSheet)

**Hypothesis**: The sheet's `onDismiss` callback was unreliable. Using `.onChange` to observe state changes directly would be more reliable.

**Changes Made** (`DiscoveryCreationFlowView.swift`):
```swift
// Added tracking flag
@State private var wasCreditsSheetPresented = false

// Added Equatable conformance to ActiveSheet
private enum ActiveSheet: Identifiable, Equatable {
    case credits(CreditsViewModel)
    case missingUploadLocation

    // Custom Equatable - only compare cases, not associated values
    static func == (lhs: ActiveSheet, rhs: ActiveSheet) -> Bool {
        switch (lhs, rhs) {
        case (.credits, .credits): return true
        case (.missingUploadLocation, .missingUploadLocation): return true
        default: return false
        }
    }
}

// Replaced onDismiss with onChange
.onChange(of: activeSheet) { _, newValue in
    // Track when credits sheet was presented
    if case .credits = newValue {
        wasCreditsSheetPresented = true
    }
    // When sheet closes after credits was shown, force refresh
    if newValue == nil && wasCreditsSheetPresented {
        wasCreditsSheetPresented = false
        presentedCreditsViewModel = nil
        creditsSheetDetent = .fraction(0.8)
        Task {
            await viewModel.refreshStateAfterCreditsSheet()
        }
    }
}
.sheet(item: $activeSheet) { sheet in  // Removed onDismiss callback
    // ...
}
```

**Result**: Did not fix the issue.

---

## Remaining Hypotheses to Investigate

### 1. refreshStateAfterCreditsSheet() Is Never Called
The `.onChange` or refresh logic might not be triggering at all. Need to add print/log statements to verify.

### 2. @Published Property Updates Don't Trigger Re-render
Even if `creditBalance` and `isInIntroMode` are updated, SwiftUI might not be detecting the changes. Possible causes:
- The view model might be deallocated or a different instance
- Some SwiftUI state management issue with the confirmation view

### 3. The Values Being Read Are Incorrect
- `creditBalanceStore.refresh()` might be returning the old value
- `tracker.isInIntroMode` might still return `true` despite `markPurchaseMade()` being called
- `currentUserId` in `FreeCreditsAlertTracker` might be nil, causing early returns

### 4. Different CreditBalanceStore Instances
`CreditsViewModel` and `DiscoveryCreationFlowViewModel` might be using different `CreditBalanceStore` instances. If so:
- CreditsViewModel's store gets updated during purchase
- FlowViewModel's store has stale data
- The `onBalanceUpdated` callback should sync them, but might not be working

### 5. Weak Reference Issue
In `presentCreditsSheet()`:
```swift
newViewModel.onBalanceUpdated = { newBalance in
    Task { [weak flowViewModel] in
        await flowViewModel?.syncCreditBalance(newBalance)
    }
}
```
If `flowViewModel` is deallocated, `syncCreditBalance` won't be called.

### 6. Task Execution Timing
The `Task { }` blocks used for async operations might not complete before UI needs the values, or might be getting cancelled.

---

## Debugging Recommendations

### Add Logging at Key Points

1. **In `CreditsViewModel.purchase()` after success**:
   ```swift
   print("[DEBUG] markPurchaseMade called")
   print("[DEBUG] Balance refresh result: \(newValue)")
   print("[DEBUG] Calling onBalanceUpdated with: \(newValue)")
   ```

2. **In `syncCreditBalance()`**:
   ```swift
   print("[DEBUG] syncCreditBalance called with: \(newValue)")
   ```

3. **In `.onChange(of: activeSheet)`**:
   ```swift
   print("[DEBUG] activeSheet changed to: \(String(describing: newValue))")
   print("[DEBUG] wasCreditsSheetPresented: \(wasCreditsSheetPresented)")
   ```

4. **In `refreshStateAfterCreditsSheet()`**:
   ```swift
   print("[DEBUG] refreshStateAfterCreditsSheet called")
   print("[DEBUG] creditBalance before: \(creditBalance)")
   print("[DEBUG] isInIntroMode before: \(isInIntroMode)")
   // ... after updates
   print("[DEBUG] creditBalance after: \(creditBalance)")
   print("[DEBUG] isInIntroMode after: \(isInIntroMode)")
   ```

5. **In `FreeCreditsAlertTracker.markPurchaseMade()`**:
   ```swift
   print("[DEBUG] markPurchaseMade - currentUserId: \(currentUserId ?? "nil")")
   print("[DEBUG] hasShownCreditsExhausted before: \(hasShownCreditsExhaustedAlert)")
   ```

### Verify Instance Identity

Check if the same `DiscoveryCreationFlowViewModel` instance is used throughout:
```swift
print("[DEBUG] ViewModel instance: \(ObjectIdentifier(viewModel))")
```

---

## Alternative Approaches to Consider

### 1. Direct Property Binding
Instead of passing values as parameters, use `@ObservedObject` or `@EnvironmentObject` in `DiscoveryConfirmationView` to directly observe the view model.

### 2. Notification-Based Refresh
Post a notification when purchase completes, observe it in the confirmation view to trigger refresh.

### 3. Combine Publisher
Use a Combine publisher to explicitly signal when state should refresh, rather than relying on sheet dismiss callbacks.

### 4. onAppear Refresh
Add `.onAppear` to `DiscoveryConfirmationView` that checks if a refresh is needed (e.g., via a flag set during purchase).

### 5. Force View Identity Change
Change the view's `id` after returning from credits to force SwiftUI to recreate it with fresh values.

---

## Current State of Code

The following changes are currently in the codebase (all attempted fixes):

1. **CreditsView.swift**: Has the `shouldCloseAfterPostPurchaseConfig` flag and delayed `close()` call
2. **DiscoveryCreationFlowViewModel.swift**: `refreshStateAfterCreditsSheet()` forces server refresh
3. **DiscoveryCreationFlowView.swift**: Has `wasCreditsSheetPresented` flag, `ActiveSheet` Equatable conformance, and `.onChange(of: activeSheet)` modifier

All changes compile successfully but do not resolve the issue.
