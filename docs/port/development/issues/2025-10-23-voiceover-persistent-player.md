# 2025-10-23 – Voiceover Persistent Player Port

## Context
- React Native app uses a single compact audio player (`components/custom/PersistentAudioPlayer/PersistentAudioPlayer.tsx`) that stays pinned to the bottom of the screen without blocking primary content.
- Swift port currently renders a larger floating card (`VoiceoverPlayerBar.swift`) only on the discoveries feed, shows a separate `VoiceoverDetailButton.swift` inside the detail overlay, and exposes no player during discovery streaming.
- Goal: align iOS implementation with the RN experience—one shared, lightweight player visible on the feed, discovery detail, and streaming states, hiding only when it would conflict with capture/upload flows.

## Current Gaps
- `VoiceoverPlayerBar` consumes excess vertical space, lacks the RN slider-first layout, and lives in a view-specific overlay (`DiscoveriesHomeView.swift` lines around 245-555).
- Discovery detail overlay keeps a bespoke button and pads bottom content manually (`DiscoveryDetailView.swift` lines around 252-312).
- Discovery streaming flow (`DiscoveryStreamingStageView.swift`) never surfaces playback controls.
- No shared mechanism broadcasts player height, so screens guess at spacers and insets.

## Objectives
1. Introduce a SwiftUI equivalent of the RN persistent player with the same compact layout, transport controls, and close affordance.
2. Centralize presentation so only one player instance exists across the app, while respecting safe areas and capture/upload visibility rules.
3. Ensure feed, detail, and streaming surfaces pad or offset their content using a shared inset rather than hard-coded values.

## Plan
1. **Build `VoiceoverPersistentPlayerView`**
   - Mirror RN layout (slider stack, artwork thumbnail, elapsed/total labels, circular play/pause, close button).
   - Reuse `VoiceoverPlaybackBindings` for slider math and hook into `VoiceoverPlaybackController` actions.
   - Load cover art via `DiscoveryCachedImage`; fall back to waveform icon.

2. **Player Host & Height Propagation**
   - Create a container modifier/view that renders the persistent player once near the root.
   - Measure its height with a `PreferenceKey` and publish visibility state so descendants can pad scroll content and indicators.
   - Mirror RN hide rules: respect `VoiceoverPlaybackController.isDetailOverlayActive` and suppress during capture/upload phases.

3. **Integrate at App Root**
   - Mount the host inside `MainTabView` so all tabs and overlays inherit the shared inset.
   - Ensure creation overlays continue to render above the persistent player when appropriate.

4. **Refactor Discoveries Feed**
   - Remove `VoiceoverPlayerBar` and associated overlay stack from `DiscoveriesHomeView`.
   - Replace hard-coded bottom padding with the shared player inset.

5. **Update Discovery Detail Overlay**
   - Stop rendering additional padding once playback is active; instead consume the shared inset.
   - Toggle `voiceoverController.isDetailOverlayActive` while the overlay is on-screen so the global player hides and the detail-specific layout can control playback initiation.
   - Retain a button or CTA purely for triggering playback—do not introduce a second player UI.

6. **Augment Discovery Streaming Flow**
   - Wrap `DiscoveryStreamingStageView` (and any other streaming surfaces) with the inset reader so the persistent player appears above its content without masking controls.

7. **Clean-Up**
   - Delete `VoiceoverPlayerBar.swift` once unused.
   - Align colors, typography, and spacings with Brand tokens; add accessibility labels and safe-area handling.

8. **Validation**
   - Manually verify playback across feed, detail, and streaming states; confirm close button collapses the inset.
   - Exercise capture/upload flows to ensure the player hides at the right times.
   - Add unit/UI regression coverage where feasible for controller state transitions.

## Decisions
- **Single layout only:** stick with the compact player; no expanded variants needed because target devices are iPhones.
- **Streaming visibility:** keep audio playback running if the user started it, hide the player during capture and confirm screens, and surface it again once the streaming screen appears.
