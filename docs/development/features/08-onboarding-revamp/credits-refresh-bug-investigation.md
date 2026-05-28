# Credits Refresh Bug - Deep Investigation

## Bug Summary

When a user is on the Confirm Image Selection stage with 0 credits:
1. They see the "Free Credits Exhausted" modal
2. They navigate to Credits page and purchase credits
3. They complete the Post-Purchase Configuration flow
4. They return to Confirm Image Selection stage

**Expected:** UI shows new credit balance, audio toggle is unlocked (user exited intro mode)
**Actual:** Credits still show as 0, audio toggle remains locked

---

## Code Flow Analysis

### The Complete User Journey

```
DiscoveryCreationFlowView
├── flowState = .confirming(state)
├── Shows DiscoveryConfirmationView with:
│   ├── creditBalance: viewModel.creditBalance (currently 0)
│   └── isAudioToggleLocked: viewModel.isInIntroMode (currently true)
│
├── showFreeCreditsExhaustedAtConfirm = true
│   └── .fullScreenCover → CreditsExhaustedFullScreenView
│       └── User taps "Get Credits"
│           ├── shouldPresentCreditsAfterExhaustedDismiss = true
│           └── showFreeCreditsExhaustedAtConfirm = false (dismisses)
│
├── fullScreenCover.onDismiss fires
│   └── DispatchQueue.main.asyncAfter(0.1s) { presentCreditsSheet() }
│
├── presentCreditsSheet() called
│   ├── Creates CreditsViewModel (or reuses existing)
│   ├── Sets onBalanceUpdated callback → syncCreditBalance()
│   ├── wasCreditsSheetPresented = true (via .onChange)
│   └── activeSheet = .credits(creditsViewModel)
│
├── .sheet(item: $activeSheet) → CreditsView
│   └── User purchases credits
│       ├── CreditsViewModel.purchase()
│       │   ├── tracker.markPurchaseMade() → UserDefaults updated
│       │   │   └── hasShownCreditsExhausted = true (exits intro)
│       │   ├── balanceStore.refresh(force: true) → gets new balance
│       │   └── updateBalance(newValue)
│       │       └── onBalanceUpdated?(value) → syncCreditBalance()
│       │           └── Only updates creditBalance, NOT isInIntroMode!
│       │
│       └── shouldShowPostPurchaseConfig = true
│           └── .fullScreenCover → PostPurchaseConfigurationFlow
│               └── User completes configuration
│                   ├── markPostPurchaseConfigCompleted()
│                   ├── shouldCloseAfterPostPurchaseConfig = true
│                   └── showPostPurchaseConfig = false (dismisses)
│
├── PostPurchaseConfigurationFlow.fullScreenCover.onDismiss fires
│   └── close() called → dismiss() → Should set activeSheet = nil
│
└── .onChange(of: activeSheet) SHOULD fire with newValue = nil
    └── IF wasCreditsSheetPresented == true:
        └── Task { await viewModel.refreshStateAfterCreditsSheet() }
            ├── creditBalance = freshBalance (from server)
            └── isInIntroMode = await tracker.isInIntroMode (should be false now)
```

---

## Key Files and Their Responsibilities

| File | Responsibility |
|------|----------------|
| `DiscoveryCreationFlowView.swift` | Parent view, manages sheet presentations, `.onChange(of: activeSheet)` |
| `DiscoveryCreationFlowViewModel.swift` | Holds `creditBalance` and `isInIntroMode` @Published properties |
| `CreditsView.swift` | Credits page UI, manages PostPurchaseConfigurationFlow fullScreenCover |
| `CreditsViewModel.swift` | Handles purchase, calls `onBalanceUpdated` callback |
| `DiscoveryConfirmationView.swift` | Displays credit balance and audio toggle |
| `FreeCreditsAlertTracker.swift` | Actor tracking intro mode state in UserDefaults |

---

## State Updates: When and Where

### 1. During Purchase (`CreditsViewModel.purchase()`)

```swift
// In CreditsViewModel.swift:162-187
case .success:
    let tracker = FreeCreditsAlertTracker.shared
    await tracker.markPurchaseMade()  // ← Updates UserDefaults

    let newValue = try await balanceStore.refresh(force: true)
    updateBalance(newValue)  // ← Calls onBalanceUpdated callback
```

### 2. The `onBalanceUpdated` Callback

```swift
// In DiscoveryCreationFlowView.swift:373-377
newViewModel.onBalanceUpdated = { newBalance in
    Task { [weak flowViewModel] in
        await flowViewModel?.syncCreditBalance(newBalance)
    }
}
```

### 3. `syncCreditBalance()` - ONLY UPDATES BALANCE

```swift
// In DiscoveryCreationFlowViewModel.swift:510-513
func syncCreditBalance(_ newValue: Int?) async {
    let normalized = await creditBalanceStore.set(newValue)
    creditBalance = normalized
    // NOTE: isInIntroMode is NOT updated here!
}
```

### 4. `refreshStateAfterCreditsSheet()` - UPDATES BOTH

```swift
// In DiscoveryCreationFlowViewModel.swift:517-536
func refreshStateAfterCreditsSheet() async {
    // Update credit balance
    let freshBalance = try await creditBalanceStore.refresh(force: true)
    creditBalance = freshBalance

    // Update intro mode status
    let tracker = FreeCreditsAlertTracker.shared
    isInIntroMode = await tracker.isInIntroMode  // ← This is the critical update
}
```

---

## The Core Problem

**`isInIntroMode` is only updated in `refreshStateAfterCreditsSheet()`, which depends on the `.onChange(of: activeSheet)` firing when the credits sheet dismisses.**

If this doesn't happen, `isInIntroMode` remains `true` even though:
- `tracker.markPurchaseMade()` was called during purchase
- `tracker.isInIntroMode` now returns `false`
- The user has actually exited intro mode

---

## Potential Failure Points

### 1. `.onChange(of: activeSheet)` Not Firing

**Location:** `DiscoveryCreationFlowView.swift:172-186`

```swift
.onChange(of: activeSheet) { _, newValue in
    if case .credits = newValue {
        wasCreditsSheetPresented = true
    }
    if newValue == nil && wasCreditsSheetPresented {
        // ... refreshStateAfterCreditsSheet() called here
    }
}
```

**Potential issues:**
- `activeSheet` might not be set to `nil` when `dismiss()` is called from nested presentation
- SwiftUI race condition with nested dismiss (fullScreenCover → sheet)
- The Equatable conformance on `ActiveSheet` might cause issues

### 2. `wasCreditsSheetPresented` is `false`

If the `.onChange` didn't fire when `activeSheet` became `.credits(...)`, then `wasCreditsSheetPresented` would still be `false`, and the refresh wouldn't be triggered.

### 3. The Task Never Completes

```swift
Task {
    await viewModel.refreshStateAfterCreditsSheet()
}
```

This unstructured Task could theoretically be cancelled or fail silently, though this is unlikely.

### 4. SwiftUI View Not Re-rendering

Even if `creditBalance` and `isInIntroMode` are updated, SwiftUI might not re-render `DiscoveryConfirmationView` if there's a structural issue with how the view tree is set up.

---

## The Nested Presentation Challenge

The dismiss flow involves multiple layers:

```
DiscoveryCreationFlowView
└── .sheet (CreditsView) ← activeSheet binding
    └── .fullScreenCover (PostPurchaseConfigurationFlow)
```

When `PostPurchaseConfigurationFlow.onComplete` is called:
1. `showPostPurchaseConfig = false` → Dismisses fullScreenCover
2. In `fullScreenCover.onDismiss`: `close()` is called
3. `close()` calls `dismiss()` on CreditsView
4. This should set `activeSheet = nil` on parent

**The potential race condition:** SwiftUI might not properly propagate the `nil` to the `activeSheet` binding when dismissing from within a nested presentation context.

---

## DiscoveryConfirmationView Parameter Passing

```swift
// DiscoveryCreationFlowView.swift:311-323
case let .confirming(state):
    DiscoveryConfirmationView(
        state: state,
        creditBalance: viewModel.creditBalance,  // ← Value, not binding
        flowType: viewModel.flowType,
        ...
        isAudioToggleLocked: viewModel.isInIntroMode  // ← Value, not binding
    )
```

These are **value parameters**, not bindings or observed objects. For the UI to update:
1. `viewModel.creditBalance` or `viewModel.isInIntroMode` must change
2. This triggers re-render of `DiscoveryCreationFlowView` (due to `@ObservedObject`)
3. `DiscoveryConfirmationView` is recreated with new parameter values

If step 1 doesn't happen (because `refreshStateAfterCreditsSheet()` isn't called), step 2 and 3 never occur.

---

## Alternative Flow: Direct Navigation to Credits

The bug also occurs when the user navigates directly from the confirmation screen to credits (via the credits badge), not through the exhausted modal. This path also uses `presentCreditsSheet()` and should have the same `.onChange` behavior.

---

## What Previous Attempts Fixed (and Why They Didn't Work)

### Attempt 1: Fix Dismiss Race Condition
Added `shouldCloseAfterPostPurchaseConfig` flag to delay `close()` until fullScreenCover's `onDismiss`.

**Why it didn't work:** The dismiss timing was correct, but the underlying issue isn't about when `close()` is called - it's about whether `activeSheet = nil` triggers the `.onChange`.

### Attempt 2: Force Server Refresh
Changed `refreshStateAfterCreditsSheet()` to force server refresh instead of using cache.

**Why it didn't work:** The function itself works correctly - the issue is that it's never being called.

### Attempt 3: Replace onDismiss with .onChange
Switched from relying on sheet's `onDismiss` to using `.onChange(of: activeSheet)`.

**Why it didn't work:** If `activeSheet` isn't changing to `nil` (or the change isn't detected), `.onChange` won't fire regardless of the approach.

---

## Hypotheses to Test

### Hypothesis A: `.onChange` Never Fires
The `activeSheet` binding isn't being set to `nil` when `dismiss()` is called, or SwiftUI isn't detecting the change.

**Test:** Add print statement at the start of `.onChange` to log every change.

### Hypothesis B: `wasCreditsSheetPresented` is False
The flag wasn't set to `true` when the credits sheet opened.

**Test:** Add print statement when setting `wasCreditsSheetPresented = true`.

### Hypothesis C: `refreshStateAfterCreditsSheet()` Fails Silently
The async function throws or returns early without updating properties.

**Test:** Add print statements at start and end of function.

### Hypothesis D: Properties Update But View Doesn't Re-render
The @Published properties are updated but SwiftUI doesn't trigger a re-render.

**Test:** Add `.onChange(of: viewModel.isInIntroMode)` to DiscoveryCreationFlowView to verify property changes.

---

## Recommended Debug Logging

Add these logs to trace the complete flow:

### In `CreditsView.close()`
```swift
private func close() {
    print("[DEBUG] CreditsView.close() called")
    if let onClose {
        onClose()
    } else {
        dismiss()
    }
}
```

### In `.onChange(of: activeSheet)`
```swift
.onChange(of: activeSheet) { oldValue, newValue in
    print("[DEBUG] activeSheet changed: \(String(describing: oldValue)) → \(String(describing: newValue))")
    print("[DEBUG] wasCreditsSheetPresented: \(wasCreditsSheetPresented)")

    if case .credits = newValue {
        wasCreditsSheetPresented = true
        print("[DEBUG] Set wasCreditsSheetPresented = true")
    }
    if newValue == nil && wasCreditsSheetPresented {
        print("[DEBUG] Credits sheet dismissed, calling refreshStateAfterCreditsSheet()")
        wasCreditsSheetPresented = false
        presentedCreditsViewModel = nil
        creditsSheetDetent = .fraction(0.8)
        Task {
            await viewModel.refreshStateAfterCreditsSheet()
        }
    }
}
```

### In `refreshStateAfterCreditsSheet()`
```swift
func refreshStateAfterCreditsSheet() async {
    print("[DEBUG] refreshStateAfterCreditsSheet() START")
    print("[DEBUG] Before - creditBalance: \(String(describing: creditBalance)), isInIntroMode: \(isInIntroMode)")

    // ... existing code ...

    print("[DEBUG] After - creditBalance: \(String(describing: creditBalance)), isInIntroMode: \(isInIntroMode)")
    print("[DEBUG] refreshStateAfterCreditsSheet() END")
}
```

### In `syncCreditBalance()`
```swift
func syncCreditBalance(_ newValue: Int?) async {
    print("[DEBUG] syncCreditBalance() called with: \(String(describing: newValue))")
    let normalized = await creditBalanceStore.set(newValue)
    creditBalance = normalized
    print("[DEBUG] syncCreditBalance() set creditBalance to: \(String(describing: creditBalance))")
}
```

---

## Potential Solutions to Explore

### Solution 1: Update `isInIntroMode` in `syncCreditBalance()`
```swift
func syncCreditBalance(_ newValue: Int?) async {
    let normalized = await creditBalanceStore.set(newValue)
    creditBalance = normalized

    // Also update intro mode since purchase may have exited intro
    let tracker = FreeCreditsAlertTracker.shared
    isInIntroMode = await tracker.isInIntroMode
}
```

**Pros:** Updates intro mode immediately during purchase flow
**Cons:** Doesn't fix the root cause if `.onChange` is broken

### Solution 2: Use `.onDisappear` on CreditsView
```swift
CreditsView(...)
    .onDisappear {
        Task {
            await viewModel.refreshStateAfterCreditsSheet()
        }
    }
```

**Pros:** More reliable than relying on binding changes
**Cons:** `onDisappear` might fire at wrong times

### Solution 3: Notification-Based Refresh
Post a notification when purchase completes, observe it in DiscoveryCreationFlowView.

```swift
// In CreditsViewModel after successful purchase
NotificationCenter.default.post(name: .creditsPurchased, object: nil)

// In DiscoveryCreationFlowView
.onReceive(NotificationCenter.default.publisher(for: .creditsPurchased)) { _ in
    Task {
        await viewModel.refreshStateAfterCreditsSheet()
    }
}
```

**Pros:** Decoupled, reliable
**Cons:** Adds complexity, notification might fire before sheet dismisses

### Solution 4: Force View Identity Change
Add a unique ID to `DiscoveryConfirmationView` that changes after credits sheet dismisses.

```swift
@State private var confirmationViewId = UUID()

// After credits sheet dismisses
confirmationViewId = UUID()

// In body
DiscoveryConfirmationView(...)
    .id(confirmationViewId)
```

**Pros:** Forces SwiftUI to recreate view with fresh values
**Cons:** Might cause unwanted UI glitches

### Solution 5: Use Combine Publisher
Create a dedicated publisher for credits/intro state changes.

**Pros:** Explicit, testable state flow
**Cons:** Significant refactor

---

## Next Steps

1. **Add debug logging** to identify exactly where the flow breaks
2. **Run the app** and reproduce the bug while watching console output
3. **Identify the failure point** based on which logs appear/don't appear
4. **Implement the appropriate fix** based on findings

---

## Related Files

- `DiscoveryCreationFlowView.swift` - Lines 172-186 (onChange), 248-275 (fullScreenCover), 364-384 (presentCreditsSheet)
- `DiscoveryCreationFlowViewModel.swift` - Lines 73, 87 (properties), 507-536 (sync/refresh methods)
- `CreditsView.swift` - Lines 107-145 (fullScreenCover), 187-193 (close)
- `CreditsViewModel.swift` - Lines 131-224 (purchase)
- `FreeCreditsAlertTracker.swift` - Lines 53-55 (isInIntroMode), 128-139 (markPurchaseMade)
