Hero Animation System – 2025-10-20

Commit: d58bae8647e862a57f67176bf96fd23595d9c689

Purpose
- Document the working, reference implementation for the Discoveries → Detail hero transition and its reverse close animation so future changes don’t reintroduce the “jump”, “crop/zoom”, or “landing offset” issues.

Scope
- Files in scope (workspace‑relative):
  - native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/DiscoveriesHomeView.swift
  - native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/DiscoveryImageLoader.swift (image loading helper)
  - native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/DiscoveryDetailView.swift (separate detail; not used by this overlay flow)

System Overview
- We present DiscoveryHeroOverlay above the grid when a card is tapped.
- The overlay animates from the tapped card’s frame to an expanded “hero header” state (open), and from that state back to the card (close).
- The image shown during the transition is the card’s snapshot (placeholder) until the overlay is settled; this prevents any texture swap “jump”.

Key Components
- Hidden Source Cell
  - The tapped card is hidden while the overlay is shown to avoid double‑render.
  - HiddenDiscovery(id, sessionId) tracks which cell to hide.
- Card Frame Capture
  - DiscoveriesGrid writes card frames in the global coordinate space using a PreferenceKey.
  - Dictionary `cardFrames: [Int64: CGRect]` is updated on layout.
- Snapshot Cache
  - DiscoveryHeroImageCache caches a UIImage snapshot for each discovery id.
  - We use this snapshot as the hero image placeholder to ensure pixel‑perfect continuity.

Open Animation (card → overlay)
- State
  - heroContext = DiscoveryHeroContext(sessionId, discovery, imageURL, startFrame, placeholderImage, cardAspectRatio)
  - heroProgress animates 0 → 1 with a timing curve.
  - heroIsSettled flips to true after heroOpenAnimationDuration.
- Rendering
  - Geometry = HeroGeometry(startFrame, containerSize, containerOrigin, cardAspect, progress)
  - While not settled, the overlay shows a hero “card” composed of:
    - DiscoveryHeroImageView(height: geometry.imageHeight)
    - Card chrome overlaid at the bottom
  - We pass preferPlaceholder = true until settled to avoid initial image source swap.
  - Content (markdown, buttons) fades in only after settled.
- Crop Invariant
  - The hero image uses `.scaledToFill` and is clipped to its rect; during open we do not swap sources until settled, so the crop stays visually stable.

Close Animation (overlay → card)
- Goal: Use a single animatable driver so the image and its container transform identically (no crop/zoom drift), start exactly from the user’s last gesture pose, and land exactly on the grid card.
- Inputs
  - destinationFrame: the live grid card frame at close time, taken from `cardFrames[discovery.id]` (fallback: context.startFrame)
  - Captured gesture state on release: closeStartTranslation, closeStartScale, closeStartRotation
- Base layout during close
  - Base hero “card” frame is fixed to expanded header dimensions:
    - baseWidth = containerSize.width
    - baseHeight = min(containerHeight, containerWidth × cardAspect)
  - The entire hero card subtree is then transformed uniformly by UniformCloseTransform.
- UniformCloseTransform (single driver)
  - Driven by `progress` (1 → 0). Compute t = 1 − progress (0 → 1).
  - Compute target center for the destination card in overlay space:
    - targetCenter = destinationFrame.mid − containerFrame.origin (top‑left reference)
  - Compute current center of hero base (before offset):
    - currentCenter = (baseWidth/2, baseHeight/2)
  - Interpolate transform from captured gesture to the card:
    - scale(t) = lerp(initialScale, startScale, t), startScale = destinationFrame.width / containerFrame.width
    - rotation(t) = lerp(initialRotation, 0, t) around Y axis
    - offset(t) = lerp(initialOffset, targetCenter − currentCenter, t) (anchor .center)
  - Apply in order: scaleEffect(.center) → rotation3DEffect(Y) → offset(x,y)
- Image Source During Close
  - preferPlaceholder = true while closing to avoid a source swap causing any visual jump.
- Scroll Coupling
  - Pull‑down offset from internal content scroll is disabled while closing to keep the image rect stationary.

Gesture Interaction
- Activation
  - Left‑edge horizontal drag only (minimum distance, horizontal dominance, and x ≤ heroEdgeActivationWidth).
- While dragging (not closing)
  - heroDragTranslation.x = clamped horizontal translation (≥ 0)
  - heroDragTranslation.y = verticalTranslation × 0.5 (subtle vertical tracking)
  - heroDragScale = lerp 1 → 0.65 as translation approaches a threshold
  - heroDragRotation = up to −5° around Y (subtle parallax)
  - heroDragCornerRadius/Shadow increase slightly with progress
- Release
  - If threshold exceeded, capture closeStartTranslation/Scale/Rotation and trigger close.
  - Else, spring back to settled and reshow content.

Timings
- heroOpenAnimationDuration = 0.5s (cubic bezier)
- heroCloseAnimationDuration = 0.65s (cubic bezier)
- Content fade and control fade are shorter easeInOuts and are tied to `isChromeReady`.

Logging
- Category: HeroTransition (OSLog)
- During close, logs geometry per render with: progress, width, height, imageHeight, widthDrivenHeight, heightDelta, currentAspect, cardAspect, container, destination frame, placeholder, pullDown, chromeReady.
- Use this to verify invariants: heightDelta ≈ 0; currentAspect == cardAspect; pullDown == 0; destination frame matches live card.

Critical Invariants (do not break)
- Use the card snapshot as placeholder until the overlay is settled and while closing.
- During close, transform the entire hero card with one driver (scale + rotation + offset) using anchor .center.
- When computing close offsets:
  - Work in the overlay’s coordinate space (subtract containerFrame.origin).
  - Align centers: offset target = (destinationCenter − currentBaseCenter).
- Do not add content scroll offsets while closing.
- When closing, base hero card dimensions should be fixed to the expanded header (baseWidth = containerWidth; baseHeight = min(containerHeight, containerWidth × cardAspect)).
- Always use the latest `cardFrames[id]` as the destination; fallback to the original startFrame only when needed.
- Keep gesture transforms separate during interaction, and seed the close from their captured values.

Future Improvements
- Derive close duration from remaining distance for parity between back and swipe.
- Consider matchedGeometryEffect for the hero image as a long‑term alternative once we can guarantee view identity lifetimes across the transition.

Test Protocol
- Open/close with back button; verify the hero lands on the card with no offset.
- Swipe with translation + tilt; release to close; verify it continues from the gesture state and lands correctly.
- Scroll detail content, then close; ensure crop stays constant and landing is correct.
- Inspect logs for late‑close frames to verify the invariants.

