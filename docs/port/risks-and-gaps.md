# Risks & Open Questions

This list captures uncertainties, technical debt, and decisions that require follow-up during the native port. Addressing these early will reduce surprises later in the project.

---

## Backend & Service Risks
- **Expo vs APNs Notifications:** Current backend sends Expo push notifications. Native iOS will need APNs device tokens. Options: (1) Extend backend to send APNs alongside Expo, (2) Maintain Expo push by shipping Expo runtime in native app (undesirable), or (3) Defer notifications until backend update is ready. Decision required before Phase 6.
- **OpenAI Model Availability:** `ask-ai-v7` uses `gpt-5-mini`. Ensure production access is stable and in-line with Anthropic/Claude roadmap (project documentation still references Claude). If switching back to Claude, confirm API contracts.
- **Google Sign-In Native Support:** Existing flow uses Expo Auth Session. Project requires Google login on native iOS; integrate `GoogleSignIn` SDK and update Supabase OAuth redirect URIs.
- **Receipt Validation Idempotency:** `validate-receipt` expects Apple `original_transaction_id`. Verify StoreKit 2 surfaces this consistently for consumables and ensure we pass the same identifier. Regression would break purchase deduping.

## Data & Feature Gaps
- **Voiceover Backfill:** Discoveries with ID < 868 lack voiceover assets. These are development assets and can be ignored. Current client short-circuits. Maintain this behavior. 
- **Restore Purchases Flow:** React Native implementation has TODO for restoring purchases. Native launch should include this to match App Store review expectations.
- **Feedback Persistence:** Inline feedback UI is local-only. Clarify whether storage/analytics integration is planned or if we keep it local in v1. Feedbacks are scrapped for this version. Do not port.
- **Discovery Share Tokens:** `discovery.share_token` exists but share flows are not surfaced. Share/deep-link experience is required in native MVP.
- **Map View:** No Map view.

## Client Architecture Risks
- **SSE Streaming Robustness:** Need durable implementation handling mid-stream app suspends, network dropouts, and background completion (matching `activeAnalysisTracker` + `requestTracker` logic). Test coverage must include cancellation/refund cases.
- **Image Preloading Performance:** React Native list suffers from double-trigger & caching bugs (see TODO). Native implementation must avoid repeating mistakes—validate concurrency, dedupe fetches, and manage cache eviction.
- **Large Markdown Rendering:** AI responses can be lengthy; ensure chosen Markdown renderer performs well and supports inline selection for feedback.
- **Camera Permissions UX:** Onboarding currently suppresses prompts until after tutorial. Replicate logic (skip request until onboarding complete) to avoid App Store guideline violations.
- **Push Registration Timing:** Confirm when to request notifications (currently on confirm screen). Evaluate if Apple will reject if triggered too late or without context.

## Operational / Process Risks
- **Environment Drift:** Expo project uses `.env` + EAS for config. Need new pipeline for managing secrets in Xcode/CI. Risk of inconsistent environments during migration.
- **Documentation Divergence:** Use React Native to fork documentation. IOS app will be the only app at the beginning. Keep only up to date docs and keep them updated as changes are made. Don't care about diverging from older docs.
- **Test Data Availability:** Ensure Supabase staging has enough sample discoveries and credits to support simulator QA, especially for voiceover/audio scenarios.

## Decisions Needed
1. **Notification Strategy** – Who owns backend updates for APNs? Deadline before Phase 6. Will decide later, need more info to decide.
2. **Google OAuth Requirement** –We need this
3. **Restore Purchases & Receipts** – Mandatory for initial release
4. **Feedback Feature** – Scrap.
5. **Map View Priority** – No map view.

Resolve or track these items in the new project’s backlog before implementation begins.
