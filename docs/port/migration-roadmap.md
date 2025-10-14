# Migration Roadmap

The following phased plan guides delivery of the native iOS application from project kickoff through release. Each phase lists its primary objectives, key tasks, dependencies, and exit criteria.

---

## Phase 0 – Alignment & Backlog Curation (Complete)
- **Objectives:** Inventory existing functionality, integrations, and known issues (captured in `feature-inventory.md`, `data-integrations.md`, `risks-and-gaps.md`).
- **Deliverables:** Approved architecture plan, roadmap, and simulator strategy.
- **Exit Criteria:** Stakeholders sign off on scope and sequencing; engineering has clarified open questions.

---

## Phase 1 – Foundation Setup
- **Objectives:**
  - Create Xcode project (`What's That iOS`) with SwiftUI + modular structure.
  - Configure shared packages (Supabase Swift, StoreKit helper, Markdown renderer).
  - Implement configuration loader (`Configuration` struct reading xcconfigs).
  - Build scaffolding for dependency injection (e.g., protocol registries or lightweight service locator).
- **Dependencies:** Architecture approval; Supabase project credentials; Apple developer account access.
- **Exit Criteria:** App launches to placeholder screen; environment config validated (Supabase ping, feature flags).

---

## Phase 2 – Core Account & Onboarding Flows
- **Objectives:**
  - Implement onboarding flows (pre/post) with persistence.
  - Integrate Supabase Auth (email/password, Google sign-in if possible, password reset deep links).
  - Establish session management, root navigation guard, global providers.
- **Key Tasks:** UI build, session observer actor, deep-link handling, Terms/Privacy Markdown rendering.
- **Exit Criteria:** User can create an account, login, logout, and progress through onboarding in simulator.

---

## Phase 3 – Discovery Consumption, Modal Animation & Voiceover
- **Objectives:**
  - Recreate the discoveries grid UI exactly (two-column layout, floating header, skeletons) and ensure scrolling/refresh behavior matches the React Native build.
  - Implement the matched-geometry modal transition, including edge-swipe dismissal, gradient overlay, and detail sheet styling described in `feature-inventory.md`.
  - Wire voiceover playback (local + global players) and ensure cached assets hydrate seamlessly for the seeded test account.
- **Key Tasks:** Discovery repository actor, image cache manager, SwiftUI grid + sticky header, modal coordinator with custom transitions (UIKit bridge), VoiceoverRepository + AVAudioPlayer integration, playback persistence.
- **Dependencies:** Availability of seeded Supabase test user with discovery history; design reference assets (screenshots/gifs) for pixel parity.
- **Exit Criteria:** In simulator, test user can browse existing discoveries with smooth animations, open/close detail modal flawlessly, and play narration with persistent audio controls.

---

## Phase 4 – Discovery Creation Pipeline & Streaming Polish
- **Objectives:**
  - Build camera and photo upload flows with shared state machine.
  - Hook CoreLocation service and Google Places Edge Function.
  - Implement confirmation screen (credit check, custom context assembly, push registration).
  - Integrate SSE streaming client for `ask-ai-v7`, mirroring smooth token-by-token updates and transition into the modal experience without jank.
- **Key Tasks:** Camera preview controller, EXIF extraction, image processing actor, SSE parser, ask-ai session actor with cancellation/refund handling, confirm screen UI parity.
- **Dependencies:** StoreKit groundwork for credit checks; push notification entitlements (even if simulator stubbed); Phase 3 modal already complete for handoff.
- **Exit Criteria:** Using simulator photos, user can generate a new discovery end-to-end (image uploaded, AI completes with streaming UI, discovery inserted, modal opens via same animation sequence).

---

## Phase 5 – Monetization, Settings, & System Surfaces
- **Objectives:**
  - Integrate StoreKit 2 purchase flow, Supabase receipt validation, credit balance syncing.
  - Build purchase screen UI, low-credit alerts, and (new) restore purchases flow.
  - Port settings screen (theme toggle, onboarding reset, cache clearing, debug links).
  - Wire update check screen (using `Updates` equivalent or planned native mechanism).
- **Dependencies:** Apple in-app purchase test accounts, product metadata alignment with Supabase `_shared/Products.ts`.
- **Exit Criteria:** Credits can be purchased/consumed/restored in sandbox; settings controls operate as expected.

---

## Phase 6 – Notifications, QA & Polish
- **Objectives:**
  - Replace Expo push with APNs token registration; coordinate with backend for dual delivery (Expo + APNs) or maintain Expo path (documented decision).
  - Implement analytics/logging (if required).
  - Conduct accessibility review and performance tuning (image preloading efficiency, memory footprint).
  - Build automated tests: unit (use cases), integration (repositories), UI (XCTest / snapshot).
  - Update documentation, onboarding guides, and ops runbooks.
- **Exit Criteria:** Full regression suite passing; manual QA sign-off; TestFlight build ready with release notes.

---

## Phase 7 – Launch & Post-Launch Follow-Up
- **Objectives:** Release to App Store/TestFlight, monitor crash logs, gather feedback, address launch bugs, and plan backlog items (e.g., feedback persistence, map view, Android parity).
- **Exit Criteria:** Stable production metrics, backlog reprioritized for post-launch enhancements.

---

## Cross-Cutting Dependencies & Considerations
- **Backend:** Ensure Supabase functions remain compatible; coordinate if APNs support requires backend work.
- **Design:** Validate SwiftUI UI/UX with design team; incorporate updated visuals if desired.
- **Data Migration:** None needed, but confirm voiceover legacy behavior and share token handling.
- **Testing Data:** Maintain test accounts and sample discoveries for simulator workflows.
- **Documentation:** Keep `project-documentation` in sync; new iOS docs live in `projects/whats-that-ios`.

This roadmap assumes 6–8 week effort with parallel tracks (e.g., one engineer on AI streaming while another builds StoreKit). Adjust timeframes based on team capacity and risk appetite.
