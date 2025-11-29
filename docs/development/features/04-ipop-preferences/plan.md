# IPoP Preferences Capture – Plan

## Goals
- Let users state and order their IPoP preferences during onboarding and later in Settings, with clear, friendly copy.
- Tell users we use these preferences to shape responses (usually honor them, sometimes blend others).
- Pipe the ordered preferences into Ask AI v7 via `customContext` so prompt assembly can bias lens selection (only when the user has provided an order).

## Current State (today)
- Onboarding flows: `PreOnboardingCarousel` and `PostOnboardingCarousel` have no IPoP content; post flow covers welcome, narration voice, location permissions, and first action CTA.
- Settings (`SettingsView`) offers audio guide, account, cache/onboarding reset sections but no IPoP controls.
- Discovery request payloads: `DiscoveryContextBuilder` builds `customContext` with recent discoveries and history only; `DiscoveryCreationFlowViewModel` forwards it to `SupabaseDiscoveryAnalysisClient`.
- Ask AI v7 (`supabase/functions/ask-ai-v7/index.ts`) parses `customContext` JSON for recent/history only, then drops the pretty-printed JSON into the user prompt. System prompt already describes IPoP but has no per-user preference input.

## Requirements From Brief
- Add an onboarding screen/sheet for users to set and order IPoP preferences; reuse in Settings for later changes.
- Minimal, readable explanation of IPoP using system prompt content but simplified for users.
- Explicit note on onboarding + settings: we use preferences to construct responses and usually follow them, but not always.
- Preferences must be ordered (user can drag/reorder) across the four dimensions: Ideas, People, Objects, Physical.
- Feed the ordered preferences into Ask AI v7 through `customContext`; craft a prompt-ready message so lens selection respects the ordering.

## Proposed UX
- **Onboarding (post-auth flow)**: Add a new mandatory slide in `PostOnboardingCarousel` before the voice picker. Content:
  - Title: “What should we lean into?”
  - Body: “Drag to rank what you care about. We’ll shape most responses around your top picks (sometimes we’ll mix others if it fits).”
  - Reorderable list with drag handles + short labels (see Copy below). Primary CTA “Save order”; no skip option—onboarding cannot complete without an order.
- **Settings**: New section “Experience style (IPoP)” in `SettingsView`.
  - Row shows summary chips if set; if unset, show “Not set yet” + “Set order” chevron; tapping opens a sheet reusing the same reorder UI and explainer text.
  - Inline helper text: “We usually follow this order when writing discoveries, but may blend other angles if it helps.” Use the same sheet style/presentation as the existing voice-model picker sheet for consistency.
- **Copy (user-friendly IPoP definitions)**:
  - Ideas — “big-picture reasons, facts, and how things fit together.”
  - People — “human stories, feelings, and relationships.”
  - Objects — “design, craft, and what things are made of.”
  - Physical — “sights, sounds, movement, and other senses.”
- Accessibility: ensure drag handles are reachable; otherwise follow standard Settings sheet accessibility (no custom VoiceOver-specific controls planned).

## Data Model & Persistence
- Add domain model `IPoPDimension: CaseIterable, Codable` (Ideas, People, Objects, Physical).
- Add `IPoPPreferences` with ordered array of dimensions.
- Add `IPoPPreferencesStore` (UserDefaults-backed, namespaced keys like `ipop.preferences`) with load/save/reset.
  - No default order: stored value is `nil`/empty until user provides one.
- Wire the store into `AppDependencyContainer` and `DiscoveryCreationDependencyProvider` so onboarding, settings, and discovery flow share the same source of truth.

## Client Integration to Ask AI
- Extend `DiscoveryContextBuilder` to accept `IPoPPreferences` and include them in the serialized `customContext` **only when the user has set an order**, e.g.:
  ```json
  {
    "recentFullDiscoveries": "...",
    "aggregatedHistory": "...",
    "ipopPreferences": { "ordered": ["Ideas","People","Objects","Physical"] }
  }
  ```
- Update `DiscoveryCreationFlowViewModel` to load preferences from `IPoPPreferencesStore` during confirmation setup and pass into the builder.
- Keep payload JSON compact (ordered list only) to preserve existing history fields.

## Ask AI v7 Changes
- In `supabase/functions/ask-ai-v7/index.ts`, parse `ipopPreferences.ordered` from `customContext` JSON.
- When present, build a prompt-friendly string for `customContext` variable (see “Prompt string options” below) and append it; when absent, do not mention IPoP in `customContext` at all.
- Keep `recentFullDiscoveries` and `userDiscoveryContext` behavior unchanged.
- Update `user-prompt.ts` to state that user IPoP preferences are provided below in `customContext` and must be followed for lens ordering.

## UI/Logic Components
- Shared view model (e.g., `IPoPPreferencesViewModel`) to load current order, handle reordering, save, and expose display chips for summaries.
- Reusable SwiftUI view for the reorder list (drag handles, definition subtitle, “most important” label on top row).
- No skip/clear/reset; only user-defined order. Show a subtle “Saved” toast after updates in Settings. Match the existing voice-model picker sheet interaction style.

## Copy/Consent Placement
- Onboarding + Settings both include the usage note: “We use these to shape your discoveries and usually follow your order, but we might mix other angles when it helps.”
- Keep text within 120-character lines to match existing style guidance.

## Testing & QA Notes
- Unit tests: `IPoPPreferencesStore` load/save/reset including “unset” state; `DiscoveryContextBuilder` includes `ipopPreferences` only when set and keeps history intact.
- View model tests: ordering mutations persist and surface in summaries.
- Integration: discovery request JSON contains `ipopPreferences` when set; Ask AI function maps to prompt variables; no regressions when preferences are missing.
- UI checks: onboarding slide pagination and indicators still align; Settings sheet presents/dismisses correctly; VoiceOver can reorder.

## Open Decisions
- None specific to analytics; telemetry for IPoP can be omitted for this release.

## Prompt String (for when preferences exist)
- “IPoP preference order: Ideas → People → Objects → Physical. Primary lens bias: aim ~60/30/10/rare with ranges 45–70% / 20–40% / 5–20% / ≤5%. Flip lens selection is independent of this order and may use any IPoP dimension.”

## Lens Distribution Guidance (primary lens only)
- Apply only to the primary lens; flip lens can be any dimension regardless of preference.
- Use the ordered list to bias primary lens selection:
  - Top lens: target ~60%; acceptable range 45–70%
  - Second lens: target ~30%; acceptable range 20–40%
  - Third lens: target ~10%; acceptable range 5–20%
  - Fourth lens: extremely rare; acceptable up to 5% only when the content truly calls for it
- Physical as primary should be rare unless the subject strongly warrants it (e.g., “breathtaking view,” highly sensory scene). Even if the user ranks Physical low, it can still appear as a flip lens.
