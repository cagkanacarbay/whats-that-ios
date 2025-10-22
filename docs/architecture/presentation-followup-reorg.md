# Presentation Module Follow-Up Reorg

## Context

- `Sources/WhatsThatPresentation` still contains root-level files (`MainTabView.swift`, `SettingsView.swift`, etc.) that predate the discovery refactor.
- Feature boundaries are inconsistent: some discovery views now live under `Features/`, while credits/settings/onboarding remain at the top level.
- Shared UI atoms (`BrandComponents.swift`) and controllers (`VoiceoverPlaybackController.swift`) would benefit from clear namespaces to guide future additions.

## Current Inventory (Post-Discovery Refactor)

| File                                              | Responsibility                                           | Notes                                                        |
| ------------------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------ |
| `AppRootViewModel.swift`                        | Resolves global app flow and auth/onboarding transitions | Domain-oriented, should live with other app-shell components |
| `MainTabView.swift`                             | Entry tab bar composition                                | References discovery creation/feed views                     |
| `RootContentView.swift`                         | Bootstraps app shell and binds environment objects       |                                                              |
| `OnboardingPermissionsCoordinator.swift`        | Orchestrates onboarding permissions flow                 | Could sit under an `Onboarding` feature                    |
| `SettingsView.swift`                            | Settings sheet (credits, appearance, sign out)           | Should be a dedicated feature                                |
| `CreditsView.swift`, `CreditsViewModel.swift` | Credits purchase/balance UI and logic                    | Feature-specific                                             |
| `BrandComponents.swift`                         | Buttons and branded controls                             | Belongs under shared components                              |
| `VoiceoverPlaybackController.swift`             | Global voiceover/narration controller                    | Shared service used by multiple features                     |
| `Features/DiscoveryCreation/*`                  | Discovery creation UI (already refactored)               |                                                              |
| `Features/DiscoveriesFeed/*`                    | Discoveries feed UI (already refactored)                 |                                                              |

## Proposed Folder Structure

```
Sources/WhatsThatPresentation/
├── App/
│   ├── RootContentView.swift
│   ├── MainTabView.swift
│   └── AppRootViewModel.swift
├── Features/
│   ├── DiscoveryCreation/            # existing
│   ├── DiscoveriesFeed/              # existing
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── SettingsViewModel.swift
│   │   └── SettingsRoutes.swift
│   ├── Credits/
│   │   ├── CreditsView.swift
│   │   └── CreditsViewModel.swift
│   └── Onboarding/
│       └── OnboardingPermissionsCoordinator.swift
├── Shared/
│   ├── Brand/
│   │   └── BrandComponents.swift
│   └── Controllers/
│       └── VoiceoverPlaybackController.swift
└── Support/
    └── PresentationExports.swift     # optional umbrella, placeholder for cross-module exports
```

_Rationale_:

- Separate app-shell concerns (`App/`) from feature-specific views.
- Group features for discoverability and future scaling.
- Centralize shared controls/services to avoid accidental duplication.

## Feature Module Conventions

- Adopt a feature-oriented MVVM-with-Coordinator pattern (Model from domain layer, dedicated View, ViewModel/Coordinator per feature).
- Each feature directory should contain clearly named subfolders (e.g., `Views`, `ViewModels`, `Coordinators`, `Components`) as the feature evolves.
- Shared code is limited to the `Shared/` namespace; features should not cross-reference each other directly—communicate via protocols or app-level routing.
- When adding new functionality, start inside the appropriate feature folder to keep responsibilities contained and discoverable.
- Build instructions: default to `swift build` (or `xcodebuild` when necessary) from repo root; avoid ad-hoc targets so the structure stays predictable.

## Detailed Relocation Plan

### 1. App Shell

- Move `AppRootViewModel.swift`, `MainTabView.swift`, and `RootContentView.swift` into `App/`.
- Update file headers or type access if needed (remain `public` where currently exposed).
- Ensure imports referencing these files (e.g., from `WhatsThatApp`) use new paths.

### 2. Settings & Credits

- Create `Features/Settings/` and move `SettingsView.swift` inside.
- Add `SettingsViewModel.swift` (or promote extracted logic) so the feature presents the standard View/ViewModel split.
- Move `CreditsView.swift` and `CreditsViewModel.swift` into `Features/Credits/`.
- Update `MainTabView` or other routers to reference new module paths.

### 3. Onboarding

- Move `OnboardingPermissionsCoordinator.swift` to `Features/Onboarding/`.
- If coordinator exposes public API used outside presentation, add documentation comment and ensure necessary `public` modifiers remain.

### 4. Shared Assets

- Create `Shared/Brand/` and move `BrandComponents.swift`.
- Create `Shared/Controllers/` and move `VoiceoverPlaybackController.swift`.
- Evaluate if any existing helper types (e.g., brand colors) should also relocate here in future passes.

### 5. Support (Optional)

- Introduce `Support/PresentationExports.swift` (empty placeholder) to collect typealiases or re-exports if multiple submodules need a single import point. Optional for now; note in TODO.

## Implementation Steps

_Every stage must compile via Xcode or `xcodebuild` before advancing. After each clean build, notify the user so they can perform an app-level visual check._

1. **Scaffold Folders**
   - Create `App/`, `Features/Settings`, `Features/Credits`, `Features/Onboarding`, `Shared/Brand`, `Shared/Controllers`.
   - Trigger the WhatsThatIOS build (`Cmd+B` or `xcodebuild`) to confirm the workspace still compiles.
2. **App Shell Move**
   - Relocate `AppRootViewModel.swift`, `MainTabView.swift`, `RootContentView.swift` into `App/`.
   - Update imports; rerun the WhatsThatIOS build.
3. **Settings & Credits Move**
   - Move `SettingsView.swift` into `Features/Settings/`; introduce `SettingsViewModel.swift` to encapsulate async logic.
   - Move `CreditsView.swift` and `CreditsViewModel.swift` into `Features/Credits/`.
   - Update references; rebuild with WhatsThatIOS.
4. **Onboarding Coordinator Move**
   - Move `OnboardingPermissionsCoordinator.swift` into `Features/Onboarding/`.
   - Adjust imports and rebuild WhatsThatIOS.
5. **Shared Assets Move**
   - Move `BrandComponents.swift` to `Shared/Brand/`.
   - Move `VoiceoverPlaybackController.swift` to `Shared/Controllers/`, retaining conformance to the feature-oriented controller pattern.
   - Update dependents; run the WhatsThatIOS build again.
6. **Documentation & README**
   - Update architectural docs and add a presentation section to the repo README summarizing feature folders and build conventions.
   - Final WhatsThatIOS build; notify user for visual verification.

## Decisions & Follow-Ups

- **Feature encapsulation**: All features must be self-contained using View + ViewModel (+ Coordinator when needed). Settings and Credits will follow this immediately; future work should not add presentation code outside feature folders.
- **Voiceover architecture**: `VoiceoverPlaybackController` stays under `Shared/Controllers` but will expose a controller interface compatible with the feature MVVM/MVC approach. Longer term, evaluate extracting persistence/audio concerns into infrastructure while keeping the presentation-facing controller here.
- **Documentation**: After moves complete, update the main README (or a dedicated architecture overview) to explain feature folders, build commands (`swift build` and `USE_REMOTE_DEPS=1 xcodebuild …`), and contribution guidelines.
