# Claude Code Project Configuration

**What's That?** is an iOS app that lets users photograph objects to get AI-generated audio guides about them. It uses Supabase for backend services and StoreKit for in-app purchases.

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

### Capturing Build Logs

```bash
USE_REMOTE_DEPS=1 xcodebuild ... | tee build.log
# Then search for errors:
rg -n "error:" build.log
```

### Simulator Note

If tests fail with "simulator runtime is not available", download the required iOS runtime from Xcode Settings > Components.

---

## Project Structure

### Root Layout

```
native/                          # iOS app (Xcode workspace + Swift Package)
supabase/                        # Backend (Edge Functions + migrations)
docs/                            # All project documentation
```

### iOS Codebase (`native/WhatsThatIOSPackage/Sources/`)

| Module | Purpose |
|--------|---------|
| `WhatsThatApp/` | SwiftUI entry point, dependency injection (`AppDependencyContainer`, `FeatureDependencyProviders/`) |
| `WhatsThatDomain/` | Pure business rules, protocols. No UIKit/SwiftUI. Subfolders: Auth, Credits, Discovery, Onboarding, AppFlow |
| `WhatsThatData/` | Repository implementations (Supabase repos, DTOs, Mappers). Bridges domain protocols to data sources |
| `WhatsThatInfrastructure/` | Platform services + SDK integrations: Auth, Camera, StoreKit, Location, Push Notifications, Networking |
| `WhatsThatPresentation/` | SwiftUI features (MVVM + Coordinator). All UI lives here |
| `WhatsThatShared/` | Cross-cutting: BrandTheme, AppConfiguration, Caching, Formatting |

### Presentation Layer Key Files

| File | Role |
|------|------|
| `App/RootContentView.swift` | App flow: preOnboarding → auth → postOnboarding → MainTabView |
| `App/MainTabView.swift` | 4 tabs (Camera, Discoveries, Audio Guides, Gallery) - pure routing + overlays |
| `App/CreationFlowCoordinator.swift` | Owns VMs, modal state, discovery completion tracking |
| `DiscoveryCreationFlowViewModel.swift` | Slim VM delegating to 3 coordinators (PhotoCapture, StreamingSession, ConfirmationState) |
| `Shared/Services/DiscoverySessionManager.swift` | Singleton handling up to 3 concurrent background discovery sessions |

### Supabase Backend (`supabase/`)

| Path | Purpose |
|------|---------|
| `supabase/functions/ask-ai-v7/` | Main AI analysis edge function (streaming discovery generation) |
| `supabase/functions/generate-voiceover/` | Fish Audio TTS voiceover generation |
| `supabase/functions/validate-receipt/` | StoreKit receipt validation for IAP |
| `supabase/functions/nearby-places/` | Google Places API proxy |
| `supabase/functions/shared-discovery/` | Public share page endpoint (no JWT) |
| `supabase/functions/delete-account/` | GDPR account deletion |
| `supabase/functions/export-discoveries/` | User data export |
| `supabase/functions/_shared/` | Shared utilities across edge functions |
| `supabase/migrations/` | Database migrations (timestamp format: `YYYYMMDDHHMMSS_description.sql`) |

---

## Documentation

**Always check `docs/` before starting work on a feature or system.**

### Feature Development (`docs/development/features/`)

This is how we plan and build features. Each feature gets its own numbered folder (e.g., `08-onboarding-revamp/`, `10-creation-flow-architecture-redesign/`). Inside, we create documents for requirements, design specs, implementation plans, bug investigations, and testing checklists. Everything for a feature is self-contained in its folder.

**Workflow:** Create a new numbered folder → plan the feature with docs inside it → implement from those plans.

**Before working on an area of the app, read the relevant feature folder first** — it contains the decisions, constraints, and bug history you need.

### Development References

| Document | When to Read |
|----------|-------------|
| `docs/development/building-ios.md` | Full build workflow details |
| `docs/development/database-development-patterns.md` | **Read when developing database functions or Supabase RPC features** — covers `RETURNS TABLE` vs `RETURNS JSON`, timestamp handling, Swift `JSONObject` decode pattern |

### Production & Deployment

| Document | When to Read |
|----------|-------------|
| `docs/production-management/build-and-deploy.md` | Environment configuration (XCConfig), remote deps toggle, deployment notes, migration conventions |
| `docs/production-management/version-releases.md` | **Read before any release.** Version log system, soft/force updates, legal updates, release timing & sequencing. Use `/release-update` and `/legal-update` skills |
| `docs/production-ready/environments.md` | Dev vs Prod environment config: API keys, CORS, edge function secrets, web share setup |

### Security

| Document | When to Read |
|----------|-------------|
| `docs/security/supabase-security-audit.md` | RLS policies, function security (`SECURITY DEFINER`, pinned `search_path`), GDPR readiness |

### AI System Prompt

The active AI system prompt lives at `supabase/functions/ask-ai-v7/prompts/system-prompt.ts`. **Read this before modifying discovery generation behavior.**

### Legal Documents

| Document | Purpose |
|----------|---------|
| `docs/legal/PRIVACY_POLICY.md` | Current privacy policy |
| `docs/legal/TERMS_AND_CONDITIONS.md` | Current terms of service |

**When planning a new feature, consider whether it requires updates to the Privacy Policy or Terms of Service** (e.g., new data collection, third-party integrations, permission usage). Flag this during feature planning so legal docs stay current.

---

## Database Conventions

**NEVER run migrations directly.** Write migration files to `supabase/migrations/` and the user runs them manually. Use MCP tools only to query/read data, not to execute DDL or DML.

### Key Patterns (from `docs/development/database-development-patterns.md`)

- **RPC functions**: Use `RETURNS TABLE` for timestamps (not `RETURNS JSON`) — PostgREST auto-serializes `timestamptz` as ISO8601
- **Swift decoding**: When structs have `Date` fields, use `JSONObject` + `jsonArray.decode()` pattern (not direct `.execute().value`)
- **Migration naming**: `YYYYMMDDHHMMSS_description.sql` — use `supabase migration new` to auto-generate timestamps

### Supabase Environments

| Environment | Project ID | Use |
|-------------|------------|-----|
| Development | `cywshvmspnvimucwqarc` | Testing |
| Production | `vipghlhvnrdheoydynty` | Live users |

---

## App Architecture Quick Reference

- **App flow**: RootContentView → preOnboarding → authentication → postOnboarding → MainTabView
- **AppFlowResolver** determines state from `OnboardingFlags` + `AuthSession`
- **Intro Mode**: First 3 free discoveries, audio locked ON, credits exhausted triggers conversion
- **Conditional Permissions**: Camera on first use, Location on 2nd camera, Notifications after purchase
- **Discovery Creation**: Camera/Gallery tabs are pure triggers → fullScreenCover modal → DiscoveryCreationFlowView
- **DiscoverySessionManager**: Handles up to 3 concurrent background sessions with queuing; completed items linger 2.5s then fade
- **IPOP**: Content preference system (Ideas, People, Objects, Physical) that customizes AI-generated descriptions

---

## Available Claude Skills

| Skill | Purpose |
|-------|---------|
| `/release-update` | Create a migration for app version releases |
| `/legal-update` | Create a migration for ToS or Privacy Policy updates |
| `/commit` | Commit changes |
