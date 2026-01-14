# iPad Support Changes Tracker

This document tracks all changes made to the codebase to support native iPad UI adaptation.

## Foundation
- [x] **UIDevice+isIPad.swift**
  - Added shared `isIPad` boolean property in `WhatsThatShared`
  - Re-exported in `WhatsThatPresentation`
- [x] **Font+Adaptive.swift**
  - Added `adaptiveSystem(size:weight:scaleFactor:)` to `Font`
  - Default scale factor 1.4x for iPad, 1.0x for iPhone
- [x] **IPadLayout.swift**
  - Added centralized layout constants (`miniPlayerMaxWidth`, `authContentMaxWidth`, etc.)
- [x] **BrandComponents.swift**
  - Primary/Secondary Buttons: Added iPad-specific vertical padding (14pt -> 18pt)
  - Social Buttons: Scaled icons and padding
  - Floating Fields: Increased height (52pt -> 64pt), updated offsets, constrained max width
- [x] **BrandMarkdownTheme.swift**
  - Updated `BrandMarkdownThemeFactory` to use `UIDevice.isIPad`
  - Added adaptive scaling for all markdown elements (Body 16->22.4, Headings scaled)

## Feature: Discoveries Feed
- [x] **DiscoveryCardView.swift**
  - Updated card title to use `adaptiveSystem` (13pt base)

## Feature: Discovery Detail
- [x] **DiscoveryDetailView**
  - Force full screen presentation on iPad (override any sheet-like appearance)
- [x] **DiscoveryHeaderOverlayView.swift**
  - Updated Title (26pt base), Date (14pt base), Short Desc (13pt base) to `adaptiveSystem`
- [x] **DiscoveryDetailContentView** (in `DiscoveryDetailView.swift`)
  - Updated fallback description text to `adaptiveSystem` (16pt base)
  - Updated highlight text to `adaptiveSystem` (16pt base)
- [x] **DiscoveryAudioControls.swift** (Generate Audio Button)
  - Updated button height (50pt -> 66pt on iPad)
  - Updated main icon size (36pt -> 48pt circle, 16pt -> 22pt icon on iPad)
  - Updated main text font (16pt -> 22pt on iPad)
  - Updated queue action icons (14pt -> 18pt) and text (9pt -> 12pt) on iPad

## Feature: Creation Flow
### Streaming Stage
- [x] **DiscoveryStreamingLoaderView.swift**
  - Updated Status (18pt), Title (26pt), Date (14pt), Desc (14pt) to `adaptiveSystem`
- [x] **DiscoveryStreamingMarkdownView.swift**
  - Updated fallback "Analysis complete" and markdown text to `adaptiveSystem`
  - Markdown content scales via `BrandMarkdownThemeFactory`

### Confirmation Stage
- [x] **DiscoveryConfirmationActionsView.swift**
  - Updated Credits text (16pt -> adaptive)
  - Updated "Retake"/"Continue" buttons to use `scaleFactor: 1.3` (17pt -> ~22pt on iPad)
- [x] **AudioToggleView.swift**
  - Updated "Audio" label, info icon
  - Updated Popover title, body, and caption text
  - Increased popover padding and max width for iPad

## Feature: Audio Guides Page
### Hero Player (HeroPlayerView.swift)
- [x] **Layout & Sizing**
  - Ring size: 300pt (iPhone) -> 460pt (iPad)
  - Artwork size: 264pt (iPhone) -> 400pt (iPad)
  - Time labels width: 240pt (iPhone) -> 360pt (iPad)
- [x] **Typography**
  - Title font: Scaled to 28pt Bold on iPad
  - Time labels: Caption -> 18pt Medium on iPad
- [x] **Controls**
  - Play/Pause button: 64pt -> 88pt on iPad
  - Seek/Skip buttons: 24pt -> 32pt on iPad
  - Autoplay Toggle: Scaled 1.5x on iPad
  - Bottom controls (Speed/Autoplay) centered on iPad with fixed spacing

### Lists & Rows
- [x] **AudioGuideRowView.swift**
  - Thumbnail size: 56pt -> 80pt on iPad
  - Title text: Body -> Adaptive 16pt
  - Duration/Status text: Caption -> Adaptive 14pt
  - Checkmark/Icons: Scaled up on iPad
  - Menu (Ellipsis) icon: Scaled up to 20pt on iPad
- [x] **AudioGuidesPageView.swift**
  - Updated Section Headers ("Up Next", "Just Played") to `adaptiveSystem`
  - Updated Toggles ("Autoplay", "Show without audio") text to `adaptiveSystem`
  - Updated Tab Toggles ("Up Next", "My Discoveries") text to `adaptiveSystem`
  - Increased Tab Toggle button size for iPad (44pt height vs 32pt)
  - **Refinement:** Increased "My Discoveries" date section headers (Caption -> Adaptive 16pt Bold)
  - **Refinement:** Increased Menu Item labels (System -> Adaptive 17pt)

## Feature: Onboarding
- [x] **OnboardingSlidePage.swift**
  - Added layout logic to constrain image height on compact/iPad screens
  - Constrained content width to ensure readability on larger screens

## Feature: Authentication
- [x] **Shared Layout**
  - Constrained content max width to `400pt` (`IPadLayout.authContentMaxWidth`) for all auth forms
- [x] **LoginForm.swift**
  - Updated "Welcome back" title (28pt bold adaptive)
  - Updated all inputs to `BrandFloatingField` (adaptive height/font)
  - Updated Primary Button (adaptive padding)
  - Updated Links/Buttons fonts to `adaptiveSystem`
- [x] **SignUpForm.swift**
  - Updated Title and inputs to `adaptiveSystem`
  - Constrained max width
- [x] **ForgotPasswordForm.swift** / **PasswordResetView.swift**
  - Updated Title, body, and inputs to `adaptiveSystem`
  - Constrained max width
- [x] **AuthenticationFlowView.swift**
  - Updated container styling to support constrained centered content on iPad

## Feature: Settings
- [x] **SettingsView.swift**
  - **Rows & Padding**: Added extra vertical padding (10pt vs 4pt) for iPad rows to improve touch targets
  - **Typography**: Updated all section headers, labels, and footer text to `adaptiveSystem` or `adaptiveBody`/`adaptiveCaption`
  - **Toggle**: Updated photo save toggle label to adaptive
  - **Custom Rows**: Updated Voice Model, Credits, and Content Preference rows with larger icons and adaptive text

## Feature: Mini Player & Toasts (Refinements)
- [x] **MiniPlayerView.swift**
  - Increased artworkDiameter: 154pt → 168pt on iPad (prevents title clipping)
  - Increased backgroundHeight: 118pt → 136pt on iPad (more vertical space for title)
  - Adjusted spacer width: 170pt → 185pt on iPad (balances with larger artwork)
- [x] **IPadLayout.swift**
  - Increased toastMaxWidth: 480pt → 540pt (now wider than mini player for content fit)
- [x] **GenerationCompleteToastView.swift** / **DiscoveryCompletionToastView.swift**
  - Unified thumbnail sizes: 80x80pt on iPad (was 60/100 inconsistently)
  - Unified button circle sizes for iPad
  - Unified typography: Title (17pt), Subtitle (14pt), Buttons (16pt) - matching Audio Guide toast
- [x] **UnifiedToastOverlay.swift** [NEW]
  - Created unified overlay that coordinates both toast types
  - Audio guide toasts have priority (more immediately actionable)
  - Single badge counter shows combined total from both queues
  - Badge moved to top-right corner, enlarged for iPad (18pt font, 32px circle)
- [x] **MainTabView.swift**
  - Replaced separate toast overlays with single `UnifiedToastOverlay`

