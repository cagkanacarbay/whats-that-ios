# Discovery Creation Flow Snapshot (2025-03-18)

> **Scope:** Tracks the in-flight SwiftUI camera/upload pipelines, confirmation step, and AI streaming experience now ported from the Expo app. Use this as the single source of truth for what’s implemented and which gaps remain before we can call Phase 4 complete.

---

## ✅ Current State
- **Shared ViewModel (`DiscoveryCreationFlowViewModel`)**
  - Drives both camera and upload flows with parity to the React Native finite state machine.
  - Fetches credits, builds recent-discoveries context, and pulls CoreLocation metadata before the confirm screen renders.
  - Streams `ask-ai-v7` SSE responses, continuously parsing token batches to produce Markdown-safe body copy plus metadata (title + short summary) for the UI.
  - Emits newly created discovery IDs back to the tab coordinator so the feed can refresh and open the hero modal immediately after completion.

- **Confirmation Screen (`DiscoveryCreationFlowView`)**
  - Displays the captured image, live credit balance, low-credit warnings, and resolved location string.
  - Disables “Continue” when the user is out of credits and keeps a prominent retake affordance.
  - Shows that personalised context is preparing once recent discoveries load.

- **Streaming UI**
  - Recreates the RN loading cadence with animated status badges, rotating “listening” messages, and a Markdown-rendered body that updates as tokens arrive.
  - Surfaces metadata (title + short description) as soon as the parser extracts a valid JSON block.
  - Falls back gracefully when the stream is empty or cancelled.

- **Home Tab Integration**
  - `MainTabView` binds the creation flows to the Discoveries tab and tracks a `pendingDiscoveryId`.
  - `DiscoveriesHomeView` refreshes the feed, then automatically presents the hero overlay for the new discovery once data lands.

- **Unit Coverage**
  - Parser tests ensure metadata extraction stays in sync with the edge function format.
  - A view model test covers the end-to-end streaming happy path (credits/location/context + completion callback).

---

## 🚧 Known Gaps & Next Tasks
1. **Error + Cancellation UX**
   - Mirror RN banners for insufficient credits, SSE failures, and manual cancellation recovery.
   - Wire credit purchase CTA from the confirm screen once StoreKit work lands.

2. **Streaming Resilience**
   - Adopt the RN-style request tracker so background suspends or duplicate requests get replayed safely.
   - Persist the streaming transcript if the user backgrounds mid-run and resumes later.

3. **Push & Location Enhancements**
   - Complete push token registration (NativePushService currently returns `nil` placeholders).
   - Display richer location provenance (EXIF vs live GPS) and expose “Open in Maps” once map links are ready.

4. **Creation Flow Shortcuts**
   - Detail quick actions in `DiscoveryDetailView` (“Take another photo”, “Upload a photo”) so the hero overlay can relaunch the respective creation pipeline.
   - Add pull-to-refresh chip reminder when the user returns to the creation tabs after completing a discovery.

5. **UI Polish & Animations**
   - Reintroduce RN’s countdown shimmer & loader clears for the confirm and streaming screens.
   - Bring over sound/animation cues once assets are available.

6. **Testing & Diagnostics**
   - Add snapshot/UI tests around the confirmation + streaming layouts.
   - Create targeted integration tests for SSE cancellation and metadata parsing edge cases.
   - Resolve the outstanding `SupabaseVoiceoverRepositoryTests` dependency so full `swift test` can pass again.

---

## Observations / Open Questions
- The Expo app rotates fun loader strings via shared constants—consider centralising those in `WhatsThatShared` so both the confirm and streaming views reuse them.
- We still rely on UIKit pickers; investigate PhotosPicker/AVCapture pipeline swap once we have time for SwiftUI-native camera scaffolding.
- Credits fetching currently swallows errors; decide whether we want inline retry UI or to push the user to the settings credits screen.

---

_Next sync_: Once the error-handling + quick actions ship, revisit this note and update the “Known Gaps” section before starting the StoreKit integration work.*** End Patch
