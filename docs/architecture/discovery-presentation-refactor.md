# Discovery Presentation Refactor Plan

## Context
- `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/DiscoveryCreationFlowView.swift` currently spans 1,462 lines with router logic, UI for every state, loader animations, and UIKit interop embedded together.
- `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/DiscoveriesHomeView.swift` is 2,068 lines combining feed orchestration, grid layout, hero overlay animation, voiceover playback chrome, and support utilities.
- Nested helper types (cards, overlays, loaders, share sheet helpers, preference keys) are declared inside these files, limiting reuse and making targeted tests cumbersome.

## Goals
- Separate Discovery Creation flow into stage-specific SwiftUI views with clear responsibilities (Capture, Confirm, Streaming, End).
- Break the Discovery Feed (“My Discoveries”) experience into modular components: header, grid/cards, hero/detail overlay, voiceover controls, and error overlays.
- Introduce a predictable folder hierarchy under `WhatsThatPresentation` so each feature’s views, view models, and helpers reside together.
- Enable incremental refactors with testable surface areas and minimize churn for domain or infrastructure modules.

## Proposed Folder Structure

```text
native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/
├── Features/
│   ├── DiscoveryCreation/
│   │   ├── Flow/
│   │   │   ├── DiscoveryCreationFlowView.swift        # slim router that switches on stage
│   │   │   ├── DiscoveryCreationFlowViewModel.swift   # relocated from root
│   │   │   └── DiscoveryCreationFlowState+Extensions.swift
│   │   ├── Stages/
│   │   │   ├── Capture/
│   │   │   │   ├── DiscoveryCaptureStageView.swift
│   │   │   │   ├── DiscoveryCapturePlaceholderView.swift
│   │   │   │   └── DiscoveryCaptureProgressView.swift
│   │   │   ├── Confirmation/
│   │   │   │   ├── DiscoveryConfirmationView.swift
│   │   │   │   ├── DiscoveryConfirmationActionsView.swift
│   │   │   │   └── DiscoveryConfirmationLocationBadge.swift
│   │   │   ├── Streaming/
│   │   │   │   ├── DiscoveryStreamingStageView.swift
│   │   │   │   ├── DiscoveryStreamingLoaderView.swift
│   │   │   │   └── DiscoveryStreamingMarkdownView.swift
│   │   │   └── Completion/
│   │   │       ├── DiscoveryCompletionStageView.swift
│   │   │       └── DiscoveryCompletionShareController.swift
│   │   ├── Common/
│   │   │   ├── DiscoveryCreationOverlayButtonStyle.swift
│   │   │   ├── DiscoveryCreationPalette.swift
│   │   │   ├── DiscoveryCreationSharePresenter.swift
│   │   │   └── DiscoveryCreationViewConstants.swift
│   │   └── Tests/ (future snapshot/unit tests)
│   └── DiscoveriesFeed/
│       ├── DiscoveriesHomeView.swift                  # orchestrates feature-level composition
│       ├── Header/
│       │   ├── DiscoveriesHeaderView.swift
│       │   └── DiscoveriesHeaderMetrics.swift
│       ├── Grid/
│       │   ├── DiscoveriesGridView.swift
│       │   ├── DiscoveryCardView.swift
│       │   ├── DiscoveryCardSkeletonView.swift
│       │   ├── DiscoveryCardImageView.swift
│       │   └── DiscoveryCardPreferenceKeys.swift
│       ├── DetailOverlay/
│       │   ├── DiscoveryDetailOverlayView.swift
│       │   ├── DiscoveryDetailHeroAnimator.swift
│       │   ├── DiscoveryDetailDismissInteractor.swift
│       │   ├── DiscoveryDetailImageCache.swift
│       │   └── DiscoveryDetailContext.swift
│       ├── Voiceover/
│       │   ├── VoiceoverPlayerBar.swift
│       │   └── VoiceoverPlaybackBindings.swift
│       ├── Errors/
│       │   ├── DiscoveriesErrorToastView.swift
│       │   └── DiscoveriesErrorReducer.swift
│       └── Preferences/
│           ├── DiscoveriesScrollOffsetPreference.swift
│           └── DiscoveriesHeaderHeightPreference.swift
├── Shared/
│   ├── Components/                                    # existing Brand components stay here
│   └── Utilities/
└── Root/                                              # RootContentView, MainTabView, etc.
```

## Discovery Creation Flow Refactor

### Current Component Inventory
| Struct / Type | Scope | Responsibility Today | Target File |
| --- | --- | --- | --- |
| `DiscoveryCreationFlowView` | top-level file | Dispatches on `flowState` and renders nested stage structs | `Flow/DiscoveryCreationFlowView.swift` (router only) |
| `DiscoveryCreationFlowViewModel` | top-level file | Flow state orchestration, service calls | `Flow/DiscoveryCreationFlowViewModel.swift` (no behavioral changes) |
| `IdleStateView` | private struct | CTA with emoji + “Get started” button | `Stages/Capture/DiscoveryCaptureStartView.swift` |
| `ProgressStateView` | private struct | Circular progress and preparing label | `Stages/Capture/DiscoveryCaptureProgressView.swift` |
| `ErrorStateView` | private struct | Displays error emoji/message/CTA | `Common/DiscoveryCreationErrorView.swift` |
| `ConfirmationStateView` + helpers | private struct (≈480 lines) | Preview layout, credit chip, overlay buttons, alerts | `Stages/Confirmation/DiscoveryConfirmationView.swift` plus `DiscoveryConfirmationActionsView.swift`, `DiscoveryConfirmationOverlayButton.swift`, `DiscoveryConfirmationLocationPrompt.swift` |
| `BottomOverlayHeightPreferenceKey` | nested | Measure overlay height | `Common/Preferences/DiscoveryCreationBottomOverlayPreference.swift` |
| `AnalysisStateView` | private struct (≈700 lines) | Loader messaging, markdown animation, scroll management, share sheet | `Stages/Streaming/DiscoveryStreamingStageView.swift` with sub-files: `DiscoveryStreamingLoaderView.swift`, `DiscoveryStreamingMarkdownView.swift`, `DiscoveryStreamingSharePresenter.swift` |
| `ShimmerTextView`, `PulsingDotsView`, etc. | nested UI atoms | Visual embellishments for loader | `Common/Indicators/DiscoveryCreationShimmerTextView.swift`, `DiscoveryCreationPulsingDotsView.swift` |
| `IdentifiedError` | helper | bridges optional error to alert | `Common/DiscoveryCreationIdentifiedError.swift` |

Additional utilities inside `AnalysisStateView` (loader messages array, markdown animation constants, `DiscoveryStreamFormatter` references, share sheet presenter) will be collected into `Stages/Streaming` to keep logic localized.

### Target Stage Responsibilities
- **Capture Stage (`DiscoveryCaptureStageView`)**
  - Owns idle/permission/capture/upload states (`.idle`, `.requestingPermissions`, `.capturing*`, `.selecting*`).
  - Delegates to `viewModel.startFlow` / `viewModel.retake`.
  - Embeds `DiscoveryCaptureStartView`, `DiscoveryCaptureProgressView`, `DiscoveryCreationErrorView` if errors occur before confirmation.
  - Access to environment palette extracted to `DiscoveryCreationPalette`.
- **Confirmation Stage (`DiscoveryConfirmationStageView`)**
  - Wraps preview image, credit info, retake/continue actions with dedicated components.
  - Moves share/location permission alerts into dedicated view modifiers.
  - Uses `BottomOverlayHeightPreferenceKey` from `Common`.
- **Streaming Stage (`DiscoveryStreamingStageView`)**
  - Splits loader UI, markdown streaming, metadata reveal, share CTA.
  - `DiscoveryStreamingLoaderView` handles shuffled messages and crossfade animations.
  - `DiscoveryStreamingMarkdownView` hosts MarkdownUI usage with fallback text.
  - `DiscoveryStreamingSharePresenter` encapsulates share sheet bridging (UIKit/AppKit).
- **Completion Stage (`DiscoveryCompletionStageView`)**
  - Renders final markdown and metadata once streaming ends (`!state.isStreaming`).
  - Reuses `DiscoveryStreamingMarkdownView` but without loader state.
  - Hosts final action buttons (share, done).

### Refactor Task Breakdown
1. **Extract Common Types**
   - Move `BottomOverlayHeightPreferenceKey`, `IdentifiedError`, shimmer/pulsing views into `Common/`.
   - Update imports in existing file to new locations; ensure visibility (`internal`).
2. **Create Stage Files with Existing Content**
   - Copy `IdleStateView` → `DiscoveryCaptureStartView`.
   - Copy `ProgressStateView` → `DiscoveryCaptureProgressView`.
   - Copy confirmation block into `DiscoveryConfirmationView` and split overlays/actions into separate structs.
   - Copy `AnalysisStateView` into `DiscoveryStreamingStageView`, then peel out loader/markdown/share helpers into adjacent files.
   - Implement minimal `DiscoveryCompletionStageView` by reusing streaming components after `.isStreaming == false`.
3. **Rewrite `DiscoveryCreationFlowView`**
   - Replace nested `@ViewBuilder` branches with stage router calling new views.
   - Provide stage-specific dependencies (e.g., `DiscoveryStreamingStageView(viewModel: viewModel)`).
   - Keep alert handling via `IdentifiedError`.
4. **Validation**
   - Build after each extraction to ensure no missing imports (`swift build` or Xcode incremental build).
   - Confirm share sheet functionality from simulator once wiring completes.

### Open Questions
- End-stage UI copy/CTA: confirm with product whether a dedicated summary view is needed or reuse streaming view when `loaderCleared == true`.
- Whether stage views should be `public` for preview/testing use—pending module exposure decisions.

## Discoveries Feed Refactor

### Current Component Inventory
| Struct / Type | Scope | Responsibility Today | Target File |
| --- | --- | --- | --- |
| `DiscoveriesHomeView` | root struct (≈2,068 lines) | Coordinates feed state, renders header, grid, hero overlay, voiceover bar | `Features/DiscoveriesFeed/DiscoveriesHomeView.swift` (slim orchestrator) |
| `ScrollOffsetPreferenceKey`, `HeaderHeightPreferenceKey` | nested | Report scroll/header metrics | `Preferences/DiscoveriesScrollOffsetPreference.swift`, `Preferences/DiscoveriesHeaderHeightPreference.swift` |
| `DiscoveryCardFramePreferenceKey` | nested | Track card frames for hero animation | `Grid/DiscoveryCardPreferenceKeys.swift` |
| `DiscoveriesGrid` | private struct | Lazy grid with pagination and selection callbacks | `Grid/DiscoveriesGridView.swift` |
| `DiscoveryCardSkeleton`, `DiscoveryCard`, `DiscoveryCardImage`, `DiscoveryCardChrome` | nested | Skeleton state, card content, overlays | `Grid/DiscoveryCardSkeletonView.swift`, `DiscoveryCardView.swift`, `DiscoveryCardImageView.swift`, `DiscoveryCardChromeView.swift` |
| `DiscoveriesErrorView`, `EmptyDiscoveriesView`, `FeedErrorToast` | nested | Empty/error states, toast message | `Errors/DiscoveriesEmptyStateView.swift`, `DiscoveriesErrorToastView.swift` |
| `DiscoveryHeroContext`, `HiddenDiscovery` | nested types | Manage hero overlay state | `DetailOverlay/DiscoveryDetailContext.swift` |
| `DiscoveryHeroOverlay`, `HeroGeometry`, `UniformCloseTransform`, `DiscoveryHeroContentView`, `DiscoveryHeroTopControls` | nested | Full-screen detail overlay with animations and controls | `DetailOverlay/DiscoveryDetailOverlayView.swift`, `DiscoveryDetailHeroGeometry.swift`, `DiscoveryDetailUniformCloseTransform.swift`, `DiscoveryDetailContentView.swift`, `DiscoveryDetailTopControls.swift` |
| `HeroScrollOffsetPreferenceKey` | nested | Scroll offset tracking inside hero | `DetailOverlay/DiscoveryDetailPreferenceKeys.swift` |
| `DiscoveryHeroImageCache` | nested singleton | Cache card images for hero animation | `DetailOverlay/DiscoveryDetailImageCache.swift` |
| `VoiceoverPlayerBar` | nested struct | Persistent playback controls | `Voiceover/VoiceoverPlayerBar.swift` |

### Target Composition
- `DiscoveriesHomeView` remains responsible for:
  - Owning `DiscoveryFeedViewModel` state.
  - Coordinating `voiceoverController`, `pendingDiscoveryId`, `pendingCreatedSummary`.
  - Presenting feature components (`DiscoveriesHeaderView`, `DiscoveriesGridView`, `DiscoveryDetailOverlayView`, `VoiceoverPlayerBar`, error toasts).
- Subviews take on layout/animation heavy lifting:
  - `DiscoveriesHeaderView` handles geometry/background gradient, includes metrics helper struct for spacing logic.
  - `DiscoveriesGridView` exposes callbacks for selection, pagination, and uses `DiscoveryCardView` + skeleton.
  - `DiscoveryDetailOverlayView` orchestrates hero animation using helpers (geometry, dismiss interactor, image cache).
  - `VoiceoverPlayerBar` lifts out into its own file with supporting binding helper `VoiceoverPlaybackBindings.swift`.
  - Error/empty states become dedicated files to simplify readability and testing.

### Refactor Task Breakdown
1. **Preference Keys & Utilities**
   - Move `ScrollOffsetPreferenceKey`, `HeaderHeightPreferenceKey`, `HeroScrollOffsetPreferenceKey`, and `DiscoveryCardFramePreferenceKey` into respective files under `Preferences/` and `DetailOverlay/`.
   - Replace references in `DiscoveriesHomeView` with new type locations.
2. **Grid Extraction**
   - Copy `DiscoveriesGrid`, `DiscoveryCardSkeleton`, `DiscoveryCard`, `DiscoveryCardImage`, `DiscoveryCardChrome` into new `Grid/` files.
   - Update `DiscoveriesHomeView` to call `DiscoveriesGridView(...)`.
   - Keep `HiddenDiscovery` data type within grid module or move to `DetailOverlay` based on usage (context for hero).
3. **Header Extraction**
   - Convert `header(opacity:)` into `DiscoveriesHeaderView(opacity:onSignOut:onSettings:)`.
   - Extract metrics calculations (e.g., `headerContentHeight`, `gridTopPadding`) into `DiscoveriesHeaderMetrics` struct that accepts safe area insets.
4. **Detail Overlay Module**
   - Migrate `DiscoveryHeroOverlay` and supporting structs into separate files.
   - Create `DiscoveryDetailDismissInteractor` to own drag gesture math currently in `handleHeroDragChanged/Ended`.
   - Introduce `DiscoveryDetailHeroAnimator` to manage open/close animations and progress state.
5. **Voiceover & Errors**
   - Move `VoiceoverPlayerBar` into `Voiceover/`.
   - Extract `DiscoveriesErrorView`, `EmptyDiscoveriesView`, `FeedErrorToast` into `Errors/`.
6. **Simplify `DiscoveriesHomeView`**
   - After extraction, rewrite body to compose new components:
     ```swift
     DiscoveriesHeaderView(...)
     DiscoveriesGridView(...)
     DiscoveryDetailOverlayView(context: heroContext, ...)
     VoiceoverPlayerBar(...)
     DiscoveriesErrorToastView(...)
     ```
   - Keep hero gesture wiring but delegate calculations to interactor/animator classes.
7. **Validation**
   - Rebuild after each major extraction.
   - Perform manual run-through: pull-to-refresh, pagination, hero open/close, voiceover playback, error toast display.

### Data Flow Considerations
- Ensure `HiddenDiscovery` remains accessible where grid needs to hide cards; likely lives in `Grid/HiddenDiscovery.swift` and is imported by detail overlay module.
- Verify `DiscoveryHeroImageCache.shared` remains a singleton accessible across modules; consider protocol if future injection is desired.
- Confirm `VoiceoverPlaybackController` environment object semantics remain consistent once moved out of nested struct.

## Cross-Cutting Considerations
- Update any SwiftUI previews once files move (Xcode will expect new paths).
- Re-run `swift package resolve` if folder reorganization confuses SPM caching.
- Double-check module visibility; top-level SwiftPM target is `WhatsThatPresentation`, so new subfolders must remain under `Sources/WhatsThatPresentation`.
- Document transitions in `docs/architecture/discovery-presentation-refactor.md` and update README if necessary.
- Plan for snapshot/unit tests once structure stabilizes (placeholder files already accounted for in proposed tree).

## Implementation Phases (Detailed)

_Stage gate for every step_: run `swift build` via MCP before proceeding (must finish cleanly). After each successful build, notify the user so they can perform a visual check in the app.

1. **Scaffold & Common Extraction**
   - Create directory tree.
   - Move common helpers (preference keys, error identifier) into new files.
   - Build to confirm no regressions.
2. **Discovery Creation Stages**
   - Extract capture components, update router.
   - Extract confirmation components; ensure alerts, share actions preserved.
   - Extract streaming loader/markdown; introduce completion stage wrapper.
   - Validate flow by running through camera/upload paths in simulator.
3. **Discoveries Grid & Header**
   - Move grid/card/skeleton components.
   - Move preference keys and adjust data flow for card frames.
   - Extract header view & metrics; ensure scroll behavior remains intact.
4. **Hero Overlay & Voiceover Modules**
   - Create detail overlay module files; integrate animator/interactor objects.
   - Move image cache, hero context, and voiceover player out of monolith.
   - Reconnect gestures and voiceover controller toggles; build again.
5. **Error & Empty States + Final Cleanup**
   - Relocate error/empty views.
   - Audit `DiscoveriesHomeView` for leftover nested structs; remove or reference from new modules.
   - Run formatting/linting; update doc with final component map.
6. **Validation & Testing**
   - Perform manual QA across major flows.
   - Add TODO entries for snapshot/unit tests in newly created `Tests/` directories.

## Next Steps
- Review the detailed inventory and task breakdown for completeness.
- Resolve open questions (completion stage behavior, public access needs).
- Sequence tasks into review-sized PRs once approved.
