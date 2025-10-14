# Repository Guidelines

## Project Structure & Module Organization
- Core workspace lives under `native/`; open `native/WhatsThatIOS.xcworkspace` in Xcode.
- Application shell files sit in `native/WhatsThatIOS/` (entry point, assets, test plan).
- Feature code, domain logic, and services belong in the Swift package at `native/WhatsThatIOSPackage/Sources/WhatsThat*/`.
- Unit tests mirror the module layout inside `native/WhatsThatIOSPackage/Tests/`; UI automation lives in `native/WhatsThatIOSUITests/`.
- Shared build settings and entitlements are stored in `native/Config/`.

## Build, Test, and Development Commands
- `open native/WhatsThatIOS.xcworkspace` – launch the workspace in Xcode.
- `USE_REMOTE_DEPS=1 xcodebuild -workspace native/WhatsThatIOS.xcworkspace -scheme WhatsThatIOS -destination 'platform=iOS Simulator,name=iPhone 15' build` – validate that the app compiles with remote packages enabled.
- `USE_REMOTE_DEPS=1 xcodebuild test -workspace native/WhatsThatIOS.xcworkspace -scheme WhatsThatIOS -destination 'platform=iOS Simulator,name=iPhone 15' -testPlan WhatsThatIOS` – run the full XCTest plan.
- `swift package resolve --package-path native/WhatsThatIOSPackage` – refresh SPM dependencies when editing `Package.swift`.

## Coding Style & Naming Conventions
- Target Swift 5.10, SwiftUI-first presentation, and structured concurrency. Default to 4-space indentation and 120-character lines.
- Use `UpperCamelCase` for types, `lowerCamelCase` for methods/properties, and `SCREAMING_SNAKE_CASE` for xcconfig keys.
- Prefer `final` classes, protocol-oriented abstractions, and async/await over completion handlers.
- Run the toolchain `swift-format` (matching the config planned in `docs/port/ios-architecture-plan.md`) and keep SwiftLint violations at zero once the config is committed.

## Testing Guidelines
- Write XCTests colocated with the module under test (e.g., `WhatsThatDomainTests`). Name files `<Feature>Tests.swift`.
- Update `native/WhatsThatIOS.xctestplan` when adding or disabling suites so CI picks them up.
- Cover new domain use cases, service adapters, and SwiftUI view models; include stubbed data fixtures when remote dependencies are unavailable.
- Snapshot or UI flows belong in `native/WhatsThatIOSUITests/` using XCUITest.

## Commit & Pull Request Guidelines
- The repository has no commit history yet; adopt Conventional Commits (`feat:`, `fix:`, `chore:`) to keep history searchable.
- Keep commits focused, referencing modules touched (e.g., `feat(domain): add search use case`).
- Pull requests should describe the change, list impacted modules, attach simulator screenshots for UI updates, and link any planning docs or issues.
- Confirm builds and full test plans pass locally before requesting review; note any deviations explicitly.

## Configuration & Secrets
- Copy `native/Config/Environments/Example.xcconfig` to a local file (e.g., `Development.xcconfig`) and provide Supabase and Google keys.
- Never commit secrets; rely on xcconfig overrides and launch arguments to inject environment-specific values.
