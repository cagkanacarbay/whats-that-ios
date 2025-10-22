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
- Split the confirmation stage UI into `DiscoveryConfirmationActionsView` and `DiscoveryConfirmationLocationBadge` while centralising palette/constants/overlay styling in `Features/DiscoveryCreation/Common/`.
- Extracted streaming subviews into `DiscoveryStreamingLoaderView` and `DiscoveryStreamingMarkdownView` for clearer responsibilities.
- Introduced `DiscoveriesHeaderView` with a dedicated `DiscoveriesHeaderMetrics` helper to manage spacing and opacity.
- Split the feed grid into reusable `DiscoveriesGridView`, `DiscoveryCardView`, and supporting image/skeleton components, moving `HiddenDiscovery` into the Grid module.
- Moved the discovery detail overlay stack (context, image cache, geometry helpers, animator, and dismiss interactor) into `Features/DiscoveriesFeed/DetailOverlay/` and rewired `DiscoveriesHomeView` to consume the extracted view.
- Relocated the persistent voiceover player into `Features/DiscoveriesFeed/Voiceover/`, introducing `VoiceoverPlaybackBindings` for slider state management.
- Extracted feed toast, empty, and error surfaces into `Features/DiscoveriesFeed/Errors/` so grid and shell reuse a shared implementation.
- Moved `DiscoveriesHomeView`, hero header components, the shared discovery image loader, and `VoiceoverDetailButton` into the `Features/DiscoveriesFeed/` hierarchy so feature assets live alongside their modules.
