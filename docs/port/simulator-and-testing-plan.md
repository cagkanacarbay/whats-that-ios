# Simulator & Testing Plan

This guide explains how we will bootstrap, exercise, and validate the native iOS implementation using Xcode’s simulator and automated tests.

---

## Simulator Readiness Checklist
- **Xcode Configuration**
  - Install latest Xcode (≥ 15.4) with iOS 17 simulator runtimes.
  - Create `WhatsThatIOS.xcodeproj` with Debug scheme targeting iPhone 15 (primary) and iPad (sanity).
  - Set up signing identities for development builds (can use personal team for simulator).
- **Environment Injection**
  - Manage secrets via the XCConfig environment switcher:
    - `Config/Environment.xcconfig` selects the active environment include.
    - `Config/Environments/Development.xcconfig` is the in-repo dev profile (safe to duplicate for staging/production).
    - For private overrides, copy the dev profile to `Config/Environments/Development.local.xcconfig` (gitignored) and then update `Environment.xcconfig` to include that file instead. Include both `GOOGLE_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID` so the Google Sign-In URL scheme resolves correctly on simulator.
  - Provide sample `Supabase.test.json` for unit tests (mocked responses).
  - Gate secrets to fall back to mock data when absent (e.g., `Configuration.hasLiveServices`).
- **Assets & Fixtures**
  - Bundle sample photos (`Fixtures/Images`) for simulator capture fallback.
  - Include canned SSE transcripts, discovery lists, and voiceover files for offline UI previews.

---

## Handling Service Constraints in Simulator
- **Camera:** If simulator camera unavailable, offer “Use Sample Photo” option that loads fixture from bundle while preserving full flow (image resizing, AI call).
- **Photo Library:** Use `PHPickerViewController` on simulator to select from fixtures folder.
- **Location:** Provide toggle for “Simulate Current Location” (Xcode allows GPX traces). Location service should fall back to default coordinates when simulator denies permission.
- **Push Notifications:** Simulator does not receive APNs tokens. For testing:
  - Implement mock token provider returning sentinel value (e.g., `"SIMULATOR_TOKEN"`).
  - Skip backend registration in Debug builds when token is sentinel; surface banner indicating notifications disabled.
  - Provide manual trigger to simulate “discovery complete” notification for UI testing.
- **IAP:** StoreKit 2 supports simulator via StoreKit Testing in Xcode. Create `.storekit` configuration mirroring live product IDs and attach to scheme.
- **Audio Playback:** Use bundled `.wav` fixtures to test playback; ensure AVAudioSession configured for simulator.
- **Expo Push Compatibility:** While production uses Expo push, simulator-focused runs can mock success responses when calling Supabase functions.

---

## Automated Testing Strategy
- **Unit Tests**
  - Validate use cases (auth, discovery creation, credits) with mocked repositories (use `AsyncStream` test helpers).
  - Test SSE parser with fixture streams (cover status/token/complete/error sequences).
  - Ensure voiceover scheduling logic mirrors backoff rules (legacy ID guard, max attempts).
- **Integration Tests**
  - Use Supabase test project or WireMock-style local server to simulate Edge Functions (ask-ai, validate-receipt).
  - Exercise StoreKit `.storekit` file for purchase and restore flows.
  - Validate image cache writes/reads on disk (sanitized sandbox directories).
- **UI Tests (XCTest / XCUITest)**
  - Cover primary flows: onboarding, login, capture (fixture), confirm, streaming preview, discovery detail, audio playback, purchase credits.
  - Use accessibility identifiers rather than text to avoid localization brittleness.
  - Inject deterministic data via launch arguments (e.g., `--useMockServices true`, `--mockDiscoveryCount 20`).
- **Snapshot Tests**
  - Optional: capture key screens for visual regression (dark/light mode, large text).

---

## Manual QA Playbook
- **Core Scenarios**
  - New user sign-up, onboarding, sample photo analysis, discovery detail playback.
  - Insufficient credits → purchase → retry analysis.
  - Location denied vs granted; confirm map/open-in-Maps behavior.
  - Voiceover missing (legacy ID) fallback message.
  - Delete discovery from modal and ensure list updates.
  - Password reset deep link handling (using simulator Safari + universal link test server).
- **Edge Cases**
  - SSE cancellation mid-stream (kill app) → ensure background polling / completion handling matches expectations.
  - Credit refund when `ask-ai` returns error (simulate via mock function).
  - StoreKit interrupted transaction recovery on next launch.
  - Audio playback restore after app restart (position remembered).
  - Theme toggle persistence; onboarding reset clearing flags.

---

## Tooling & CI Considerations
- Integrate with Xcode Cloud or existing CI to run unit/UI tests on simulator (headless).
- Use fastlane lanes for building, testing, and distributing TestFlight builds.
- Provide script to seed Supabase test data (`scripts/seed-test-discoveries.ts` equivalent) for consistent QA baseline.
- Collect simulator logs (`os_log`, network traces) for debugging SSE or StoreKit issues.

---

## Dependency Validation Workflow
- **SPM lockfile audits:** Once we’re on a networked machine, run `swift package update --dry-run` weekly to detect upstream releases of `supabase-swift`, `Nuke`, `MarkdownUI`, `GoogleSignIn`, and other pinned packages. Record output in `dependency-audit.md`.
- **Compatibility smoke tests:** Maintain a lightweight test target that links all third-party frameworks and exercises critical paths (Supabase auth, signed URL fetch, StoreKit purchase, Markdown rendering, Nuke image load). Run it on both Debug and Release simulator builds to catch linker or concurrency regressions early.
- **Supabase contract checks:** Use a staging environment to validate that the confirmed versions of `supabase-swift` still handle OTP/password reset flows, Storage signed URLs, and edge function invocations. Add regression tests around `grant_initial_credits`, `validate-receipt`, and `ask-ai-v7` invocation payloads.
- **Automated linting:** After the packages are resolved, run `swift format --lint` (Swift 5.10) and `swiftlint` (latest confirmed version) on CI to ensure package updates don’t introduce warnings that block builds.
- **Pre-release verification:** Before cutting a TestFlight build, re-run the package audit and simulator smoke suite on the exact Xcode version we intend to ship, ensuring no last-minute toolchain drift.

---

## Auth Troubleshooting Log
- **Date:** 2024-10-14  
- **Symptom:** Email/password sign-in always surfaced “We couldn't sign you in…” even with known-good Supabase credentials. Auth flow never advanced beyond the login screen.
- **Root Cause:** The generated Info.plist omitted the Supabase URL, anon key, and Google client ID because `GENERATE_INFOPLIST_FILE=YES` strips values containing `://`. `AppConfiguration.fromBundle()` therefore returned the `.preview` fallback, forcing `AppDependencyContainer.bootstrap` to instantiate `StubAuthService`.
- **Fix Implemented:**  
  1. Added a dedicated plist (`Config/AppInfo.plist`) that references the xcconfig-supplied `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `GOOGLE_CLIENT_ID`.  
  2. Split the Supabase URL into `SUPABASE_URL_SCHEME` + `SUPABASE_URL_HOST_PATH` inside the environment config (`Config/Environments/Development.xcconfig`) so build setting parsing no longer treats `//` as a comment.  
  3. Updated `Package.swift` so remote dependencies (Supabase, Google Sign-In, Nuke, etc.) are enabled by default; set `USE_REMOTE_DEPS=0` only when explicitly opting into stubbed builds.
- **Verification:** After the change, the simulator build authenticates successfully against Supabase, transitions through onboarding, and surfaces live auth session state. Keep these steps on hand if the issue reappears (e.g., when rotating xcconfig secrets or regenerating build settings).

---

## Verification of AI Pipeline
- Create mock `ask-ai-v7` server returning deterministic SSE transcript for unit/UI tests.
- In staging, connect to real Supabase Edge function using sample OpenAI key; verify:
  - Credit deduction and refund semantics.
  - Image uploaded to `discovery_images` bucket.
  - Discovery appears in list with metadata populated.
  - Push notification logs (where applicable).

---

## Release Readiness Checklist
- Automated tests green (unit, integration, UI).
- Manual QA checklist signed off.
- Performance profiling on simulator and physical device (once available) shows acceptable memory/CPU usage during scrolling and streaming (address prior Expo issues).
- Accessibility audit completed (VoiceOver, Dynamic Type).
- Crash/analytics tooling integrated (e.g., Sentry or Firebase, if desired).

Following this plan keeps the native project continuously verifiable, minimizes regressions, and ensures a smooth path to TestFlight and production.
