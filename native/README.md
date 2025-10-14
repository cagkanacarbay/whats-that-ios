# WhatsThatIOS - iOS App

A modern iOS application using a **workspace + SPM package** architecture for clean separation between app shell and feature code.

## AI Collaboration Guide

When pairing with AI coding assistants, start with the shared conventions captured in the repository root at `../AGENTS.md`. That document consolidates the architectural principles, coding standards, and workflow expectations for this workspace. Extend or customize it as needed for your team, but keep it as the single source of truth so every tool (Cursor, Codex, ChatGPT, etc.) follows the same guidance.

## Project Architecture

```
WhatsThatIOS/
├── WhatsThatIOS.xcworkspace/              # Open this file in Xcode
├── WhatsThatIOS.xcodeproj/                # App shell project
├── WhatsThatIOS/                          # App target (minimal)
│   ├── Assets.xcassets/                # App-level assets (icons, colors)
│   ├── WhatsThatIOSApp.swift              # App entry point
│   └── WhatsThatIOS.xctestplan            # Test configuration
├── WhatsThatIOSPackage/                   # 🚀 Primary development area
│   ├── Package.swift                      # Package configuration + dependency toggles
│   ├── Sources/
│   │   ├── WhatsThatApp/                  # Composition root & dependency container
│   │   ├── WhatsThatPresentation/         # SwiftUI views + view models
│   │   ├── WhatsThatDomain/               # Use cases, domain models, repository contracts
│   │   ├── WhatsThatData/                 # Repository implementations
│   │   ├── WhatsThatInfrastructure/       # Networking, persistence, external services
│   │   └── WhatsThatShared/               # Cross-cutting configuration/utilities
│   └── Tests/                             # XCTest targets mirrored per module
└── WhatsThatIOSUITests/                   # UI automation tests
```

## Key Architecture Points

### Workspace + SPM Structure
- **App Shell**: `WhatsThatIOS/` contains minimal app lifecycle code
- **Feature Code**: Modules under `WhatsThatIOSPackage/Sources/WhatsThat*/` house all presentation, domain, data, infrastructure, and shared code.
- **Separation**: Business logic lives in the SPM package; the app target imports `WhatsThatApp` for composition.

### Buildable Folders (Xcode 16)
- Files added to the filesystem automatically appear in Xcode
- No need to manually add files to project targets
- Reduces project file conflicts in teams

## Development Notes

### Code Organization
Most development happens inside the Swift Package modules (`Sources/WhatsThat*/`). Keep UIKit-only shims inside the app target.

### Public API Requirements
Types exposed to other modules or the app target need `public` access:
```swift
public struct NewView: View {
    public init() {}
    
    public var body: some View {
        // Your view code
    }
}
```

### Adding Dependencies
Edit `WhatsThatIOSPackage/Package.swift` to manage third-party dependencies. By default, the project ships with **stubbed dependencies disabled** to support offline development.

- Set `USE_REMOTE_DEPS=1` when invoking `swift build` / `xcodebuild` to resolve Supabase Swift, Google Sign-In, Nuke, MarkdownUI, and Apple collections packages (transitive requirements like AppAuth, swift-crypto, and swift-http-types will be fetched automatically).
- Keep the dependency mapping in sync with `docs/port/dependency-audit.md`.
- In sandboxed environments (CI, restricted shells), also set `SWIFT_MODULECACHE_PATH` and `CLANG_MODULE_CACHE_PATH` to a writable directory such as `.build/modulecache` before running package commands.

Example (simplified):
```swift
var infrastructureDependencies: [Target.Dependency] = ["WhatsThatShared"]
if useRemoteDependencies {
    infrastructureDependencies += [
        .product(name: "Supabase", package: "supabase-swift")
    ]
}
```

### Runtime Configuration
- `AppConfiguration` values are read from the app bundle via `AppConfiguration.fromBundle()`, which maps the xcconfig keys (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_CLIENT_ID`) into Info.plist entries.
- You can still override the configuration manually by passing a custom `AppConfiguration` into `AppRootView(configuration:)` (it will call `AppDependencyContainer.bootstrap(...)`).
- If configuration is incomplete or the remote packages are unavailable, the bootstrapper automatically falls back to `StubDiscoveryRepository` and other local stubs.
- Inject secrets through `.xcconfig` files or launch arguments; avoid hard-coding credentials in source.
- Populate the placeholders `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `GOOGLE_CLIENT_ID` in `Config/Shared.xcconfig` (and override in Debug/Release files as needed). Leave them blank to continue using stubbed services.
- Remember to build with `USE_REMOTE_DEPS=1` (e.g., by adding it to your Xcode scheme’s environment) whenever you want the Supabase/GoogleSignIn packages compiled into the binary.

### Test Structure
- **Unit Tests**: Module-specific folders under `WhatsThatIOSPackage/Tests/` (XCTest today)
- **UI Tests**: `WhatsThatIOSUITests/` (XCUITest framework)
- **Test Plan**: `WhatsThatIOS.xctestplan` coordinates all tests

## Configuration

### XCConfig Build Settings
Build settings are managed through **XCConfig files** in `Config/`:
- `Config/Shared.xcconfig` - Common settings (bundle ID, versions, deployment target)
- `Config/Debug.xcconfig` - Debug-specific settings  
- `Config/Release.xcconfig` - Release-specific settings
- `Config/Tests.xcconfig` - Test-specific settings

### Entitlements Management
App capabilities are managed through a **declarative entitlements file**:
- `Config/WhatsThatIOS.entitlements` - All app entitlements and capabilities
- AI agents can safely edit this XML file to add HealthKit, CloudKit, Push Notifications, etc.
- No need to modify complex Xcode project files

### Asset Management
- **App-Level Assets**: `WhatsThatIOS/Assets.xcassets/` (app icon, accent color)
- **Feature Assets**: Add `Resources/` folder to SPM package if needed

### SPM Package Resources
To include assets in a module (e.g., presentation layer):
```swift
.target(
    name: "WhatsThatPresentation",
    dependencies: [],
    resources: [.process("Resources")]
)
```

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted iOS development workflows.
