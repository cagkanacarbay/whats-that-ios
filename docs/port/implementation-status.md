# Implementation Status

This log mirrors the migration roadmap and supporting plan documents so we can track what has been implemented and what is still outstanding.

---

## Phase 1 – Foundation Setup (Migration Roadmap §Phase 1)
- ✅ Scaffolded the Xcode workspace + Swift package structure via `WhatsThatIOS.xcworkspace` and `WhatsThatIOSPackage` (see native project tree).
- ✅ Replaced the scaffold product `WhatsThatIOSFeature` with layered modules (`WhatsThatApp`, `WhatsThatPresentation`, `WhatsThatDomain`, `WhatsThatData`, `WhatsThatInfrastructure`, `WhatsThatShared`).
- ✅ Added automated unit test targets per module (currently smoke tests around discovery feed scaffolding).
- ⬜️ Remaining: split modules into Swift packages (if we pursue multi-package structure), add CI hooks, lint/format scripts.

## Phase 2 – Core Account & Onboarding Flows
- 🟡 In progress. `AppRootView` now gates between pre-onboarding slides, email/password auth, post-onboarding reminders, and the discovery feed. The pre/onboarding, sign up, log in, and forgot password screens mirror the React Native Tamagui styling (brand colors, logo, copy, social buttons). Supabase email/password auth is live and Google Sign-in now runs through the native SDK + Supabase `signInWithIdToken` bridge. Post-onboarding adds a permissions card so we can request location or push notifications without leaving the flow. We continue to use `UserDefaultsOnboardingRepository` for flags while onboarding polish proceeds. Added `BrandTheme` + SwiftUI brand components (primary/secondary/social buttons, floating text fields) and dropped shared assets (`BrandLogo`, onboarding illustrations, Google/Apple icons) so the native UI reuses the RN look-and-feel.
- ✅ Added a lightweight Settings sheet within the discoveries header menu so QA can reset onboarding flags (replaying the intro + permissions without reinstalling).
- ⬜️ Remaining: wire deep-link reset handling, finish Terms/Privacy copy, and implement Apple sign-in.

## Phase 3 – Discovery Consumption, Modal Animation & Voiceover
- 🟡 In progress. Discovery home screen now mirrors the Tamagui grid (two-column cards, skeletons, pull-to-refresh, paginated loading) with the new SwiftUI feed view and pagination logic.
- ⬜️ Remaining: discovery detail modal/voiceover modules, signed Supabase image delivery & matched-geometry transitions.

## Phase 4 – Discovery Creation Pipeline & Streaming Polish
- ⬜️ Not started. Camera/upload flows, SSE streaming, and shared state machine pending.

## Phase 5 – Monetization, Settings, & System Surfaces
- ⬜️ Not started. StoreKit and settings modules are placeholders only.

## Phase 6 – Notifications, QA & Polish
- ⬜️ Not started. No APNs integration or QA harness yet.

## Phase 7 – Launch & Post-Launch
- ⬜️ Not applicable yet.

---

## Architecture Plan Alignment (ios-architecture-plan.md)
- ✅ **Shared Layer** – Introduced `AppConfiguration` + `AppConfiguration.fromBundle()` for runtime config; missing Supabase/Google keys now trigger a fail-fast precondition so dev environments surface configuration issues immediately.
- ✅ **Infrastructure Layer** – Added `SupabaseClientFactory` (guarded by `USE_REMOTE_DEPS`) and a `GoogleSignInService` wrapper (conditional build); retained only the lightweight Supabase transport stub for tests (auth now requires live services).
- ✅ **Data Layer** – Implemented `SupabaseDiscoveryRepository` using `supabase-swift`; retains `StubDiscoveryRepository` for offline/testing. Repository now returns Supabase metadata (image paths, share tokens, location), generates signed Supabase Storage URLs, and supports cursor-based pagination for the feed.
- ✅ **Presentation Layer** – Root flow now uses `AppRootViewModel` to arbitrate onboarding/auth states before showing the discovery feed; authentication UI covers sign-in, sign-up, Google placeholder, and forgot-password messaging. Added brand-aware SwiftUI building blocks (`BrandTheme`, `BrandPrimaryButton`, social buttons, floating text fields) and RN-parity assets so onboarding/auth screens match Tamagui designs. Discovery feed has been rebuilt as the Tamagui two-column grid with skeletons, pull-to-refresh, and pagination (detail modal + matched geometry still TODO).
- ⚠️ **Coordinator / Navigation** – Root gating is live, but the planned tab bar + modal coordinator remain outstanding.

---

## Dependency & Environment Notes
- ✅ `USE_REMOTE_DEPS` toggles all third-party packages (Supabase Swift 2.34.0, GoogleSignIn 7.1.0, Nuke 12.8.0, MarkdownUI 2.4.1, etc.). Remote deps must remain enabled for the app to launch; `USE_REMOTE_DEPS=0` is now reserved for compilation-only experiments and will crash at runtime.
- ✅ `Config/AppInfo.plist` replaces the generated Info.plist so Supabase/Google keys travel with every build. The Supabase URL is split into `SUPABASE_URL_SCHEME` and `SUPABASE_URL_HOST_PATH` inside the environment configs (e.g., `Config/Environments/Development.xcconfig`) to avoid `//` commenting quirks during plist substitution.
- ⚠️ Build/Test commands (documented in README):
  - `SWIFT_MODULECACHE_PATH=.build/modulecache CLANG_MODULE_CACHE_PATH=.build/modulecache swift test`
  - `USE_REMOTE_DEPS=1 SWIFT_MODULECACHE_PATH=.build/modulecache CLANG_MODULE_CACHE_PATH=.build/modulecache swift test`
  - Simulator: ensure Supabase/Google env vars are set when launching via Xcode or MCP (not required when using the embedded xcconfig values).

---

## Next Suggested Steps
1. Phase 2: Add Google sign-in, password reset deep-link handling, and tighten copy/accessibility on onboarding screens.
2. Phase 3: Replace placeholder feed UI with the two-column grid + discovery modal plan, layering in caching/image loading via Nuke.
3. Expand automated tests to cover live repository mappings and auth edge cases (e.g., failed sign-in, onboarding persistence across launches).

This document should be updated whenever a plan item is started or completed, so it remains a parallel source of truth with the roadmap and architecture plan.
