# iPad Support

This document outlines the work required to properly support iPad for the What's That app.

## Status Summary

| Phase | Status |
|-------|--------|
| Build Configuration | ✅ Complete |
| App Icons | ✅ Complete |
| Info.plist | ✅ Complete |
| Design Decisions | ✅ Complete |
| UI Adaptation | ⬜ Not Started — See [ipad-ui-requirements.md](./ipad-ui-requirements.md) |
| Testing | ⬜ Not Started |

---

## Critical Requirements

### Requirement 1: Device Detection — Zero iPhone Impact

**All iPad UI adaptations MUST have zero effect on iPhone.** This is a non-negotiable requirement.

#### Detection Pattern

Use `UIDevice.current.userInterfaceIdiom` for explicit device checks:

```swift
import UIKit

extension UIDevice {
    static var isIPad: Bool {
        current.userInterfaceIdiom == .pad
    }
}
```

Usage in SwiftUI:
```swift
if UIDevice.isIPad {
    // iPad-specific layout
} else {
    // iPhone layout (unchanged)
}
```

#### Why This Is Safe

| Factor | Guarantee |
|--------|-----------|
| Portrait-only | No orientation ambiguity |
| Full-screen only | No Split View size class changes |
| `userInterfaceIdiom` | Hardware-based, never changes at runtime |
| Conditional branching | iPhone code path completely isolated |

#### Alternative: Size Class (Also Safe)

```swift
@Environment(\.horizontalSizeClass) private var horizontalSizeClass

// horizontalSizeClass == .regular → iPad
// horizontalSizeClass == .compact → iPhone
```

Both methods are reliable given our portrait-only, full-screen configuration. Choose based on context:
- Use `UIDevice.isIPad` for device-specific logic (e.g., different detent heights)
- Use `horizontalSizeClass` for layout-dependent logic (e.g., column counts)

> [!IMPORTANT]
> Any PR modifying UI for iPad support MUST be tested on both iPhone and iPad simulators to verify zero regression on iPhone.

---

## Design Decisions (Finalized)

The following decisions establish our **minimal-change approach** to iPad support. The goal is to have the iPad version work acceptably without maintaining separate code paths.

### Decision 1: Sheet Presentation — Accept iPad Default ✅

**Decision:** Accept iPad's default centered popover/sheet presentation.

- iPad presents sheets as centered modal popovers by default
- We will NOT force iPhone-style bottom sheets
- Reason: Looks acceptable, reduces complexity

**No code changes required.**

---

### Decision 2: Layout/Grid Columns — Keep Current Behavior ✅

**Decision:** Keep `UIScreen.main.bounds` calculations as-is. No column count adjustments.

- Discovery grid will display with 2 columns (cards will be larger on iPad)
- Discovery detail overlay will be larger but looks nice
- We are NOT adding column count logic based on device type

**No code changes required.**

---

### Decision 3: Content Width Constraints — None ✅

**Decision:** No max-width constraints on content.

- Content will expand to fill available width on iPad
- This is acceptable for our use case

**No code changes required.**

---

### Decision 4: Navigation Paradigm — Keep NavigationStack ✅

**Decision:** Keep `NavigationStack` everywhere. Do NOT use `NavigationSplitView`.

- Consistent with iPhone experience
- Minimal change set
- No sidebar navigation on iPad

**No code changes required.**

---

### Decision 5: Popover Behavior — Accept Current Implementation ✅

**Decision:** Existing popover implementations are acceptable.

- `AudioToggleView.swift` popover: Works correctly
- `DiscoveryDetailShareHelpers.swift`: Already handles iPad source rect

**Testing only — no code changes.**

---

### Decision 6: Safe Area Handling — Monitor During Testing ✅

**Decision:** Current `GeometryReader`-based safe area handling should work.

- iPad has different safe areas (smaller top inset, etc.)
- One hardcoded fallback (`59pt` for iPhone notch) may need monitoring
- Address issues if they arise during testing

**No proactive changes — test and fix if needed.**

---

### Decision 7: Hardware Keyboard — Automatic ✅

**Decision:** SwiftUI handles hardware keyboard support automatically.

- `@FocusState` works correctly with external keyboards
- On-screen keyboard may not appear when hardware keyboard connected (expected behavior)

**No code changes required.**

---

### Decision 8: Pointer/Hover Support — Automatic ✅

**Decision:** SwiftUI provides automatic hover states.

- All existing buttons will work with mouse/trackpad
- No additional work needed

**No code changes required.**

---

### Decision 9: Camera Position — No Changes ✅

**Decision:** AVFoundation handles iPad camera positioning.

- iPad cameras are positioned differently in portrait
- Camera preview and capture will work without changes

**Testing only — no code changes.**

---

### Summary: Minimal Change Approach

| Area | Decision | Action |
|------|----------|--------|
| Sheets | Accept iPad default | None |
| Grid columns | Keep 2-column | None |
| Content width | No constraints | None |
| Navigation | Keep NavigationStack | None |
| Popovers | Accept current | Test only |
| Safe areas | Monitor | Fix if needed |
| Hardware keyboard | Automatic | None |
| Pointer support | Automatic | None |
| Camera | Automatic | Test only |

**Result:** The primary work is **testing**, not UI redesign. The existing UI scales to iPad in an acceptable way.

---

## Phase 1: Build Configuration ✅

**Status: Complete**

Changed `TARGETED_DEVICE_FAMILY` from `1` (iPhone only) to `"1,2"` (iPhone + iPad) in the following locations within `project.pbxproj`:

| Target | Configuration | Line |
|--------|---------------|------|
| WhatsThatIOS | Debug | ~420 |
| WhatsThatIOS | Release | ~453 |
| WhatsThatIOSUITests | Debug | ~466 |
| WhatsThatIOSUITests | Release | ~480 |

**Files Modified:**
- `native/WhatsThatIOS.xcodeproj/project.pbxproj`

---

## Phase 2: App Icons ✅

**Status: Complete**

Added the required iPad app icons by resizing the existing 1024x1024 marketing icon.

### Icons Generated

| Size | Filename | Purpose |
|------|----------|---------|
| 152x152 | `AppIcon-76@2x.png` | iPad @2x (76pt) |
| 167x167 | `AppIcon-83.5@2x.png` | iPad Pro @2x (83.5pt) |

### Icon Catalog Updates

Updated `Contents.json` to include iPad entries for:
- 20x20 @1x, @2x
- 29x29 @1x, @2x
- 40x40 @1x, @2x
- 76x76 @2x (152px)
- 83.5x83.5 @2x (167px)

**Files Modified:**
- `native/WhatsThatIOS/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Added: `AppIcon-76@2x.png`, `AppIcon-83.5@2x.png`

---

## Phase 3: Info.plist ✅

**Status: Complete**

Configured iPad to run in portrait-only mode, matching iPhone behavior.

### Approach: Portrait-Only (No Multitasking)

Apple requires all 4 orientations for iPad apps that support multitasking (Split View, Slide Over). Since our UI is designed for portrait mode and we want consistency with iPhone, we opted out of multitasking instead.

### Changes Made

Added `UIRequiresFullScreen = true` to Info.plist:

```xml
<key>UIRequiresFullScreen</key>
<true/>
```

**Effect:**
- App runs full-screen only on iPad (no Split View or Slide Over)
- Allows portrait-only orientation without requiring landscape support
- Matches iPhone behavior and our current UI design

> **Note:** If we later decide to support multitasking, we would need to:
> 1. Remove `UIRequiresFullScreen` or set it to `false`
> 2. Add all 4 orientations to `UISupportedInterfaceOrientations~ipad`
> 3. Implement landscape layout adaptations

**Files Modified:**
- `native/Config/AppInfo.plist`

---

## Phase 4: UI Adaptation ⬜

**Status: Not Started**

> [!NOTE]
> Detailed screen-by-screen UI requirements are documented in **[ipad-ui-requirements.md](./ipad-ui-requirements.md)**.

### Summary of Required Work

The UI work follows our **minimal-change approach** — no layout restructuring, only targeted adjustments:

| Category | Screens | Effort |
|----------|---------|--------|
| **Text Scaling** | All screens | Low per screen |
| **Mini Player Redesign** | My Discoveries | Medium |
| **Onboarding Layout** | Onboarding pages | Medium |
| **Auth Centering** | Login, Sign Up, Forgot Password | Low |

### Priority Order

**P1 (High):**
1. Mini Player — Limit width, redesign for iPad
2. Onboarding — Constrain images, ensure text visibility
3. Discovery Detail View — Force full screen, scale text and buttons
4. Audio Guides — Scale player and all text

**P2 (Medium):**
3. Discovery Detail View — Force full screen, scale text and buttons
2. Gallery Titles — Increase font size
3. Authentication — Center content, scale text
4. Streaming Result View — Match Discovery Detail scaling

**P3 (Lower):**
1. Creation/Camera Flow — Scale labels
2. Settings Sheet — Increase height and text

---

## Phase 5: Multitasking Support ❌

**Status: Not Applicable**

We have opted out of iPad multitasking by setting `UIRequiresFullScreen = true`. This means:

- ❌ No Split View support
- ❌ No Slide Over support  
- ✅ App always runs full-screen
- ✅ Portrait-only orientation maintained

This decision simplifies development and ensures UI consistency with iPhone. If multitasking support is desired in the future, it would require:

1. Removing `UIRequiresFullScreen` from Info.plist
2. Adding all 4 orientations to `UISupportedInterfaceOrientations~ipad`
3. Implementing responsive layouts that handle size class changes
4. Testing all multitasking scenarios

---

## Phase 6: Testing Checklist

### Device Matrix

Test on the following devices to cover the range of iPad screen sizes:

| Device | Size | Purpose |
|--------|------|--------|
| iPad Pro 12.9" | Largest | Verify content doesn't look too sparse |
| iPad mini | Smallest (8.3") | Verify constrained layouts aren't too tight |
| iPhone 16 Pro | Reference | Ensure zero iPhone regression |

### Build Validation
- [ ] App Store validation passes
- [ ] Build runs on iPad Pro 12.9" Simulator
- [ ] Build runs on iPad mini Simulator
- [ ] Build runs on iPhone 16 Pro Simulator (regression check)
- [ ] Build runs on physical iPad (if available)

### Core Functionality
- [ ] In-app purchases work on iPad (previously broken in compatibility mode, now fixed)
- [ ] Camera capture works
- [ ] Photo upload works
- [ ] Discoveries display correctly
- [ ] Audio playback works

### UI Testing
- [ ] Discovery grid layout appropriate for screen size
- [ ] Detail overlay doesn't appear oversized
- [ ] Onboarding slides readable and well-proportioned
- [ ] Settings accessible and usable
- [ ] All sheets and modals sized appropriately

### Keyboard & Accessibility
- [ ] On-screen keyboard avoidance works on Auth forms (iPad keyboard is larger)
- [ ] Keyboard avoidance works on any text input fields
- [ ] Dynamic Type: Test with accessibility large text enabled
- [ ] Dynamic Type: Verify adaptive fonts don't compound excessively

---

## Effort Estimates

| Component | Effort | Priority |
|-----------|--------|----------|
| Build config | ⭐ Minimal | **P0** ✅ |
| App icons | ⭐ Minimal | **P0** ✅ |
| Info.plist | ⭐ Minimal | **P0** ✅ |
| StoreKit testing | ⭐⭐ Low | **P0** |
| Grid layout | ⭐⭐⭐ Medium | **P1** |
| Detail overlay | ⭐⭐⭐ Medium | **P1** |
| Onboarding | ⭐⭐ Low-Medium | **P2** |
| Camera flow | ⭐⭐ Low-Medium | **P2** |
| Settings | ⭐ Low | **P3** |
| Authentication | ⭐ Low | **P3** |
| Audio guides | ⭐ Low | **P3** |

---

## Recommended Approach

### Current Strategy: Portrait-Only Full-Screen

We are using a simplified iPad support strategy:

1. ✅ `TARGETED_DEVICE_FAMILY = "1,2"` (universal app)
2. ✅ iPad app icons added
3. ✅ `UIRequiresFullScreen = true` (no multitasking)
4. ✅ Portrait-only orientation
5. ⬜ Test in-app purchases on iPad
6. ⬜ UI adaptation for larger screens (optional)

**Rationale:**
- Matches iPhone behavior and existing UI design
- Avoids complexity of landscape layouts
- Simplifies testing matrix
- Can be expanded later if needed

---

### Future Option: Full iPad Experience

If we later want a polished iPad experience with multitasking:

1. Remove `UIRequiresFullScreen`
2. Add all 4 iPad orientations
3. Implement all Phase 4 UI adaptations
4. Address all global patterns (Phase 5)
5. Complete testing checklist (Phase 7)

**Effort:** ~1-2 weeks
**Result:** Native, polished iPad experience with multitasking
