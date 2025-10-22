# Core Module Refactor Plan
**Created:** 2025-02-14  
**Last Modified:** 2025-02-14  
**Version:** 1.0  

> **Keep in sync:** Whenever source files or folders under `Sources/WhatsThatApp`, `WhatsThatDomain`, `WhatsThatData`, `WhatsThatInfrastructure`, or `WhatsThatShared` change, update this plan, bump the version, and adjust dates. The document must always describe the current structure and the agreed plan forward.

## Current Module Snapshot

| Module | Key Files | Observations |
| --- | --- | --- |
| `WhatsThatApp` | `AppDependencyContainer.swift`, `DiscoveryCreationDependencyProvider.swift`, `AppRootView.swift` | No subfolders, mixes DI and root SwiftUI composition. |
| `WhatsThatDomain` | `AuthUseCase.swift`, `DiscoveryCreationProtocols.swift`, `DiscoveryModels.swift`, `CreditModels.swift`, `OnboardingModels.swift`, `DiscoveryAnalysisParser.swift`, `DiscoveryContextBuilder.swift`, `AuthModels.swift`, `DiscoveryImageProcessing.swift`, `AppFlowResolver.swift`, `DiscoveryVoiceoverModels.swift`, `DiscoveryCreationModels.swift`, `CreditBalanceStore.swift` | All domain logic sits flat; cross-concern types intermingle. |
| `WhatsThatData` | `SupabaseDiscoveryRepository.swift`, `SupabaseVoiceoverRepository.swift`, `SupabaseCreditsRepository.swift`, `StubDiscoveryRepository.swift`, `UserDefaultsOnboardingRepository.swift` | Mixes remote and local repositories; lacks DTO or API organization. |
| `WhatsThatInfrastructure` | `SupabaseClientFactory.swift`, `SupabaseDiscoveryAnalysisClient.swift`, `SupabaseAuthService.swift`, `StoreKitCreditsStore.swift`, `GoogleSignInService.swift`, `SignInWithAppleService.swift`, `CameraCaptureService.swift`, `PhotoLibrarySelectionService.swift`, `CoreLocationDiscoveryLocationService.swift`, `NativePushService.swift`, `DefaultDiscoveryImageEncoder.swift`, `StubNetworkClient.swift` | Platform services and third-party integrations coexist in a single folder. |
| `WhatsThatShared` | `BrandTheme.swift`, `BrandMarkdownTheme.swift`, `AppConfiguration.swift`, `AppConfiguration+Bundle.swift`, `AppAppearance.swift`, `DiscoveryAssetCache.swift`, `DiscoveryStreamFormatter.swift` | Shared utilities without categorization; configuration and UI theming live together. |

## Target Global Structure

```
Sources/
├── WhatsThatApp/
│   ├── AppEntry/
│   │   └── AppRootView.swift
│   ├── DependencyInjection/
│   │   ├── AppDependencyContainer.swift
│   │   └── FeatureDependencyProviders/
│   │       └── DiscoveryCreationDependencyProvider.swift
│   └── Routing/
│       └── AppNavigationCoordinator.swift   # potential future addition
├── WhatsThatDomain/
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
│   │   └── (future API models)
│   └── Mappers/
│       └── (future translation helpers)
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
│   │   ├── Location/
│   │   │   └── CoreLocationDiscoveryLocationService.swift
│   │   ├── Notifications/
│   │   │   └── NativePushService.swift
│   │   ├── Analysis/
│   │   │   └── SupabaseDiscoveryAnalysisClient.swift
│   │   └── Credits/
│   │       └── StoreKitCreditsStore.swift
│   ├── Networking/
│   │   ├── SupabaseClientFactory.swift
│   │   └── StubNetworkClient.swift
│   └── Configuration/
│       └── InfrastructureConfig.swift (future shared settings)
└── WhatsThatShared/
    ├── Branding/
    │   ├── BrandTheme.swift
    │   └── BrandMarkdownTheme.swift
    ├── Configuration/
    │   ├── AppConfiguration.swift
    │   └── AppConfiguration+Bundle.swift
    ├── Appearance/
    │   └── AppAppearance.swift
    ├── Caching/
    │   └── DiscoveryAssetCache.swift
    └── Formatting/
        └── DiscoveryStreamFormatter.swift
```

## Module-Specific Refactor Plans

### WhatsThatApp
- **Goals:** separate DI, app entry, and (future) routing; prepare for additional feature dependency providers.
- **Steps:**
  1. Create `AppEntry/` and move `AppRootView.swift`.
  2. Create `DependencyInjection/` and subfolder `FeatureDependencyProviders/` for `DiscoveryCreationDependencyProvider.swift`.
  3. Keep `AppDependencyContainer.swift` in `DependencyInjection/` root.
  4. After moves, run `swift build` and update import paths in `WhatsThatPresentation`.
- **Future Extensions:** add `AppNavigationCoordinator.swift` or similar once routing logic expands.

### WhatsThatDomain
- **Goals:** align with Clean Architecture boundaries (feature-oriented, pure Swift, platform-agnostic).
- **Steps:**
  1. Create subfolders (`Auth`, `Credits`, `Discovery`, `Onboarding`, `AppFlow`).
  2. Move files accordingly (e.g., `DiscoveryAnalysisParser.swift` → `Discovery/`).
  3. Ensure type visibility remains `public`/`internal` as required.
  4. Add `README` or `module.md` in the domain root describing that no UIKit/SwiftUI should appear here.
  5. `swift build` to validate.
- **Best Practices:** Keep protocols in domain; avoid importing infrastructure/data modules to maintain strict boundary.

### WhatsThatData
- **Goals:** group data access by resource (Discovery, Voiceover, etc.) and prepare for DTO/mapping layers.
- **Steps:**
  1. Create `Repositories/<Feature>` subfolders and move current repositories inside.
  2. Introduce empty `DTOs/` and `Mappers/` directories with placeholder README or TODO for future API contracts.
  3. After moving, adjust any `import` statements (mostly in DI) and run `swift build`.
- **Future Work:** Add unit tests that target repository logic; co-locate fixtures under a parallel `Tests` tree.

### WhatsThatInfrastructure
- **Goals:** categorize platform services by domain; make Supabase factory and stubs more discoverable.
- **Steps:**
  1. Create `Services/<Category>` directories (Auth, Discovery, Location, Notifications, Analysis, Credits).
  2. Relocate services accordingly; ensure `SupabaseDiscoveryAnalysisClient` sits under `Services/Analysis/`.
  3. Move `SupabaseClientFactory.swift` and `StubNetworkClient.swift` into `Networking/`.
  4. Consider a `Configuration/` folder if shared settings or environment adapters emerge.
  5. Run `swift build`.
- **Best Practices:** Infrastructure should depend on platform frameworks but expose protocol-conforming implementations back to domain/data.

### WhatsThatShared
- **Goals:** improve discoverability of shared utilities; ensure no feature-specific logic leaks in.
- **Steps:**
  1. Create higher-level categories (`Branding`, `Configuration`, `Appearance`, `Caching`, `Formatting`).
  2. Move existing files into appropriate folders.
  3. Add a brief README clarifying purpose of each category.
  4. Run `swift build`.
- **Future Considerations:** Evaluate moving long-term caches (e.g., `DiscoveryAssetCache`) into Infrastructure if networking storage grows complex.

## Implementation Checklist

_Every step requires a clean `swift build` (run via MCP) before proceeding. After a successful build, notify the user to run a simulator smoke test._

1. **Scaffold Directories** (no file moves yet).
2. **Refactor WhatsThatApp** (AppEntry/DependencyInjection); build.
3. **Refactor WhatsThatDomain** (new subfolders); build.
4. **Refactor WhatsThatData** (Repositories grouped); build.
5. **Refactor WhatsThatInfrastructure** (Services/Networking); build.
6. **Refactor WhatsThatShared** (Branding/Configuration/etc.); build.
7. **Documentation Updates** (update `file-structure.md`, this plan’s version, README pointers); final build.

## Contribution Guidelines After Refactor
- New domain logic must live under the relevant domain feature folder, accompanied by protocols where appropriate.
- Data-layer additions go into `Repositories` (or `DTOs/Mappers`) with clear naming (`<Resource><Repository/Mappers>.swift`).
- Infrastructure services should be categorized by capability; avoid dumping files at the root.
- Shared utilities must remain UI-agnostic and import-free from higher layers.
- Any structural change mandates updating this plan, `file-structure.md`, and passing `swift build` plus feature tests.
