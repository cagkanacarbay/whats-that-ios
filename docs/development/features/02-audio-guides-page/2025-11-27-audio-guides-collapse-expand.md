Result time: 2025-11-29 — Issue resolved; keeping notes for reference.

2025-11-27 — Audio Guides collapse/expand notes

Summary
- Built: Audio Guides page with collapsing hero → sticky tabs + mini player when scrolling past ~half the hero artwork; mini player shows persistent controls.
- Issue: Previously, returning to full hero from collapsed state was unreliable. This has now been resolved; notes below remain for historical reference.

What works
- Collapse triggers once scroll offset crosses ~half hero height (+24pt hysteresis), shows mini player, pins tabs.
- Mini player stays visible in collapsed mode.

What was broken (resolved)
- Expand path (tap mini): Tap logged but hero often remained hidden; mini could hide without hero returning.
- Expand path (pull-down near top): Logs fired, but hero did not reliably reappear; sometimes mini hid and stayed collapsed.
- Scroll offset preference logs stopped at top, so thresholds were unclear post-collapse.

Attempts and results (resolved)
- Threshold tuning: switched between hero frame-based threshold, measured hero height with fallback (240pt), half-height collapse, and ±24pt hysteresis; collapse OK, expand previously unreliable.
- Auto-scroll vs. manual: tried auto-scrolling to sticky header on collapse and to hero on expand; removed auto-hide of mini to avoid flicker.
- State gating: introduced hasCollapsedHero and pendingExpand; mini hidden only when hero visible again.
- Coordinate space tweaks: measured hero in scroll vs. global; settled on scroll space.
- Tap handler changes: mini tap logged and scrolled to hero without hiding mini immediately.
- Pull-down threshold adjustments: lowered to -10; logs sometimes missing when at list top.

Current status
- Expand reliability issues have been fixed; this document is retained only for reference of the prior investigation.
