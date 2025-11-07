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
│   ├── Assets.xcassets/                   # App-level assets (icons, colors)
│   ├── WhatsThatIOSApp.swift              # App entry point
│   └── WhatsThatIOS.xctestplan            # Test configuration
├── WhatsThatIOSPackage/                   # 🚀 Primary development area
│   ├── Package.swift                      # Package configuration + dependency toggles
│   ├── Sources/
│   │   ├── WhatsThatApp/                  # App entry + dependency injection
│   │   ├── WhatsThatPresentation/         # SwiftUI features (Views, ViewModels, Coordinators, Shared)
│   │   ├── WhatsThatDomain/               # Pure domain models, use cases, contracts
│   │   ├── WhatsThatData/                 # Repository implementations grouped by resource
│   │   ├── WhatsThatInfrastructure/       # Platform services, networking, encoding
│   │   └── WhatsThatShared/               # Branding, configuration, formatting, caching
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
Edit `WhatsThatIOSPackage/Package.swift` to manage third-party dependencies. Resolve them with the Xcode workspace build (no `swift build`, which targets macOS and fails on our deps):

```bash
USE_REMOTE_DEPS=1 xcodebuild \
  -workspace native/WhatsThatIOS.xcworkspace \
  -scheme WhatsThatIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

- Keep the dependency mapping in sync with `docs/port/dependency-audit.md`.
- In sandboxed environments (CI, restricted shells), set `SWIFT_MODULECACHE_PATH` and `CLANG_MODULE_CACHE_PATH` to a writable directory such as `.build/modulecache` before invoking `xcodebuild`.

### Runtime Configuration
- `AppConfiguration` values are read from the app bundle via `AppConfiguration.fromBundle()`, which maps the xcconfig keys (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_CLIENT_ID`) into Info.plist entries.
- You can still override the configuration manually by passing a custom `AppConfiguration` into `AppRootView(configuration:)` (it will call `AppDependencyContainer.bootstrap(...)`).
- The app now fails fast when configuration is missing; make sure Supabase and Google keys are present for development builds.
- Inject secrets through `.xcconfig` files or launch arguments; avoid hard-coding credentials in source.
- Populate the placeholders `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_CLIENT_ID`, and `GOOGLE_REVERSED_CLIENT_ID` in `Config/Shared.xcconfig` (and override in Debug/Release files as needed); missing values will cause the app to terminate during startup.
- Remember to build with `USE_REMOTE_DEPS=1` (e.g., scheme environment variable or command line) whenever you need Supabase/Google Sign-In packages compiled into the binary.

### Deep Linking
- The app registers a custom URL scheme `whatsthat://` (see `Config/AppInfo.plist`).
- Example website link to open the app: `<a href="whatsthat://open">Open in app</a>`.
- You can pass simple paths, e.g. `whatsthat://share/<uuid>`; the app will launch and receive the URL via `.onOpenURL`.
- Universal Links (`https://whats-that.app/...`) are also forwarded via `NSUserActivityTypeBrowsingWeb`.

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
- **Feature Assets**: Add `Resources/` folder to SPM targets as needed and declare them in `Package.swift`.

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted iOS development workflows.
