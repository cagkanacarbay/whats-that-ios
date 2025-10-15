# Discovery Hero Animation

This note documents the native implementation for the discovery-card hero animation that mirrors the behaviour from the React Native app.

## Source Reference
- React Native grid item: `components/custom/DiscoveryItem.tsx`
- Modal orchestration: `contexts/DiscoveryModalContext.tsx`
- Animation primitive: `react-native-reanimated` shared transition driven by `animationProgress`

Key points observed in the reference implementation:
- The tapped card is measured (`measure`) and the resulting rect is forwarded to the modal provider alongside the resolved image URI.
- Opening animation eases from the card frame to the full screen over 500 ms using a cubic ease-out curve. Width, height, x/y origin, and border radius are interpolated from the card rect to the full-screen container.
- The image stays visible throughout the transition. Details content fades in only after the expansion completes, preventing heavy UI work during the animation.
- Dismissal fades details out over 50 ms, then springs the container back to the source rect (`damping: 15`, `stiffness: 100`). Gestures feed translation/scale/rotation, but the base hero animation remains purely positional.

## SwiftUI Implementation Summary
- Grid now captures each card’s global frame via a preference key and hides the selected card while the hero overlay is active.
- `DiscoveryHeroContext` stores the selected discovery, image URL, measured frame, and a snapshot placeholder. We capture the snapshot from the key window immediately before hiding the card so the opening animation never shows an empty gradient.
- Overlay drives a single source of truth `progress` that transitions 0 → 1 on open (ease-out 0.5 s) and 1 → 0 on close (spring). Width, height, offsets, border radius, and shadow interpolate from the source rect to the full-screen container.
- The hero image view first renders the cached snapshot (or gradient) and swaps to the network image once `AsyncImage` finishes, eliminating the black flash seen previously.
- During closing the image height interpolates back to the card height instead of keeping full height, preventing the visible “cropping” pop.
- Detail content (gradient header, markdown body, share/map buttons) sits inside the overlay with opacity controlled by the animation, mirroring the RN layering.

## Follow-Up
- Hook the interactive swipe-to-dismiss gesture back in (parity with RN `EdgeGestureDetector`).
- Plumb voiceover playback and quick action shortcuts as outlined in `docs/port/development/discovery-detail-followup.md`.
