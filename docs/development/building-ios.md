# iOS Build & Verification Workflow
**Last Updated:** 2025-10-22

The native workspace targets iOS exclusively. Prefer Xcode-powered builds and tests so the exact toolchain, SDK, and simulator configuration used in production match local validation.

## Day-to-Day Development
- Open `native/WhatsThatIOS.xcworkspace` in Xcode and run the `WhatsThatIOS` scheme against the iPhone 15 simulator (or a device).
- Use `Product > Build` or `⌘B` frequently; Xcode caches incremental builds better than SwiftPM in this project.
- When iterating on UI, keep the simulator running and rely on hot reload/preview features instead of rebuilding from scratch.

## Command-Line Builds
Use the workspace-aware build so remote dependencies (Supabase, MarkdownUI, Nuke) resolve exactly like CI. Target the iPhone 16 simulator (the default device checked into CI and available locally):

```bash
USE_REMOTE_DEPS=1 xcodebuild \
  -workspace native/WhatsThatIOS.xcworkspace \
  -scheme WhatsThatIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

> **Tip:** Pipe the output to a log file when triaging failures so errors are easy to revisit without re-running the build:
> ```bash
> USE_REMOTE_DEPS=1 xcodebuild \
>   -workspace native/WhatsThatIOS.xcworkspace \
>   -scheme WhatsThatIOS \
>   -destination 'platform=iOS Simulator,name=iPhone 16' build \
>   | tee build.log
> ```

## Running Tests
Invoke the XCTest plan through `xcodebuild test` to execute unit + UI suites consistently:

```bash
USE_REMOTE_DEPS=1 xcodebuild test \
  -workspace native/WhatsThatIOS.xcworkspace \
  -scheme WhatsThatIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testPlan WhatsThatIOS
```

## Collecting & Fixing Build Errors
- Run the build command above once per change set. It requires CoreSimulator access, so elevated permissions may be needed in the CLI environment.
- Investigate failures directly in the logged output (or the `build.log` you captured). Re-run the build only after addressing the reported issues to avoid noisy, repetitive invocations.
- When you tee the build output to `build.log`, you can skim compiler diagnostics quickly with `rg -n "error:" build.log`, or broaden to `rg -n "warning:" build.log` when you need to audit warnings. This workflow keeps the live terminal output readable while giving you a searchable history of the failure.
- Example (current) failure: the workspace build halts in `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/DiscoveryDetailView.swift`. Fix the compile error there, then rerun the build command to confirm.
- If the build succeeds, optional smoke tests can run via the test command above or directly inside Xcode.

## Why Not `swift build`?
`swift build --package-path native/WhatsThatIOSPackage` attempts a host (macOS) build. Several dependencies require macOS 12/10.15 or newer, so the command fails even though the iOS targets are healthy. Skip `swift build` and rely on the Xcode commands above for accurate signal.
