# Audio Generating Modal Bug - Investigation Handover

## Problem Statement

The "Audio Generating Modal" (shown after first discovery completes, saying "We are voicing your discovery...") never appears for fresh users in intro mode.

## Observed Symptoms

### In Intro Mode (Fresh User)
1. User signs up
2. User goes through **Gallery/Upload flow** to create first discovery
3. When user **confirms** the image, they **stay on the Gallery tab**
4. Discovery completes successfully
5. **Modal never appears**

### After Exiting Intro Mode (e.g., after purchasing credits)
1. User goes through Gallery/Upload flow
2. When user **confirms** the image, they are **switched to Discoveries tab**
3. The overlay appears on top of Discoveries tab
4. Modal appears **immediately on confirm** (before discovery even completes!)

### Key Observation About Camera vs Gallery
- **Camera flow**: Works correctly - switches to Discoveries tab on confirm
- **Gallery flow in intro mode**: Broken - stays on Gallery tab on confirm
- **Gallery flow after intro mode**: Works correctly - switches to Discoveries tab

## The Critical Discrepancy

**The Camera tab and Gallery tab behave differently during intro mode.**

When the user confirms:
- Camera flow → switches to Discoveries tab → overlay appears → modal can show
- Gallery flow (intro mode) → stays on Gallery tab → no overlay → modal cannot show

The overlay is presented on the Discoveries tab with `isOverlay: true`. The embedded tab views have `isOverlay: false`. The modal is gated by:

```swift
// DiscoveryCreationFlowView.swift:196
.sheet(
    isPresented: Binding(
        get: { isOverlay && viewModel.showAudioGeneratingModal },
        ...
    )
)
```

So if the overlay never appears, `isOverlay` is always `false`, and the modal can never be presented.

## Why the Modal Showed Immediately After Purchasing

1. First discovery (intro mode, Gallery flow):
   - `showAudioGeneratingModal = true` was set when discovery completed
   - But overlay wasn't visible, so modal didn't show
   - Flag was **never reset** (only resets when modal is dismissed)
   - `markAudioGeneratingModalShown()` was called, marking it as "seen"

2. Second discovery (after purchasing, Gallery flow):
   - Now the tab switch works correctly
   - Overlay appears with `isOverlay: true`
   - `showAudioGeneratingModal` is **still true** from before!
   - Modal shows **immediately** on confirm

## Technical Flow

### How Tab Switch Should Work

1. User presses confirm button
2. `beginAnalysis()` is called (DiscoveryCreationFlowViewModel.swift:450)
3. `onAnalysisBegan?(configuration.type)` is called (line 466)
4. `handleAnalysisBegan` runs in MainTabView (line 550):
   ```swift
   private func handleAnalysisBegan(_ type: DiscoveryCreationFlowType) {
       switch type {
       case .camera:
           activeOverlayTab = .camera
       case .upload:
           activeOverlayTab = .upload
       }
       selectedTab = .discoveries  // THIS IS THE TAB SWITCH
   }
   ```
5. Overlay appears because `activeOverlayTab` is set

### Where It Might Be Breaking

The tab switch happens in `handleAnalysisBegan`. For this to not happen, either:
1. `onAnalysisBegan` callback is nil, OR
2. `beginAnalysis()` returns early before reaching `onAnalysisBegan?(...)`, OR
3. Something else is different between camera and gallery flows

### Callbacks Are Set in MainTabView.onAppear

```swift
// MainTabView.swift:315-321
.onAppear {
    cameraViewModel.onDiscoveryCreated = handleDiscoveryCreated
    uploadViewModel.onDiscoveryCreated = handleDiscoveryCreated
    ...
    cameraViewModel.onAnalysisBegan = handleAnalysisBegan
    uploadViewModel.onAnalysisBegan = handleAnalysisBegan
    ...
    handleTabChange(to: selectedTab, isInitial: true)
}
```

---

## Deep Investigation (Feb 2026)

### Debugging Step 1: Compare Camera vs Upload Flow Logs

We compared full console logs between a working camera flow and broken upload flow.

**Camera Flow (Working):**
```
[MainTabView] handleAnalysisBegan called with type: camera
[MainTabView] BEFORE: selectedTab=camera, activeOverlayTab=nil
[MainTabView] AFTER: selectedTab=discoveries, activeOverlayTab=Optional(...Tab.camera)
[DiscoveryCreationFlowViewModel] onAnalysisBegan callback completed
[MainTabView] onChange(selectedTab): camera -> discoveries  ← TAB CHANGE DETECTED
[MainTabView] handleTabChange called: tab=discoveries, isInitial=false, activeOverlayTab=Optional(...Tab.camera)
...
[MainTabView] updateOverlayVisibility: tab=camera, phase=analyzing, activeOverlayTab=Optional(...Tab.camera) ← CORRECT
```

**Upload Flow (Broken):**
```
[MainTabView] handleAnalysisBegan called with type: upload
[MainTabView] BEFORE: selectedTab=upload, activeOverlayTab=nil
[MainTabView] AFTER: selectedTab=discoveries, activeOverlayTab=Optional(...Tab.upload)
[DiscoveryCreationFlowViewModel] onAnalysisBegan callback completed
[ANALYSIS_LOC] source=confirmation...
[DiscoveryStreamingStageView] Stream started
[MainTabView] updateOverlayVisibility: tab=upload, phase=analyzing, activeOverlayTab=nil ← WRONG! Should be .upload
```

**Key Finding:** In the upload flow:
1. `onChange(selectedTab)` **never fires** (no log appears)
2. `activeOverlayTab` is `nil` when `updateOverlayVisibility` runs, even though `handleAnalysisBegan` set it to `.upload`

### Debugging Step 2: Add onChange for activeOverlayTab

Added logging to track `activeOverlayTab` changes:

```swift
.onChange(of: activeOverlayTab) { oldValue, newValue in
    print("[MainTabView] onChange(activeOverlayTab): \(String(describing: oldValue)) -> \(String(describing: newValue))")
}
```

**Result:** The `onChange(activeOverlayTab)` handler **NEVER fired** in the upload flow, even though `handleAnalysisBegan` clearly set it (confirmed by AFTER log).

### Debugging Step 3: Add Body Evaluation Logging

Added logging at the start of MainTabView's body:

```swift
var body: some View {
    let _ = print("[MainTabView] body evaluated: selectedTab=\(selectedTab), activeOverlayTab=\(String(describing: activeOverlayTab))")
    ...
}
```

**Critical Discovery - The Smoking Gun:**

```
[MainTabView] body evaluated: selectedTab=upload, activeOverlayTab=nil  ← Body sees upload
[MainTabView] body evaluated: selectedTab=upload, activeOverlayTab=nil
[DiscoveryCreationFlowViewModel] About to call onAnalysisBegan with type: upload
[MainTabView] handleAnalysisBegan called with type: upload
[MainTabView] BEFORE: selectedTab=discoveries, activeOverlayTab=nil  ← Callback sees discoveries!
[MainTabView] AFTER: selectedTab=discoveries, activeOverlayTab=Optional(...Tab.upload)
[MainTabView] body evaluated: selectedTab=upload, activeOverlayTab=nil  ← Body STILL sees upload!
```

**The body sees `selectedTab=upload` but `handleAnalysisBegan` sees `selectedTab=discoveries`!**

These are **different values at the same moment in time**. This can only happen if there are **two different MainTabView instances**.

### Root Cause Identified: Stale Callback Instance

The `handleAnalysisBegan` callback is attached to an **old/stale MainTabView instance** while SwiftUI is rendering a **new instance**.

**What's happening:**
1. MainTabView is created, `onAppear` runs, callbacks are set pointing to THIS instance's methods
2. Something causes SwiftUI to recreate MainTabView (new identity)
3. NEW instance has fresh @State (`selectedTab` initialized to `initialTab` which is `.discoveries`)
4. But the viewModels still have callbacks pointing to the OLD instance
5. When user confirms, OLD instance's `handleAnalysisBegan` runs, modifying OLD instance's state
6. NEW instance's body renders, showing its own state (unchanged)
7. `onChange` handlers on NEW instance never fire because the state change happened on OLD instance

### Attempted Fix 1: Move ViewModels to RootContentView (DID NOT WORK)

**Hypothesis:** The viewModels were being created inline in RootContentView's body:
```swift
MainTabView(
    cameraViewModel: makeCreationViewModel(.camera),  // NEW every body evaluation
    uploadViewModel: makeCreationViewModel(.upload),  // NEW every body evaluation
    ...
)
```

**Fix attempted:**
1. Added `@StateObject` for viewModels at RootContentView level
2. Changed MainTabView to use `@ObservedObject` instead of `@StateObject`
3. Pass stable viewModel instances to MainTabView

**Result:** Bug still occurs. The fix did not resolve the issue.

---

## Current State of Debug Logging

The following debug logging is currently in place in `MainTabView.swift`:

```swift
// Body evaluation logging
var body: some View {
    let _ = print("[MainTabView] body evaluated: selectedTab=\(selectedTab), activeOverlayTab=\(String(describing: activeOverlayTab))")
    ...
}

// Tab change logging
.onChange(of: selectedTab) { oldValue, newValue in
    print("[MainTabView] onChange(selectedTab): \(oldValue) -> \(newValue)")
    ...
}

// Active overlay tab change logging
.onChange(of: activeOverlayTab) { oldValue, newValue in
    print("[MainTabView] onChange(activeOverlayTab): \(String(describing: oldValue)) -> \(String(describing: newValue))")
}

// handleAnalysisBegan logging
private func handleAnalysisBegan(_ type: DiscoveryCreationFlowType) {
    print("[MainTabView] handleAnalysisBegan called with type: \(type)")
    print("[MainTabView] BEFORE: selectedTab=\(selectedTab), activeOverlayTab=\(String(describing: activeOverlayTab))")
    ...
    print("[MainTabView] AFTER: selectedTab=\(selectedTab), activeOverlayTab=\(String(describing: activeOverlayTab))")
}
```

---

## Additional Debugging Steps to Try

### 1. Track View Instance Identity

Add a unique identifier to MainTabView to track if/when it's recreated:

```swift
struct MainTabView: View {
    private let instanceId = UUID()

    var body: some View {
        let _ = print("[MainTabView] body evaluated: instanceId=\(instanceId), selectedTab=\(selectedTab), activeOverlayTab=\(String(describing: activeOverlayTab))")
        ...
    }

    // Also log in onAppear
    .onAppear {
        print("[MainTabView] onAppear: instanceId=\(instanceId)")
        ...
    }
}
```

This will definitively show if multiple instances exist and which one the callbacks are attached to.

### 2. Log Callback Setup with Instance ID

```swift
.onAppear {
    print("[MainTabView] onAppear setting callbacks, instanceId=\(instanceId)")
    uploadViewModel.onAnalysisBegan = { [instanceId] type in
        print("[MainTabView] onAnalysisBegan called, callback instanceId=\(instanceId)")
        self.handleAnalysisBegan(type)
    }
    ...
}
```

### 3. Try Using a Combine Publisher Instead of Closures

Instead of storing closures that capture `self`, use a Combine publisher:

```swift
// In DiscoveryCreationFlowViewModel
let analysisBeganPublisher = PassthroughSubject<DiscoveryCreationFlowType, Never>()

// In beginAnalysis()
analysisBeganPublisher.send(configuration.type)

// In MainTabView
.onReceive(uploadViewModel.analysisBeganPublisher) { type in
    handleAnalysisBegan(type)
}
```

This avoids closure capture issues entirely.

### 4. Check RootContentView's mainContent Identity

The `mainContent` computed property uses a switch statement. Check if view identity is changing:

```swift
case .main:
    MainTabView(...)
        .id("mainTabView")  // Force stable identity
```

### 5. Remove the onAppear that Sets mainTabDestination

In RootContentView, there's:
```swift
.onAppear {
    mainTabDestination = .discoveries
}
```

This changes @State in RootContentView when MainTabView appears, triggering a re-render. Try removing this or deferring it.

### 6. Reverse the Order of State Changes in handleAnalysisBegan

```swift
private func handleAnalysisBegan(_ type: DiscoveryCreationFlowType) {
    // Try setting selectedTab FIRST, then activeOverlayTab
    selectedTab = .discoveries
    switch type {
    case .camera:
        activeOverlayTab = .camera
    case .upload:
        activeOverlayTab = .upload
    }
}
```

### 7. Remove DispatchQueue.main.async from onChange Handlers

The onChange handlers use `DispatchQueue.main.async`. Try removing this:

```swift
.onChange(of: selectedTab) { oldValue, newValue in
    print("[MainTabView] onChange(selectedTab): \(oldValue) -> \(newValue)")
    handleTabChange(to: newValue)  // Remove async
}
```

---

## Key Files to Investigate

1. **MainTabView.swift** - Tab switching logic, overlay visibility, callback setup
2. **DiscoveryCreationFlowViewModel.swift** - `beginAnalysis()`, `onAnalysisBegan` callback
3. **DiscoveryCreationFlowView.swift** - Modal presentation logic (line 192-227)
4. **RootContentView.swift** - How MainTabView is created, initial tab selection

## What Was Ruled Out

- ViewModels being recreated (not the root cause - camera works fine)
- Async timing of `showAudioGeneratingModal` (user stayed on page, would have seen it)
- FreeCreditsAlertTracker binding issues (would affect both flows equally)
- Moving viewModels to RootContentView as @StateObject (attempted, did not fix)

## What We Know For Certain

1. **Two different view instances exist** - body and handleAnalysisBegan see different state values
2. **Callbacks are attached to the wrong instance** - the callback modifies state on an old instance
3. **SwiftUI onChange handlers don't fire** - because the state change happens on a different instance
4. **Camera flow works, upload flow doesn't** - something specific to the upload/gallery tab or PHPickerViewController
5. **The issue is NOT intro-mode specific** - it's specific to the upload tab in certain conditions

## Related Code Locations

- Modal presentation: `DiscoveryCreationFlowView.swift:192-227`
- `showAudioGeneratingModal` set: `DiscoveryCreationFlowViewModel.swift:1370-1373`
- Tab switch: `MainTabView.swift:550-558` (`handleAnalysisBegan`)
- Overlay visibility: `MainTabView.swift:199-240`
- Callback setup: `MainTabView.swift:315-321`
- ViewModels created: `RootContentView.swift` (now as @StateObject)
- MainTabView creation: `RootContentView.swift:520-548`
