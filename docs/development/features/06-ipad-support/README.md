# iPad Support

This document outlines the work required to properly support iPad for the What's That app.

## Status Summary

| Phase | Status |
|-------|--------|
| Build Configuration | ✅ Complete |
| App Icons | ✅ Complete |
| Info.plist | ✅ Complete |
| UI Adaptation | ⬜ Not Started |
| Testing | ⬜ Not Started |

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

The app currently has no adaptive layout code. All UI is designed for iPhone dimensions. The following areas need work to provide a polished iPad experience.

### 4.1 Discovery Feed Grid (Medium Effort)

**Current State:**
- Fixed 2-column grid calculated as `(availableWidth - spacing) / 2`
- Uses `UIScreen.main.bounds` for layout calculations
- Cards become excessively large on iPad (500+ pts wide)

**Required Changes:**
- Add `@Environment(\.horizontalSizeClass)` to detect iPad
- Implement dynamic column count: 2 columns (compact) → 3-4 columns (regular)
- Cap maximum card width at ~200pt
- Refactor `resolveCloseFrame()` and related geometry

**Files to Modify:**
- `WhatsThatPresentation/Features/DiscoveriesFeed/Grid/DiscoveriesGridView.swift`
- `WhatsThatPresentation/Features/DiscoveriesFeed/DiscoveriesHomeView.swift`

**Example Implementation:**
```swift
@Environment(\.horizontalSizeClass) private var horizontalSizeClass

private var columnCount: Int {
    horizontalSizeClass == .regular ? 4 : 2
}

private var cardWidth: CGFloat {
    let columns = CGFloat(columnCount)
    let totalSpacing = cardSpacing * (columns - 1)
    return min((availableWidth - totalSpacing) / columns, 200)
}
```

---

### 4.2 Discovery Detail Overlay (Medium Effort)

**Current State:**
- Full-screen overlay using `UIScreen.main.bounds`
- Animations assume phone-sized viewport

**Required Changes:**
- Constrain detail view to max ~600pt width on iPad (centered)
- Update transition animation calculations
- Adjust edge drag gesture handling for wider screens

**Files to Modify:**
- `WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/` (17 files)

---

### 4.3 Camera/Photo Capture Flow (Low-Medium Effort)

**Current State:**
- Designed for portrait phone

**Required Changes:**
- Test camera preview on iPad (AVFoundation usually handles this)
- Add max-width constraints to confirmation views
- Verify streaming/progress views adapt

**Files to Modify:**
- `WhatsThatPresentation/Features/DiscoveryCreation/` (18 files)

---

### 4.4 Onboarding Flow (Low-Medium Effort)

**Current State:**
- Carousel-style slides with page indicators

**Required Changes:**
- Add max-width constraints (~500pt) to slide content
- Verify image/illustration aspect ratios
- Test page indicator positioning

**Files to Modify:**
- `WhatsThatPresentation/Features/Onboarding/` (8 files)

---

### 4.5 Settings View (Low Effort)

**Current State:**
- Uses `NavigationStack` with `List` — SwiftUI handles most adaptation

**Required Changes:**
- Adjust sheet `.presentationDetents()` for iPad
- Optional: Consider `NavigationSplitView` for sidebar navigation

**Files to Modify:**
- `WhatsThatPresentation/Features/Settings/SettingsView.swift`

---

### 4.6 Credits/Purchase View (Low Effort)

**Current State:**
- Purchase UI presented as a sheet

**Required Changes:**
- Add appropriate `.presentationDetents()` for iPad
- Add max-width constraints if needed

**Files to Modify:**
- `WhatsThatPresentation/Features/Credits/CreditsView.swift`

---

### 4.7 Audio Guides (Low Effort)

**Current State:**
- Mini-player and audio controls

**Required Changes:**
- Verify mini-player positioning with different safe areas
- Add max-width constraints to full player view if needed

**Files to Modify:**
- `WhatsThatPresentation/Features/AudioGuides/` (10 files)

---

### 4.8 Authentication (Low Effort)

**Current State:**
- Sign-in screens

**Required Changes:**
- Add max-width constraints (~400pt) to form layouts
- Sign in with Apple should work without changes

**Files to Modify:**
- `WhatsThatPresentation/Features/Authentication/` (7 files)

---

## Phase 5: Global Patterns to Address

### Pattern 1: `UIScreen.main.bounds` Usage

**Problem:** Used extensively for layout calculations, particularly in:
- `DiscoveriesHomeView.swift` — grid calculations, fallback frames
- Animation/transition code

**Solution:** Replace with `GeometryReader` values or SwiftUI's layout system.

---

### Pattern 2: No Size Class Awareness

**Problem:** Zero usage of `horizontalSizeClass` or `UIDevice.current.userInterfaceIdiom`

**Solution:** Add environment variable hooks throughout navigation and layout code.

---

### Pattern 3: Hardcoded Dimensions

**Problem:** Various fixed values like `cardWidth * 1.2`, `360`, `min(screen.width * 0.9, 360)`

**Solution:** Replace with adaptive calculations using size classes.

---

## Phase 6: Multitasking Support ❌

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

## Phase 7: Testing Checklist

### Build Validation
- [ ] App Store validation passes
- [ ] Build runs on iPad Simulator
- [ ] Build runs on physical iPad

### Core Functionality
- [ ] In-app purchases work on iPad
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

### Multitasking
- [ ] App handles Split View entry/exit
- [ ] App handles Slide Over
- [ ] Layout updates on size class changes

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
