# Discovery Detail Follow-Up Plan (2025-10-15 12:48:58 UTC)

> **Validity:** This guidance reflects the state of the iOS port at 2025-10-15 12:48:58 UTC. Re-evaluate before applying if the project has progressed; do not rely on this checklist if newer updates exist.

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
- RN detail view starts voiceover playback when narration is available and coordinates with the persistent audio player.
- SwiftUI implementation shows a placeholder button; there is no voiceover fetching or playback yet.

**What to build**
1. Port the voiceover ensure/fetch logic (`DiscoveryContext` equivalent) into a native repository/actor so we can request audio + timing files from Supabase storage.
2. Expose a `VoiceoverPlayer` service that:
   - Downloads audio when needed (respecting exponential backoff rules).
   - Streams playback via `AVAudioPlayer` (or `AVPlayer` for future network playback).
   - Tracks per-discovery position for resume.
   - Emits state updates for both the detail screen and the persistent player.
3. Update `DiscoveryDetailView` to show:
   - Loading states (“Loading narration…”), disabled button when narration is already playing, and proper error feedback when voiceover is missing.
   - A local playback control (play/pause) aligned with the RN layout until the global player ships.
4. Extend the persistent audio player (Phase 3 deliverable) to subscribe to the same service so playback can continue outside the detail screen.

**Dependencies / considerations**
- Supabase storage signed URLs should reuse the existing `SupabaseDiscoveryRepository` client (consider new protocol for voiceover assets).
- Plan for legacy discoveries without narration (< ID 868) by showing the same missing-state experience as RN.
- Leave room for future timing data handling (karaoke / text highlighting).

## Sequencing
1. Implement voiceover repository + playback service so the Play button becomes functional.
2. Wire quick action buttons to creation flows.
3. Backfill tests around the new interactions (detail view logic, repository actor).
4. Fold the persistent audio player UI on top of the shared service once playback is working end-to-end.

These tasks bring the discovery detail experience to feature parity with the React Native app before we resume any animation polish work.
