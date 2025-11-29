2025-11-27 — Audio Guides collapse/expand notes

Summary
- Built: Audio Guides page with collapsing hero → sticky tabs + mini player when scrolling past ~half the hero artwork; mini player shows persistent controls.
- Issue: Returning to full hero from collapsed state is unreliable. Mini player tap and pull-down at top do not consistently restore the hero; mini sometimes hides without the hero reappearing.

What works
- Collapse triggers once scroll offset crosses ~half hero height (+24pt hysteresis), shows mini player, pins tabs.
- Mini player stays visible in collapsed mode.

What’s broken
- Expand path (tap mini): Tap logs but hero often remains hidden; mini may hide without hero returning.
- Expand path (pull-down near top): Logs fire, but hero does not reliably reappear; sometimes mini hides and stays collapsed.
- Scroll offset preference logs stop when at top, so we can’t confirm thresholds firing post-collapse.

Attempts and results
- Threshold tuning: switched between hero frame-based threshold, measured hero height with fallback (240pt), half-height collapse, and ±24pt hysteresis; collapse OK, expand still unreliable.
- Auto-scroll vs. manual: tried auto-scrolling to sticky header on collapse and to hero on expand; removed auto-hide of mini to avoid flicker; still no reliable expand.
- State gating: introduced hasCollapsedHero and pendingExpand; mini hidden only when hero visible again. Behavior improved but expand still fails intermittently.
- Coordinate space tweaks: measured hero in scroll vs. global; settled on scroll space. Logging shows collapse events but expand path incomplete.
- Tap handler changes: mini tap now logs and scrolls to hero without hiding mini immediately; still doesn’t restore hero state reliably.
- Pull-down threshold adjustments: lowered to -10; still not restoring hero consistently; logs sometimes missing when at list top.

Current suspicion
- Scroll offset preference may stop updating at the top of the list, so expand logic based on offset/minY never completes, leaving hero hidden and mini state out of sync.
- Hero height reporting 0 in logs suggests measurement timing issue; collapse uses fallback height, but expand completion depends on hero frame reaching baseline (may not occur once hidden).

Next steps to fix
- Move expand trigger to explicit gesture detection (e.g., on the list’s DragGesture) rather than offset preference at top, or add an explicit “Expand” button on mini as a fallback.
- Ensure hero frame reporting when hidden: temporarily keep hero at minimal opacity instead of height zero to get frame updates; then hide only after expand completes.
- Add dedicated state machine (collapsed/expanding/expanded) to avoid hiding mini until hero visibility is confirmed.
