# WhatsThat iOS Codebase Structure

**Created:** 2025-02-14  
**Last Modified:** 2025-02-14  
**Version:** 0.1  

> **Keep this accurate:** This document must stay in lockstep with the repository. Whenever folders or files described here are added, removed, or renamed, update the tree, increment the version, and refresh the dates before merging. Reviewers should verify the “Last Modified” timestamp matches the most recent structural change.

## Package Tree (Authoritative Snapshot)

```
native/
├── WhatsThatIOS.xcworkspace
├── WhatsThatIOS.xcodeproj
├── WhatsThatIOS/ … (app bundle assets, Info.plist, LaunchScreen, etc.)
├── Config/ … (xcconfig environments)
└── WhatsThatIOSPackage/
    ├── Package.swift
    └── Sources/
        ├── WhatsThatApp/
        │   ├── AppEntry/
        │   │   └── AppRootView.swift
        │   └── DependencyInjection/
        │       ├── AppDependencyContainer.swift
        │       └── FeatureDependencyProviders/
        │           └── DiscoveryCreationDependencyProvider.swift
        ├── WhatsThatDomain/
        │   ├── README.md
        │   ├── Auth/
        │   │   ├── AuthModels.swift
        │   │   └── AuthUseCase.swift
        │   ├── Credits/
        │   │   ├── CreditModels.swift
        │   │   └── CreditBalanceStore.swift
        │   ├── Discovery/
        │   │   ├── DiscoveryModels.swift
        │   │   ├── DiscoveryCreationModels.swift
        │   │   ├── DiscoveryCreationProtocols.swift
        │   │   ├── DiscoveryContextBuilder.swift
        │   │   ├── DiscoveryImageProcessing.swift
        │   │   └── DiscoveryAnalysisParser.swift
        │   ├── Onboarding/
        │   │   └── OnboardingModels.swift
        │   └── AppFlow/
        │       └── AppFlowResolver.swift
        ├── WhatsThatData/
        │   ├── Repositories/
        │   │   ├── Discovery/
        │   │   │   ├── SupabaseDiscoveryRepository.swift
        │   │   │   └── StubDiscoveryRepository.swift
        │   │   ├── Voiceover/
        │   │   │   └── SupabaseVoiceoverRepository.swift
        │   │   ├── Credits/
        │   │   │   └── SupabaseCreditsRepository.swift
        │   │   └── Onboarding/
        │   │       └── UserDefaultsOnboardingRepository.swift
        │   ├── DTOs/
        │   │   └── README.md
        │   └── Mappers/
        │       └── README.md
        ├── WhatsThatInfrastructure/
        │   ├── Services/
        │   │   ├── Auth/
        │   │   │   ├── SupabaseAuthService.swift
        │   │   │   ├── SignInWithAppleService.swift
        │   │   │   └── GoogleSignInService.swift
        │   │   ├── Discovery/
        │   │   │   ├── CameraCaptureService.swift
        │   │   │   ├── PhotoLibrarySelectionService.swift
        │   │   │   └── DefaultDiscoveryImageEncoder.swift
        │   │   ├── Analysis/
        │   │   │   └── SupabaseDiscoveryAnalysisClient.swift
        │   │   ├── Credits/
        │   │   │   └── StoreKitCreditsStore.swift
        │   │   ├── Location/
        │   │   │   └── CoreLocationDiscoveryLocationService.swift
        │   │   └── Notifications/
        │   │       └── NativePushService.swift
        │   ├── Networking/
        │   │   ├── SupabaseClientFactory.swift
        │   │   └── StubNetworkClient.swift
        │   └── Configuration/
        │       └── (reserved for future infrastructure settings)
        ├── WhatsThatShared/
        │   ├── README.md
        │   ├── Branding/
        │   │   ├── BrandTheme.swift
        │   │   └── BrandMarkdownTheme.swift
        │   ├── Configuration/
        │   │   ├── AppConfiguration.swift
        │   │   └── AppConfiguration+Bundle.swift
        │   ├── Appearance/
        │   │   └── AppAppearance.swift
        │   ├── Caching/
        │   │   └── DiscoveryAssetCache.swift
        │   └── Formatting/
        │       └── DiscoveryStreamFormatter.swift
        └── WhatsThatPresentation/
            ├── App/
            │   ├── MainTabView.swift
            │   ├── RootContentView.swift
            │   └── AppRootViewModel.swift
            ├── Features/
            │   ├── DiscoveryCreation/
            │   │   ├── Flow/
            │   │   │   ├── DiscoveryCreationFlowView.swift
            │   │   │   └── DiscoveryCreationFlowViewModel.swift
            │   │   ├── Stages/
            │   │   ├── Common/
            │   │   └── Tests/
            │   ├── DiscoveriesFeed/
            │   │   ├── DiscoveriesHomeView.swift
            │   │   ├── Header/
            │   │   ├── Grid/
            │   │   ├── DetailOverlay/
            │   │   ├── Voiceover/
            │   │   ├── Errors/
            │   │   ├── Preferences/
            │   │   └── Utilities/
            │   ├── Settings/
            │   │   ├── SettingsView.swift
            │   │   ├── SettingsViewModel.swift
            │   │   └── SettingsRoutes.swift
            │   ├── Credits/
            │   │   ├── Views/
            │   │   └── ViewModels/
            │   └── Onboarding/
            │       └── Coordinators/
            ├── Shared/
            │   ├── Brand/
            │   │   └── BrandComponents.swift
            │   └── Controllers/
            │       └── VoiceoverPlaybackController.swift
            └── Support/
                └── PresentationExports.swift
```

_If you reorganize anything under `native/WhatsThatIOSPackage/Sources`, edit this tree immediately and bump the version._

## Layer Responsibilities & Best Practices

- **App (`WhatsThatApp/`)**

  - Purpose: SwiftUI entry point and dependency wiring.
  - Add new dependency factories under `DependencyInjection/FeatureDependencyProviders/`.
  - Keep app-coordinator logic (if introduced) in `Routing/` subfolders to avoid mixing with DI.
- **Domain (`WhatsThatDomain/`)**

  - Purpose: Pure business rules, independent of UI or platform.
  - Create subfolders per bounded context (Auth, Discovery, etc.).
  - Define protocols/interfaces here; implementation lives in Data/Infrastructure.
  - No UIKit/SwiftUI imports—stick to Foundation/Concurrency.
- **Data (`WhatsThatData/`)**

  - Purpose: Repository implementations bridging domain protocols and data sources.
  - Group repositories by resource under `Repositories/<ResourceName>/`.
  - Store API payloads in `DTOs/` and mapping helpers in `Mappers/`.
  - When adding a new repository, provide a stub/fake alongside the real implementation when possible.
- **Infrastructure (`WhatsThatInfrastructure/`)**

  - Purpose: Platform services, third-party SDK integrations, networking factories.
  - Organize under `Services/<Category>/` (Auth, Discovery, etc.).
  - Keep HTTP/client creation under `Networking/`.
  - Expose implementations that conform to domain protocols; avoid leaking UIKit/UI logic.
- **Shared (`WhatsThatShared/`)**

  - Purpose: Cross-cutting utilities with minimal dependencies.
  - Use existing categories (Branding, Configuration, Appearance, Caching, Formatting).
  - Ensure these types are presentation-agnostic; they may be consumed by multiple layers.
- **Presentation (`WhatsThatPresentation/`)**

  - Purpose: SwiftUI features following MVVM + Coordinator patterns.
  - Add new features under `Features/<FeatureName>/`, with subfolders for `Views`, `ViewModels`, `Coordinators`, `Components`, `Tests`.
  - Shared view utilities live under `Shared/`.
  - Do not inject infrastructure directly; rely on dependency providers via `WhatsThatApp`.

## Build Workflow Expectations

1. Always use `USE_REMOTE_DEPS=1 xcodebuild -workspace native/WhatsThatIOS.xcworkspace -scheme WhatsThatIOS -destination 'platform=iOS Simulator,name=iPhone 15' build` to validate structural work; skip `swift build` as it surfaces irrelevant macOS target errors.
2. Run the same Xcode build before PR submission or when touching shared configuration.
3. After refactors, request simulator smoke tests to ensure runtime behavior remains intact.

## Adding New Folders or Files

1. Identify the correct module using the responsibilities above.
2. Create the folder structure first, following `<Module>/<Category>/<Feature>/...` conventions.
3. Update this document’s tree immediately and bump **Version** / **Last Modified**.
4. Implement code, add tests in the matching `Tests/` target if applicable.
5. Re-run the Xcode build command (`USE_REMOTE_DEPS=1 xcodebuild …`) to confirm the workspace compiles, then notify reviewers for visual checks.
6. Reference this document in PR descriptions to highlight structural updates.

## Maintaining Structure Consistency

- Treat this file as code; structural PRs must include updates here.
- Reviewers should reject changes where the tree/version/dates aren’t updated.
- When conventions change (e.g., introducing a new shared category), explain the rationale in this document and increment the version.
