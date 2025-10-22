# Discovery Presentation Refactor – Implementation Status

This log tracks the progress of the Discovery presentation refactor so we can coordinate work across the capture flow and the Discoveries feed.

## ✅ Completed
- Scaffolded the `Features/` directory hierarchy for Discovery Creation and Discoveries Feed modules.
- Moved shared helpers (identified error wrapper, bottom overlay preference key, shimmer/pulsing loaders) into `Features/DiscoveryCreation/Common/`.
- Relocated scroll/header/card/hero preference keys into dedicated files under `Features/DiscoveriesFeed/`.
- Extracted capture-stage views into `DiscoveryCaptureStartView`, `DiscoveryCaptureProgressView`, and `DiscoveryCreationErrorView`.
- Lifted the confirmation experience into `DiscoveryConfirmationView`, preserving alerts, location handling, and action overlays.
- Moved the streaming/analyzing stage into `DiscoveryStreamingStageView` with the loader animation and share sheet intact.
- Restored the loader shimmer effect with a repeatable animation and proper teardown.
- Introduced `DiscoveriesHeaderView` with a dedicated `DiscoveriesHeaderMetrics` helper to manage spacing and opacity.
- Split the feed grid into reusable `DiscoveriesGridView`, `DiscoveryCardView`, and supporting image/skeleton components, moving `HiddenDiscovery` into the Grid module.

## 🚧 Still To Do
- Split `DiscoveryConfirmationView` into smaller components (actions, location badge, overlay button style) and move shared palette constants into `Common/`.
- Extract the streaming loader, markdown rendering, and share presenter into separate files within the Streaming module.
- Add the completion stage view (`DiscoveryCompletionStageView`) and share controller wrapper envisioned in the plan.
- Finish migrating Discovery Creation overlays (button styles, palette, constants) to `Common/`.
- Continue the Discoveries Feed extraction: detail overlay animator/interactor, voiceover bar, errors/empty states, and remaining supporting helpers.
- Introduce completion-stage tests/previews once the structure stabilises; add TODO placeholders where appropriate.
- Address remaining macOS build blockers (Credits toolbar API availability, voiceover playback state accessor) so `swift build` succeeds end-to-end once the refactor settles.
