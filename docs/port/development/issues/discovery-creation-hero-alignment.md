# Discovery Creation → Hero Overlay Alignment

## Goal
Make the post-creation experience identical to opening a discovery from the Discoveries grid so that:
- the full-screen detail uses the existing `DiscoveryHeroOverlay` implementation,
- dismissing the overlay always animates back into the newly created card,
- users never perceive a navigation transition while streaming completes.

## Key Requirements
1. **Seamless transition** – while the creation flow streams, keep showing the current `AnalysisStateView`. Once the summary is ready, swap to the Discoveries tab behind the scenes and let the hero overlay take over.
2. **Single detail implementation** – reuse the exact hero overlay (`DiscoveryHeroOverlay` / `DiscoveryHeroContentView`) rather than a bespoke detail view.
3. **Matched-geometry dismissal** – when the overlay closes it must animate into the correct card. If the card frame is not yet known, fall back to the first card in the grid (the newly created discovery).
4. **No visible navigation change** – the user should observe: streaming → full detail → dismiss to grid. The tab switch to Discoveries happens invisibly.

## Proposed Architecture

### 1. Creation Flow
- Keep `DiscoveryCreationFlowView` and `AnalysisStateView` as-is for streaming.
- When `DiscoveryCreationFlowViewModel` hydrates `analysisState.discoverySummary`, fire `onDiscoverySummaryReady(summary)` (existing callback).
- In `MainTabView`, handle that callback by:
  - switching `selectedTab` to `.discoveries`,
  - cancelling both creation view models so the creation tab returns to idle,
  - storing the summary in `pendingCreatedSummary` and the id in `pendingDiscoveryId`.

### 2. Discoveries Home View
- Expose card frames from `DiscoveriesGrid` to `DiscoveriesHomeView` (Lift the `DiscoveryCardFramePreferenceKey` state).
- On every layout update, record the `CGRect` for each discovery id.
- Update `presentPendingDiscoveryIfNeeded`:
  - Ensure the summary exists in `viewModel.discoveries`. If not, bail (the feed is still loading).
  - Determine the start frame: prefer the recorded frame for the pending id; if it’s missing, fall back to the first discovery’s frame (the newly inserted item).
  - Invoke `handleDiscoverySelection` with that frame so the hero overlay animates exactly like a user tap.
- Remove the custom `DiscoveryCreationDetailView` once this path is active; all detail presentation uses `DiscoveryHeroOverlay`.

### 3. Hero Overlay Reuse
- No new UI — reuse `DiscoveryHeroOverlay`, `DiscoveryHeroContentView`, `VoiceoverDetailButton`, and the existing matched-geometry layout.
- Hero overlay already handles voiceover, sharing, maps, etc., so no additional wiring is required beyond ensuring the voiceover controller is primed via `ensureMetadata`.

### 4. Error Handling
- If summary hydration fails, the flow remains in `AnalysisStateView` with the existing error state (`analysisFailed`). We do **not** attempt to switch tabs or open the overlay.
- If hydration succeeds but the new card is not yet visible (pagination/loading), the fallback start frame (first card) provides a deterministic animation target.

## Migration Steps (High Level)
1. Update `MainTabView` to perform the hidden tab switch and cancel creation flows when summaries arrive.
2. Lift card-frame tracking into `DiscoveriesHomeView` and expose frame data from `DiscoveriesGrid`.
3. Adjust `presentPendingDiscoveryIfNeeded` to wait for frame data, fall back to the first card when necessary, and call `handleDiscoverySelection`.
4. Remove the creation-specific detail view and any dead code once the new flow works end-to-end.

## Notes
- The automatic tab switch changes the highlighted tab icon; this is acceptable per stakeholder confirmation.
- The fallback animation target is guaranteed because new discoveries are inserted at the top of the feed.
- Keep `DiscoveryCreationDetailView` temporarily until implementation is complete, then delete during cleanup.
