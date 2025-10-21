# Discovery Detail Follow-Up Plan (2025-10-15 17:40:00 UTC)

> **Validity:** This guidance reflects the state of the iOS port at 2025-10-15 17:40:00 UTC. Re-evaluate before applying if the project has progressed; do not rely on this checklist if newer updates exist.

The native detail screen is in place (hero image, gradient overlay, share/map actions, Markdown body), but the quick action buttons and voiceover experience still need to be ported. This note outlines what remains and how to approach it.

## Quick Action Buttons (Camera / Upload)

**Current state**
- React Native provides “Take another photo” and “Upload a photo” buttons inside the detail body, each restarting the respective creation flow.
- SwiftUI detail view renders the layout placeholders, but the buttons are not yet wired to the creation pipelines.

**What to build**
1. Surface the actions in `DiscoveryDetailView` once the user scrolls past the hero (same placement as RN).
2. Route taps through `DiscoveriesHomeView` so we can dismiss the detail overlay and hand control to the appropriate tab:
   - Camera button should trigger the camera creation flow (`DiscoveryCreationFlowType.camera`), ideally by signalling the existing tab state machine.
   - Upload button should trigger the photo library flow (`DiscoveryCreationFlowType.upload`).
3. Ensure the discovery detail overlay dismisses before the flow begins to avoid double presentations.
4. Track analytics/hooks to match the RN implementation (if available).

**Dependencies / considerations**
- Requires a publicly exposed method on `AppDependencyContainer` / `DiscoveriesHomeView` to request a creation flow.
- Revisit navigation once the creation state machine (Phase 4) starts so these shortcuts remain compatible.

## Voiceover Playback

**Current state**
- Supabase-backed `SupabaseVoiceoverRepository` generates signed URLs, caches metadata, and surfaces missing/error states for legacy discoveries.
- `VoiceoverPlaybackController` now drives both the inline “Play Audio Narration” button and the persistent mini player rendered at the bottom of the home view. Playback resumes after dismissing the detail overlay, and the controller exposes loading/error strings that match the RN experience.
- Tests cover model selection fallback logic; end-to-end simulator build succeeds with voiceovers enabled.

**What remains**
1. Share playback state with any future global player surfaces (skip/queue controls planned for Phase 3 follow-up) and ensure controller lifetimes are coordinated when creation flows eventually adopt audio previews.
2. Capture and restore per-discovery progress between launches (current `VoiceoverPlaybackController` resets to 0 on app kill; RN persists positions with AsyncStorage).
3. Evaluate timing JSON once karaoke/highlighting work is back on the roadmap.

**Dependencies / considerations**
- `VoiceoverPlaybackController` is injected via `AppDependencyContainer.makeVoiceoverPlaybackController()`; make sure creation flows request the same instance once quick actions unblock handoff.
- Supabase bucket TTL mirrors the RN 7-day cached URLs; adjust constants in the repository if backend policy changes.

## Sequencing
1. Wire quick action buttons to creation flows (still outstanding, see next section).
2. Persist playback positions and expose richer transport controls once the global player UI ships.
3. Fold timing JSON support / analytics hooks in a later pass.

These tasks bring the discovery detail experience to feature parity with the React Native app before we resume any animation polish work.
