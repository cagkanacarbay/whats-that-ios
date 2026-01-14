# iPad UI Requirements

This document identifies all screen UI elements that need adaptation for iPad support. Each section covers a specific screen or flow with detailed requirements.

---

## Status Overview

| Screen/Flow | Status | Priority |
|-------------|--------|----------|
| My Discoveries (Gallery) | ⬜ Not Started | P1 |
| Discovery Detail View | ⬜ Not Started | P1 |
| Audio Guides Page | ⬜ Not Started | P1 |
| Mini Player | ⬜ Not Started | P1 |
| Creation Flow | ⬜ Not Started | P2 |
| Camera Flow | ⬜ Not Started | P2 |
| Streaming/Result View | ⬜ Not Started | P2 |
| Settings Sheet | ⬜ Not Started | P3 |
| Authentication Pages | ⬜ Not Started | P2 |
| Onboarding Pages | ⬜ Not Started | P1 |

---

## My Discoveries Tab

### Gallery View

**Current State:** The gallery grid is mostly working well on iPad.

**Required Changes:**

| Element | Issue | Solution |
|---------|-------|----------|
| Discovery titles | Too small, not visible enough | Increase font size significantly for iPad |

**Implementation Notes:**
- Use `@Environment(\.horizontalSizeClass)` to detect iPad
- Apply larger font sizes only when `sizeClass == .regular`
- Titles should take up more space and be easily readable at a glance

---

## Discovery Detail View

**Current State:** Text elements are too small for the iPad screen size.

**Required Changes:**

| Element | Issue | Solution |
|---------|-------|----------|
| Title | Too small | Increase font size for iPad |
| Short description | Too small | Increase font size for iPad |
| Date | Too small | Increase font size for iPad |
| "Generate Audio" button | Too small | Increase button size (padding + font) for iPad |
| Presentation | Looks like a sheet | Force full screen presentation specific for iPad |

**Implementation Notes:**
- All text elements need to scale up proportionally
- The "Generate Audio" / "Play Audio" button should be more prominent
| "Generate Audio" button | Too small | Increase button size (padding + font) for iPad |
| Presentation | Looks like a sheet | Force full screen presentation specific for iPad |

**Implementation Notes:**
- All text elements need to scale up proportionally
- The "Generate Audio" / "Play Audio" button should be more prominent
- **Force full screen layout:** The detail view should occupy the full screen on iPad, not appearing as a sheet/card.

---

## Audio Guides Page

**Current State:** All UI elements are too small for iPad. The central audio player doesn't utilize the available screen space.

**Required Changes:**

| Element | Issue | Solution |
|---------|-------|----------|
| All text elements | Too small | Increase font sizes throughout |
| Central audio player + image | Too small | Enlarge to take up most of the screen |
| My Discoveries list items | Text too small | Increase font size for list items |
| Up Next list items | Text too small | Increase font size for list items |
| Audio pill/badge | Position may shift | Maintain relative position when enlarging |

**Implementation Notes:**
- The central audio player with album art should dominate the screen
- When expanding My Discoveries or Up Next lists, ensure list items have larger text
- Keep the audio pill in approximately the same position relative to the player

---

## Mini Player

> [!IMPORTANT]
> This component requires a **redesign** for iPad, not just scaling.

**Current State:** Mini player spans the entire horizontal width of the screen.

**Required Changes:**

| Element | Issue | Solution |
|---------|-------|----------|
| Mini player container | Spans full width | Centered with max-width, bigger than iPhone |
| Mini player size | Too small for iPad | Increase width AND height on iPad |
| Toast notifications | Need consistent positioning | Keep same logic: appear above mini player |
| Toast width | Too wide on iPad | Slightly smaller max-width than mini player |
| Toast text | Too small | Bigger fonts on iPad |

**Design Specification (iPad):**
```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│              ┌─────────────────────────┐                         │
│              │  Toast Message          │ (slightly narrower)     │
│              └─────────────────────────┘                         │
│                                                                  │
│            ┌───────────────────────────┐                         │
│            │  🎵  Discovery Title      │                         │
│            │      Playing...           │  (bigger width/height)  │
│            └───────────────────────────┘                         │
│                    Centered                                      │
└──────────────────────────────────────────────────────────────────┘
```

**Implementation Notes:**
- Mini player: `frame(maxWidth: ~500pt)` + increased height on iPad
- Toast: `frame(maxWidth: ~450pt)` (slightly smaller than mini player)
- Toast positioning: Keep same logic as iPhone (above mini player)
- Both centered horizontally
- Apply `.adaptiveBody()` or larger fonts to toast text on iPad

---

## Creation Flow

**Current State:** Most UI elements are appropriately sized, with some exceptions.

**Required Changes:**

| Element | Issue | Solution |
|---------|-------|----------|
| Credits message | Too small | Increase font size |
| "Audio" label near toggle | Too small | Increase font size slightly |
| Audio info popup | Text too small | Increase all text sizes in popup |

**Things That Are Fine (No Changes Needed):**
- Toggle size
- Button sizes
- General layout

**Implementation Notes:**
- Focus on text legibility for informational labels
- The audio toggle's label should be slightly larger but proportional

---

## Camera Flow

**Current State:** Similar issues to Creation Flow.

**Required Changes:**
- Same requirements as Creation Flow apply
- Credits message and audio label need larger text

**Things That Are Fine:**
- Buttons
- Camera preview
- General UI structure

---

## Streaming/Result View

**Current State:** During the streaming process, animations display correctly. The resulting discovery details view has the same issues as the main Discovery Detail View.

**Required Changes:**

| Element | Issue | Solution |
|---------|-------|----------|
| Streaming animations | ✅ Fine | No changes needed |
| Result title | Too small | Increase font size |
| Result description | Too small | Increase font size |
| Result date | Too small | Increase font size |
| "Generate Audio" / "Play Audio" button | Too small | Increase button size |

**Implementation Notes:**
- Apply the same scaling factors as Discovery Detail View
- Streaming animations and progress indicators are acceptable as-is

---

## Settings Sheet

**Current State:** The sheet could be slightly larger for iPad.

**Required Changes:**

| Element | Issue | Solution |
|---------|-------|----------|
| Sheet height | Could be taller | Increase sheet height for iPad |
| All text in settings | Slightly small | Increase font sizes slightly |

**Sub-sheets That Are Fine (No Changes Needed):**
- Credits sheet
- Content preferences sheet
- Voice model sheet

**Implementation Notes:**
- Adjust `.presentationDetents()` for iPad to make the sheet taller
- Keep the width as-is (standard sheet width is fine)
- Only the main settings view needs text sizing adjustments

---

## Authentication Pages

**Current State:** Content is left-aligned and text is too small.

**Required Changes:**

| Element | Issue | Solution |
|---------|-------|----------|
| Content alignment | Left-aligned | Center all content on iPad |
| All text elements | Too small | Increase font sizes |
| Logo | Alignment issue | Center along with content |

**Affected Screens:**
- Sign Up page
- Login page
- Forgot Password page

**Implementation Notes:**
- Content should be horizontally centered on iPad
- Do NOT increase the width of the content—keep it constrained
- Only center the existing content block and scale up text
- Form fields and buttons should maintain reasonable max-width

**Design Specification:**
```
iPhone (current):                 iPad (target):
┌────────────────┐               ┌────────────────────────────┐
│ [Logo]         │               │                            │
│ Email:         │               │          [Logo]            │
│ [Input      ]  │               │          Email:            │
│ Password:      │               │         [Input    ]        │
│ [Input      ]  │               │          Password:         │
│ [Login]        │               │         [Input    ]        │
└────────────────┘               │          [Login]           │
    Left-aligned                 │                            │
                                 └────────────────────────────┘
                                         Centered
```

---

## Onboarding Pages

> [!IMPORTANT]
> This section requires significant layout changes for iPad.

**Current State:** Images cover the entire screen, hiding the text content below.

**Required Changes:**

| Element | Issue | Solution |
|---------|-------|----------|
| Onboarding images | Cover entire screen | Constrain image size, add padding on sides |
| Text content | Hidden/obscured by images | Ensure text is fully visible below the image |
| Image aspect | Edge-to-edge | Add background color on left/right sides |

**Design Specification:**

**iPhone (current, acceptable):**
```
┌────────────────────────────────┐
│                                │
│     [Image fills width]        │
│                                │
│                                │
├────────────────────────────────┤
│ Title Text                     │
│ Description text here...       │
│ [Continue Button]              │
└────────────────────────────────┘
```

**iPad (required):**
```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│  [bg]    ┌────────────────────────┐    [bg]             │
│  color   │                        │    color            │
│          │   Image (maxWidth)     │                     │
│          │                        │                     │
│          └────────────────────────┘                     │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                                                          │
│              Title Text (larger)                         │
│              Description text here...                    │
│              [Continue Button]                           │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

**Implementation Notes:**
- On iPad, images should NOT span edge-to-edge
- Add max-width constraint to images (~500-600pt)
- Background color shows on left and right of image
- Ensure text section has enough vertical space to be fully visible
- Make images "as big as possible while ensuring text fits completely"
- Text should also be larger on iPad

---

## Global Implementation Guidelines

### Detection Pattern

Use this pattern for iPad-specific adaptations:

```swift
import UIKit

extension UIDevice {
    static var isIPad: Bool {
        current.userInterfaceIdiom == .pad
    }
}

// In SwiftUI views:
@Environment(\.horizontalSizeClass) private var horizontalSizeClass

private var isIPad: Bool {
    horizontalSizeClass == .regular
}
```

### Font Scaling Strategy ✅ DECIDED

> [!IMPORTANT]
> **Requirement: Zero iPhone Impact.** When checking iPhone, absolutely nothing should change.

Create a shared `Font` extension for consistent, safe scaling:

```swift
import SwiftUI
import UIKit

extension Font {
    /// Title text (e.g., discovery titles, screen headers)
    /// iPhone: .title2 → iPad: .title
    static func adaptiveTitle() -> Font {
        UIDevice.isIPad ? .title : .title2
    }
    
    /// Body text (e.g., descriptions, main content)
    /// iPhone: .body → iPad: .title3
    static func adaptiveBody() -> Font {
        UIDevice.isIPad ? .title3 : .body
    }
    
    /// Callout text (e.g., labels, secondary info)
    /// iPhone: .callout → iPad: .body
    static func adaptiveCallout() -> Font {
        UIDevice.isIPad ? .body : .callout
    }
    
    /// Caption text (e.g., dates, metadata)
    /// iPhone: .caption → iPad: .callout
    static func adaptiveCaption() -> Font {
        UIDevice.isIPad ? .callout : .caption
    }
}
```

**Why This Is Safe:**
- `UIDevice.isIPad` returns `false` on iPhone → iPhone always gets the original font
- No conditional logic changes anything for iPhone
- Each method returns exactly the iPhone font when on iPhone

**Usage:**
```swift
// Before (iPhone-only):
Text("Title").font(.title2)

// After (adaptive, zero change on iPhone):
Text("Title").font(.adaptiveTitle())
```

### Testing Requirements

For each modified screen:
- [ ] Test on iPhone simulator (ensure no changes)
- [ ] Test on iPad simulator (verify improvements)
- [ ] Test on physical iPad if available
- [ ] Verify text is readable at arm's length
- [ ] Verify buttons are easily tappable

---

## Implementation Guide

This section provides the complete implementation details. Follow these steps in order.

---

### Step 1: Create Foundation Extensions

Create these two files in the `Support` directory:

#### [NEW] `UIDevice+isIPad.swift`

**Path:** `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Support/UIDevice+isIPad.swift`

```swift
import UIKit

extension UIDevice {
    /// Returns true if running on iPad, false on iPhone
    /// This is safe to use for conditional UI—iPhone code path is completely isolated
    static var isIPad: Bool {
        current.userInterfaceIdiom == .pad
    }
}
```

---

#### [NEW] `Font+Adaptive.swift`

**Path:** `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Support/Font+Adaptive.swift`

```swift
import SwiftUI
import UIKit

extension Font {
    /// Large title text — iPhone: .title, iPad: .largeTitle
    static func adaptiveLargeTitle() -> Font {
        UIDevice.isIPad ? .largeTitle : .title
    }
    
    /// Title text — iPhone: .title2, iPad: .title
    static func adaptiveTitle() -> Font {
        UIDevice.isIPad ? .title : .title2
    }
    
    /// Body text — iPhone: .body, iPad: .title3
    static func adaptiveBody() -> Font {
        UIDevice.isIPad ? .title3 : .body
    }
    
    /// Callout text — iPhone: .callout, iPad: .body
    static func adaptiveCallout() -> Font {
        UIDevice.isIPad ? .body : .callout
    }
    
    /// Caption text — iPhone: .caption, iPad: .callout
    static func adaptiveCaption() -> Font {
        UIDevice.isIPad ? .callout : .caption
    }
}
```

---

### Step 2: Create Layout Constants

#### [NEW] `IPadLayout.swift`

**Path:** `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Support/IPadLayout.swift`

```swift
import SwiftUI
import UIKit

/// Centralized layout constants for iPad adaptations
/// All iPad-specific constraints should reference these values
enum IPadLayout {
    /// Mini player max width on iPad (centered, not full width)
    static let miniPlayerMaxWidth: CGFloat = 500
    
    /// Toast max width (slightly narrower than mini player)
    static let toastMaxWidth: CGFloat = 450
    
    /// Onboarding image max width
    static let onboardingImageMaxWidth: CGFloat = 600
    
    /// Auth form content max width
    static let authContentMaxWidth: CGFloat = 400
    
    /// Audio player image max width
    static let audioPlayerImageMaxWidth: CGFloat = 400
}
```

---

### Step 3: Modify Mini Player

**File:** `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/AudioGuides/MiniPlayerView.swift`

**Changes:**
1. Wrap mini player in a container with max-width on iPad:
   ```swift
   .frame(maxWidth: UIDevice.isIPad ? IPadLayout.miniPlayerMaxWidth : .infinity)
   .frame(maxWidth: .infinity) // This centers it
   ```
2. Increase internal padding/height on iPad
3. Apply `.adaptiveBody()` to title text

---

### Step 4: Modify Toast Component

**File:** Find the toast notification component

**Changes:**
1. Add max-width constraint (slightly smaller than mini player):
   ```swift
   .frame(maxWidth: UIDevice.isIPad ? IPadLayout.toastMaxWidth : .infinity)
   ```
2. Apply `.adaptiveBody()` to toast text
3. Keep positioning logic unchanged (above mini player)

---

### Step 5: Screen-by-Screen Text Scaling

For each file below, replace font modifiers with adaptive versions:

| Current | Replace With |
|---------|--------------|
| `.font(.title)` | `.font(.adaptiveLargeTitle())` |
| `.font(.title2)` | `.font(.adaptiveTitle())` |
| `.font(.body)` | `.font(.adaptiveBody())` |
| `.font(.callout)` | `.font(.adaptiveCallout())` |
| `.font(.caption)` | `.font(.adaptiveCaption())` |

---

#### P1 Screens (High Priority)

**Gallery View Titles:**
- **File:** `Features/DiscoveriesFeed/Grid/DiscoveriesGridView.swift`
- **Change:** Discovery title fonts → `.adaptiveTitle()`

**Audio Guides Page:**
- **File:** `Features/AudioGuides/AudioGuidesPageView.swift`
- **Changes:** 
  - Player title/artist → `.adaptiveTitle()` / `.adaptiveBody()`
  - List item titles → `.adaptiveBody()`
  - Central player image: `frame(maxWidth: UIDevice.isIPad ? 400 : 200)` or similar

**Onboarding Pages:**
- **Files:** `Features/Onboarding/PreOnboardingCarousel.swift`, `PostOnboardingCarousel.swift`, `OnboardingSlidePage.swift`
- **Changes:**
  - Image container: `frame(maxWidth: UIDevice.isIPad ? IPadLayout.onboardingImageMaxWidth : .infinity)`
  - Title/description fonts → adaptive versions

---

#### P2 Screens (Medium Priority)

**Discovery Detail View:**
- **File:** `Features/DiscoveriesFeed/DetailOverlay/DiscoveryDetailView.swift`
- **Changes:** Title, description, date fonts → adaptive versions

**Streaming Result View:**
- **File:** `Features/DiscoveryCreation/Stages/Streaming/DiscoveryStreamingStageView.swift`
- **Changes:** Same as Discovery Detail View

**Authentication Pages:**
- **Files:** `Features/Authentication/LoginForm.swift`, `SignUpForm.swift`, `ForgotPasswordForm.swift`
- **Changes:**
  - Content container: wrap in `VStack` with `frame(maxWidth: UIDevice.isIPad ? IPadLayout.authContentMaxWidth : .infinity)` centered
  - All text fonts → adaptive versions

---

#### P3 Screens (Lower Priority)

**Creation/Camera Flow:**
- **File:** `Features/DiscoveryCreation/Stages/Confirmation/DiscoveryConfirmationView.swift`
- **Changes:** Credits message, audio label → `.adaptiveCallout()`

**Settings Sheet:**
- **File:** `Features/Settings/SettingsView.swift`
- **Changes:**
  - Adjust `.presentationDetents()` to include larger size for iPad
  - Text fonts → adaptive versions

---

### Step 5: Verification Checklist

After implementation, verify each change:

#### iPhone Verification (Zero Changes)
- [ ] Build and run on iPhone 16 Pro simulator
- [ ] Gallery view looks exactly the same
- [ ] Discovery detail looks exactly the same
- [ ] Audio guides looks exactly the same
- [ ] Onboarding looks exactly the same
- [ ] Auth screens look exactly the same
- [ ] Settings sheet looks exactly the same
- [ ] Mini player looks exactly the same
- [ ] Toasts look exactly the same

#### iPad Verification (Verify Improvements)
- [ ] Build and run on iPad Pro (12.9-inch) simulator
- [ ] Gallery: Titles are larger and readable
- [ ] Discovery detail: All text is larger
- [ ] Audio guides: Player larger, text larger
- [ ] Onboarding: Images constrained, text fully visible
- [ ] Auth screens: Content centered, text larger
- [ ] Settings: Sheet taller if needed, text larger
- [ ] Mini player: Centered with max-width, larger
- [ ] Toasts: Max-width, larger text, positioned above player

---

### Build Verification Commands

Run these to verify the build compiles on both devices:

**iPhone (regression check):**
```bash
cd /Users/cagkanacarbay/Projects/whats-that/whats-that-ios/native

xcodebuild -workspace WhatsThatIOS.xcworkspace \
  -scheme "WhatsThatIOS" \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/WhatsThatBuild \
  build
```

**iPad Pro 12.9" (largest iPad):**
```bash
xcodebuild -workspace WhatsThatIOS.xcworkspace \
  -scheme "WhatsThatIOS" \
  -destination 'platform=iOS Simulator,name=iPad Pro 12.9-inch (M4)' \
  -derivedDataPath /tmp/WhatsThatBuild \
  build
```

---

## Summary of Files to Create/Modify

### New Files
| File | Path |
|------|------|
| `UIDevice+isIPad.swift` | `WhatsThatPresentation/Support/` |
| `Font+Adaptive.swift` | `WhatsThatPresentation/Support/` |
| `IPadLayout.swift` | `WhatsThatPresentation/Support/` |

### Modified Files

| Screen | File(s) | Priority |
|--------|---------|----------|
| Mini Player | `Features/AudioGuides/MiniPlayerView.swift` | P1 |
| Toast Overlays | `App/Toasts/DiscoveryCompletionToastOverlay.swift`, `AudioGuideCompletionToastOverlay.swift` | P1 |
| Gallery | `Features/DiscoveriesFeed/Grid/DiscoveriesGridView.swift` | P1 |
| Audio Guides | `Features/AudioGuides/AudioGuidesPageView.swift` | P1 |
| Onboarding | `Features/Onboarding/PreOnboardingCarousel.swift`, `PostOnboardingCarousel.swift`, `OnboardingSlidePage.swift` | P1 |
| Detail View | `Features/DiscoveriesFeed/DetailOverlay/DiscoveryDetailView.swift` | P2 |
| Streaming | `Features/DiscoveryCreation/Stages/Streaming/DiscoveryStreamingStageView.swift` | P2 |
| Auth | `Features/Authentication/LoginForm.swift`, `SignUpForm.swift`, `ForgotPasswordForm.swift` | P2 |
| Creation | `Features/DiscoveryCreation/Stages/Confirmation/DiscoveryConfirmationView.swift` | P3 |
| Settings | `Features/Settings/SettingsView.swift` | P3 |

