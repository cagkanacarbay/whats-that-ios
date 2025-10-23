# Implementation Status

This log mirrors the migration roadmap and supporting plan documents so we can track what has been implemented and what is still outstanding.

---

## Phase 1 – Foundation Setup (Migration Roadmap §Phase 1)
- ✅ Scaffolded the Xcode workspace + Swift package structure via `WhatsThatIOS.xcworkspace` and `WhatsThatIOSPackage` (see native project tree).
- ✅ Replaced the scaffold product `WhatsThatIOSFeature` with layered modules (`WhatsThatApp`, `WhatsThatPresentation`, `WhatsThatDomain`, `WhatsThatData`, `WhatsThatInfrastructure`, `WhatsThatShared`).
- ✅ Added automated unit test targets per module (currently smoke tests around discovery feed scaffolding).
- ⬜️ Remaining: split modules into Swift packages (if we pursue multi-package structure), add CI hooks, lint/format scripts.

## Phase 2 – Core Account & Onboarding Flows
- 🟡 In progress. `AppRootView` now gates between pre-onboarding slides, email/password auth, post-onboarding reminders, and the discovery feed. The pre/onboarding, sign up, log in, and forgot password screens mirror the React Native Tamagui styling (brand colors, logo, copy, social buttons). Supabase email/password auth is live, Google Sign-in runs through the native SDK + Supabase `signInWithIdToken` bridge, and Sign in with Apple is wired end-to-end via `AuthenticationServices`. Post-onboarding adds a permissions card so we can request location or push notifications without leaving the flow. We continue to use `UserDefaultsOnboardingRepository` for flags while onboarding polish proceeds. Added `BrandTheme` + SwiftUI brand components (primary/secondary/social buttons, floating text fields) and dropped shared assets (`BrandLogo`, onboarding illustrations, Google/Apple icons) so the native UI reuses the RN look-and-feel.
- ✅ Added a lightweight Settings sheet within the discoveries header menu so QA can reset onboarding flags (replaying the intro + permissions without reinstalling).
- ⬜️ Remaining: finish the Terms/Privacy Markdown modals + acceptance copy, hook up Supabase password reset deep links (`supabase.auth.setSession`), and tighten authentication error handling/accessibility so parity with the RN build is complete.

## Phase 3 – Discovery Consumption, Modal Voiceover & Quick Actions
- 🟡 In progress. Discovery home screen mirrors the Tamagui grid and now presents a native detail experience with a custom hero overlay – the discovery card animates smoothly into place using the measured card frame, cached image snapshot, and border-radius interpolation. Markdown rendering and the persistent voiceover player are functional, but the inline voiceover controls still need UX polish and the detail view is missing share/map/delete affordances.
- ⬜️ Remaining: add share + map routing and delete controls inside the detail sheet, rework the voiceover experience (correct transport controls, persistent state, global controls), and land the interactive drag dismissal parity with the React Native modal.
- 🛈 Descoped: “Take another photo” / “Upload a photo” quick action buttons will not be implemented on the native client.

## Phase 4 – Discovery Creation Pipeline & Streaming Polish
- ✅ Completed. Camera capture and photo upload flows share the new `DiscoveryCreationFlowViewModel` state machine, SSE streaming mirrors the RN experience (status events, token batches, cancellation), and Supabase analysis integration now hydrates the feed + cached assets once summaries arrive.

## Phase 5 – Monetization, Settings, & System Surfaces
- 🟡 In progress. Credits purchase UI, StoreKit 2 purchasing (`StoreKitCreditsStore`), Supabase receipt validation, and the in-app Credits screen are live; the Settings sheet exposes onboarding reset and appearance toggles.
- ⬜️ Remaining: implement restore purchases, low-credit alerts, additional settings/diagnostics surfaces, and the broader system overlays (updates screen, cache management).

## Phase 6 – Notifications, QA & Polish
- 🟡 In progress. Onboarding surfaces location/notification opt-ins and the creation pipeline requests notification permission via `NativePushService`.
- ⬜️ Remaining: wire APNs token registration to Supabase, decide on Expo vs APNs delivery, fill out analytics/logging, and stand up the QA automation harness (unit + UI).

## Phase 7 – Launch & Post-Launch
- ⬜️ Not applicable yet.

---

## Architecture Plan Alignment (ios-architecture-plan.md)
- ✅ **Shared Layer** – Introduced `AppConfiguration` + `AppConfiguration.fromBundle()` for runtime config; missing Supabase/Google keys now trigger a fail-fast precondition so dev environments surface configuration issues immediately.
- ✅ **Infrastructure Layer** – Added `SupabaseClientFactory` (guarded by `USE_REMOTE_DEPS`) and a `GoogleSignInService` wrapper (conditional build); retained only the lightweight Supabase transport stub for tests (auth now requires live services).
- ✅ **Data Layer** – Implemented `SupabaseDiscoveryRepository` using `supabase-swift`; retains `StubDiscoveryRepository` for offline/testing. Repository now returns Supabase metadata (image paths, share tokens, location), generates signed Supabase Storage URLs, and supports cursor-based pagination for the feed. Added `SupabaseVoiceoverRepository` for signed audio URL generation + metadata caching, mirroring the RN voiceover polling semantics.
- ✅ **Presentation Layer** – Root flow now uses `AppRootViewModel` to arbitrate onboarding/auth states before showing the discovery feed; authentication UI covers sign-in, sign-up, Google placeholder, and forgot-password messaging. Added brand-aware SwiftUI building blocks (`BrandTheme`, `BrandPrimaryButton`, social buttons, floating text fields) and RN-parity assets so onboarding/auth screens match Tamagui designs. Discovery feed has been rebuilt as the Tamagui two-column grid with skeletons, pull-to-refresh, and pagination, and the hero-style discovery transition is fully native: tapping a card animates a cached snapshot into `DiscoveryDetailView`, then reveals the gradient overlay, metadata stack, Markdown body, and voiceover playback (detail button + persistent mini player).
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
1. Phase 2: Deliver the Terms/Privacy Markdown modals, hook up Supabase password reset deep links, and address remaining authentication accessibility/error states.
2. Phase 3: Add share/map/delete actions to the discovery detail sheet, overhaul the voiceover controller UI/transport behaviour, and finish the interactive dismissal polish.
3. Phase 5 & 6: Ship restore purchases + credit alerts, then wire APNs token upload and outline the QA automation harness.

This document should be updated whenever a plan item is started or completed, so it remains a parallel source of truth with the roadmap and architecture plan.
