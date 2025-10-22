# What's That iOS Native Migration

This workspace captures the plan for rebuilding the existing **What's That** Expo/React Native app as a fully native iOS application.

## Documentation

All planning documents now live under `docs/port/`:

- `feature-inventory.md` – exhaustive sweep of shipping functionality in the current app (including discovery list/detail UI + animations).
- `data-integrations.md` – backend contracts, storage buckets, and third-party services.
- `ios-architecture-plan.md` – clean architecture blueprint, dependency stack, and latest package audit.
- `migration-roadmap.md` – phased delivery plan with milestones and dependencies.
- `simulator-and-testing-plan.md` – simulator workflow and test strategy with dependency validation.
- `risks-and-gaps.md` – answered questions, constraints, and decisions.
- `dependency-audit.md` – compatibility matrix for Swift packages/services we will adopt.
- `theme-system.md` – overview of the user-selectable light/dark appearance and integration guidelines.

## Presentation Module Layout
- `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/App` – root shell views and the `AppRootViewModel`.
- `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features` – feature-specific SwiftUI flows (Discovery Creation/Feed, Settings, Credits, Onboarding).
- `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Shared` – reusable brand components and controllers.
- `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Support` – shared exports or glue code for the presentation package.

## Build Commands
- `swift package resolve --package-path native/WhatsThatIOSPackage` – refresh Swift Package dependencies.
- `USE_REMOTE_DEPS=1 xcodebuild -workspace native/WhatsThatIOS.xcworkspace -scheme WhatsThatIOS -destination 'platform=iOS Simulator,name=iPhone 16' build`
- `USE_REMOTE_DEPS=1 xcodebuild test -workspace native/WhatsThatIOS.xcworkspace -scheme WhatsThatIOS -destination 'platform=iOS Simulator,name=iPhone 16' -testPlan WhatsThatIOS`

## High-Level Direction
1. **Preserve product behavior, not Expo implementation details.** All surfaces described in the docs must be functionally equivalent (or improved) on iOS.
2. **Adopt a modular clean architecture.** SwiftUI presentation, a domain/use-case layer, and actor-backed services keep the app testable and scalable.
3. **Integrate with existing Supabase + Edge Functions.** The iOS app will keep using the current Supabase schema, Edge functions (ask-ai-v7, nearby-places, validate-receipt, reset-password), storage buckets, and Google/OpenAI services.
4. **Build for testability and simulator-first development.** The native build must be fully operable inside Xcode’s iOS simulator with deterministic fixtures before running on devices.

## Next Steps
- Review each document for completeness.
- Align on any open questions captured in `docs/port/risks-and-gaps.md`.
- Approve the architecture and roadmap before opening the new Xcode project.

## Environment Configuration
- Copy `native/Config/Environments/Example.xcconfig` to `native/Config/Environments/Development.xcconfig` (or another name) and fill in your Supabase and Google credentials locally.
- `Environment.xcconfig` includes the example by default and optionally picks up any local file you create, so secrets stay out of source control.

## AI Collaboration
- `AGENTS.md` – shared guidelines for working with AI coding assistants (Cursor, Codex, ChatGPT, etc.) on this project.
