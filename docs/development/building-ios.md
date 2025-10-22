# iOS Build & Verification Workflow
**Last Updated:** 2025-10-22

The native workspace targets iOS exclusively. Prefer Xcode-powered builds and tests so the exact toolchain, SDK, and simulator configuration used in production match local validation.

## Day-to-Day Development
- Open `native/WhatsThatIOS.xcworkspace` in Xcode and run the `WhatsThatIOS` scheme against the iPhone 15 simulator (or a device).
- Use `Product > Build` or `⌘B` frequently; Xcode caches incremental builds better than SwiftPM in this project.
- When iterating on UI, keep the simulator running and rely on hot reload/preview features instead of rebuilding from scratch.

## Command-Line Builds
Use the workspace-aware build so remote dependencies (Supabase, MarkdownUI, Nuke) resolve exactly like CI:

```bash
USE_REMOTE_DEPS=1 xcodebuild \
  -workspace native/WhatsThatIOS.xcworkspace \
  -scheme WhatsThatIOS \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
```

## Running Tests
Invoke the XCTest plan through `xcodebuild test` to execute unit + UI suites consistently:

```bash
USE_REMOTE_DEPS=1 xcodebuild test \
  -workspace native/WhatsThatIOS.xcworkspace \
  -scheme WhatsThatIOS \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -testPlan WhatsThatIOS
```

## Why Not `swift build`?
`swift build --package-path native/WhatsThatIOSPackage` attempts a host (macOS) build. Several dependencies require macOS 12/10.15 or newer, so the command fails even though the iOS targets are healthy. Skip `swift build` and rely on the Xcode commands above for accurate signal.
