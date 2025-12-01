# Audio Guides – Implementation Plan (Working Draft)

Purpose: migrate Audio Guides to use the existing Voiceover playback backend (engine, caching, storage, generation) while replacing all legacy Voiceover UI with the new hero/mini player UX. Track decisions made vs. open items to settle before coding.

## Decisions Locked (per product direction)
- Reuse `VoiceoverPlaybackController` backend stack (playback, caching, generation, credits); do not rewrite engine or generation flow.
- Remove/replace old Voiceover UI (e.g., `VoiceoverPersistentPlayerView`, `VoiceoverPlayerBar`, `VoiceoverPlayerHost`) with the Audio Guides hero + mini player UI.
- Extend playback controls with ±5s seek buttons and press-and-hold accelerated seek.
- History is append-only with timestamps; every played discovery is added once per completion/start event and retains last known position for resume.
- Progress resume per discovery: remember last position and restore on replay.
- Autoplay: when enabled, skip items that are not ready; skipped non-ready items stay at the top of Up Next. If status is generating/failed, item remains at the top; failed requires user retry before playback.
- My Discoveries list uses the same Discovery dataset (1:1 with Discovery feed).
- Use existing “generate voiceover” edge function for Audio Guides; reuse credits behavior and storage/caching policies.

## To-Do: Immediate Investigation Tasks
- Audit Voiceover UI components to deprecate: map where `VoiceoverPersistentPlayerView`, `VoiceoverPlayerBar`, `VoiceoverPlayerHost`, inset stores, and related insets are instantiated (e.g., Discoveries tab safe area inset) and plan removal/replacement with Audio Guides mini player.
- Review `VoiceoverPlaybackController` APIs for:
  - Seek hooks to support ±5s and press-and-hold accelerated seek.
  - Rate control entry points (playback speed) and persistence hooks.
  - Queue provider integration (already present for discovery sequences) to align with Up Next model.
  - Error surfacing and retry pathways we can re-use.
- Inspect generation flow call sites (Discovery creation, Settings auto-generate toggle) to ensure Audio Guides connects to the existing edge function and credit handling without duplication.
- Inventory data models where discovery IDs are the source of truth (e.g., `DiscoverySummary`) to replace Audio Guides’ mock UUIDs.
- Identify storage/persistence mechanism for queue/history/progress (UserDefaults? local store? existing voiceover stores) and gaps to fill.

## Architecture & Data Model Draft
- Identity: use stable `DiscoverySummary.id` (Int64) everywhere; no transient UUIDs.
- Queue model (Up Next):
  - Ordered list of discovery IDs.
  - Each entry has status (ready/generating/failed/missing), progress, and insertion source (manual/auto) if needed.
  - Persistence local-first (disk cache); discuss whether to sync to backend later (not in scope now).
  - Autoplay skip rule: skipped non-ready items remain at head until ready/failed retry resolves.
  - Reordering allowed; removal advances current when applicable.
- History model:
  - Append-only log with discovery ID, last position, timestamp of last play.
  - No mutation except truncation/cleanup policy (to decide).
- Progress:
  - Per-discovery position stored locally; restored on play.
  - Update on periodic ticks and on pause/stop transitions.
- Playback settings:
  - Playback speed presets (0.75/1/1.25/1.5/2x) stored (scope to decide: per-user global vs. per-discovery).
  - Autoplay toggle persisted.

## Up Next Behavior – Questions to Settle
- When starting playback from a random discovery (outside queue), should it inject as “current” with previous/next drawn from queue, or should it snapshot surrounding discoveries (e.g., feed order)?  
- How to reconcile existing queued items with ad-hoc play:
  - If queue is non-empty and user taps a discovery elsewhere, do we (1) insert it at head as current, (2) treat queue as next items, (3) clear queue on confirm, or (4) branch into a transient session?
  - Do we offer a “Clear queue” action? If so, does it also stop playback/mini?
- Auto-generated items: where are they inserted (tail vs. after current), and how are they marked to avoid duplicate manual queueing?
- Section layout implications:
  - Now Playing pinned row.
  - Up Next section with collapsed view/expand affordance for long queues.
  - Last Played section with expandable history and clear visual separation.
  - Swipe-to-remove affordance with haptics on all queue rows (incl. current/upcoming).

## Discovery Detail Integration – To Hammer Out
- Navigation contract: tapping Audio pill in Discovery Detail should open Audio Guides hero for that discovery; Text pill in hero should navigate back to Discovery Detail.
- Animation/transition: desired “page-flip” effect—where to implement (shared coordinator?) and how to keep mini/hero in sync during transition.
- Data handoff: ensure detail view provides the discovery to the playback controller with correct asset state and image URL; avoid duplicate fetches when switching contexts.
- Back stack: after opening from detail, back should return user to previous screen, not always Audio Guides tab root.

## Generation & Credits – Alignment Tasks
- Wire Audio Guides creation flows to existing generate-voiceover edge function; reuse credit deduction and error handling already present.
- Absent/failed states:
  - Confirm UI triggers the same generation pathway as Discovery creation flow.
  - Ensure retry uses the same request path and updates status chips.
- Auto-generate toggle (Settings): define whether it immediately enqueues generated guides into Up Next and how status transitions (generating → ready) update the queue/head item.
- Balance updates: ensure responses update local credit balance and UI chips.

## Storage, Caching, Offline/Streaming
- Reuse `VoiceoverFileCache` for audio guides; define directory/naming convention per discovery.
- Offline behavior: if not cached and offline, block playback with “Download to Play”; surface retry/download affordance.
- Streaming fallback when online if not cached; prefetch queued items; dedupe concurrent fetches.
- Retention: follow existing voiceover eviction policy; confirm no extra retention requirements for audio guides.

## Playback UX Integration
- Mini player must replace legacy voiceover mini globally (visible on all screens where legacy appears) and open Audio Guides page; back/close returns to prior screen.
- Hero/mini sync: both views bound to shared controller state; collapse/expand must not interrupt playback.
- Controls to add:
  - ±5s buttons (tap).
  - Press-and-hold accelerated seek (define acceleration curve).
  - Playback speed menu wired to engine rate.
  - Resume state reflected in both hero and mini.
- Error surfacing: inline error + retry in mini/hero; dismissing mini while error visible stops playback and hides mini.

## My Discoveries (Data & UI)
- Drive list from real discoveries feed; statuses mapped from `DiscoveryVoiceoverAsset` (ready/processing/missing/failed).
- Chip rules: Ready/Generating/Failed/Empty plus `Queued` when in Up Next and `Playing` when active.
- Queue actions: swipe/menu add to end or play next; block duplicate queueing when already queued.
- Absent state triggers credit modal using shared generation path; failed state retry uses same.

## Persisted Settings & Progress
- Decide storage mechanism for:
  - Queue ordering, current item, autoplay toggle.
  - Per-discovery progress and last-played timestamps (history).
  - Playback speed selection.
- Consider migration from any existing voiceover preference store (e.g., `VoiceoverPreferencesStore`) for speed/auto.

## UI Removal/Replacement Plan (high level)
- Remove usages of `VoiceoverPersistentPlayerView`, `VoiceoverPlayerBar`, `VoiceoverPlayerHost`, and related inset plumbing; replace with Audio Guides mini player surfaced globally.
- Ensure tab insets/layout remain correct after removing voiceover-specific safe area insets.

## Outstanding Questions / Decisions Needed
- Exact Up Next behavior when playing ad-hoc items and how to merge/clear queues.
- Where to persist queue/history/progress (UserDefaults vs. lightweight store) and retention limits.
- Whether playback speed is global or per-discovery; default value on cold start.
- Exact accelerated-seek interaction (hold threshold, step size growth, haptics).
- Auto-generate insertion point in queue and dedupe rules for auto vs. manual items.
- Navigation/animation implementation for Discovery Detail ↔ Audio Guides hero (“page-flip”) and how to handle deep links/back stack.
- Whether to expose “Clear queue” and “Clear history” affordances; any UX gating.

## Next Steps
- [ ] Complete deep-dive of `VoiceoverPlaybackController` to map required extension points (seek, rate, queue provider, error handling, progress persistence).
- [ ] Inventory and mark all legacy voiceover UI entry points for removal/replacement.
- [ ] Draft detailed Up Next queue behavior spec (ad-hoc play, clear queue policy, auto vs. manual ordering).
- [ ] Define persistence layer for queue/history/progress and speed/autoplay settings.
- [ ] Design navigation contract for Discovery Detail ↔ Audio Guides (including animation approach).
