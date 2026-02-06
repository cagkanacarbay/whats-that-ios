# Claude Code Project Configuration

## iOS Build & Test Commands

**NEVER use `swift test` or `swift build`** - they fail due to macOS version constraints. This is an iOS-only project.

### Building

```bash
USE_REMOTE_DEPS=1 xcodebuild \
  -workspace native/WhatsThatIOS.xcworkspace \
  -scheme WhatsThatIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

### Running Tests

```bash
USE_REMOTE_DEPS=1 xcodebuild test \
  -workspace native/WhatsThatIOS.xcworkspace \
  -scheme WhatsThatIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testPlan WhatsThatIOS
```

### Running Specific Tests

```bash
USE_REMOTE_DEPS=1 xcodebuild test \
  -workspace native/WhatsThatIOS.xcworkspace \
  -scheme WhatsThatIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:WhatsThatDomainTests/VersionComparisonTests
```

### Simulator Note

If tests fail with "simulator runtime is not available", download the required iOS runtime from Xcode Settings > Components, or run tests directly from Xcode where you can select an available simulator.

### Capturing Build Logs

Pipe output to a log file for easier error analysis:

```bash
USE_REMOTE_DEPS=1 xcodebuild ... | tee build.log
# Then search for errors:
rg -n "error:" build.log
```

## Project Structure

- `native/WhatsThatIOS.xcworkspace` - Main Xcode workspace
- `native/WhatsThatIOSPackage/` - Swift Package with all modules
- `docs/` - Development documentation

## Key Documentation

- `docs/development/building-ios.md` - Full build workflow details
- `docs/production-management/build-and-deploy.md` - Environment configuration and deployment
- `docs/development/database-development-patterns.md` - **Read when developing database functions or Supabase RPC features** to follow established conventions

## Database Migrations

**NEVER run migrations directly** - Claude writes migration files to `supabase/migrations/`, and the user runs them manually. Use the MCP tools only to query/read data, not to execute DDL or DML.
