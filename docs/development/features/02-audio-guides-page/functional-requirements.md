# Audio Guides – Functional Requirements (Working Draft)

Status legend: ✅ locked, ⏳ open for discussion, 🔍 to verify against existing voiceover system.

## Audio Player + Mini Player
- ✅ Replace existing voiceover playback controller; same global availability (wherever current player is shown). Tapping mini from any screen opens the full Audio Guides page; back returns to prior screen.
- ✅ Controls: play/pause, next/prev in queue, seek via ±5s buttons (no scrubbing required). Holding the ±5s buttons should repeat/accelerate seek jumps.
- ✅ Playback speed presets: 0.75x, 1.5x, 2x. No sleep timer.
- ✅ States tracked: ready / playing / paused / stopped; maintain position and duration for display.
- ✅ Mini dismiss: dismiss stops playback if active; hidden when stopped.
- ✅ State sync: hero and mini share the same item/progress; collapse/expand does not interrupt playback.
- ✅ Per-guide resume: track last-played position per discovery; surface progress in My Discoveries rows and history items in Up Next.

## Audio Guide Storage & Caching
- 🔍 Reuse existing voiceover caching layer for Audio Guides; verify parity with new needs.
- ✅ Offline: play from cache when available; if not cached and offline, show “Download to Play” and block playback.
- ✅ Streaming fallback when online if not cached.
- ✅ Prefetch: any item placed in the queue (manual insert or auto) is prefetched in the background. Track in-flight fetches to avoid duplicate downloads, especially for just-generated items.
- ✅ Generation statuses: absent (not generated), generating, failed, ready.
- ✅ Retention/cleanup: reuse existing voiceover cache eviction as-is (no new policy).

## Up Next Queue (with History)
- ✅ Single list combining history, current, and upcoming.
- ⏳ Revisit history UX from scratch: how to present and interact with history vs upcoming (prior option set discarded).
- ✅ Actions: tap history item makes it current; removing current advances to next; removing upcoming reflows order.
- ✅ Insertion rules: “Play next” inserts at top of upcoming; “Add to end” appends. Auto-generated items append after manual ones.
- ✅ Auto-play toggle: when on, advance to next ready item automatically. Skip non-ready items and continue; log/indicate skips.
- ✅ Persistence: queue ordering, history, current item, progress, auto-play toggle persist across app relaunch.

## My Discoveries List (renamed from Discover tab)
- ✅ Mirrors existing My Discoveries content (ordering/metadata) without reordering controls.
- ✅ Actions:
  - Ready: tap plays in place; does **not** auto-switch tabs.
  - Absent: tap opens modal: “Creating an audio guide costs 1 credit” + current credit balance; Cancel/OK. OK triggers generation via edge function (edge handles credit deduction).
  - Failed: tap/overlay retry icon retries generation; transitions to generating state.
  - Swipe (light) adds to end of queue with feedback.
- ✅ No search/filters in this list.
- ✅ Credit balance is updated from edge function response (no local deduction logic).

## Credit & Generation Flow
- ✅ Absent state = no guide exists in backend; displayed ghosted. Tapping prompts credit modal; generation starts on confirm.
- ✅ No cancel of in-flight generation. Failed state uses a light warning color and retry affordance; retry returns to generating.
- ✅ Auto-generate setting (if enabled elsewhere) can create guides as new discoveries are captured; these appear in Up Next with generating state, then ready when done.

## Error Handling
- ✅ Playback errors: surface inline and allow retry; stop playback if unrecoverable.
- ✅ Generation failures: mark the item failed and allow retry.
- ✅ Fetch/prefetch errors: surface inline on the item; retry available; do not block rest of queue.
- ✅ Dismiss mini while error visible stops playback and hides mini.

## Navigation & Visibility
- ✅ Mini player visible on all screens where legacy voiceover controller appears; opens Audio Guides page on tap. Swiping back returns to prior screen.
- ✅ Audio Guides page retains hero↔mini collapse; mini sticks while browsing.

## Data Model
- ✅ Stable discovery IDs drive everything (My Discoveries rows, queue, cache keys). Avoid transient UUIDs. Do not re-fetch existing voiceovers already stored for a discovery; hydrate from cache/store when present.
- ✅ Persist per-discovery progress, queue state, toggle settings, and cached assets.

## Open Questions / Decisions Needed
- History UX: how to present and interact with history vs upcoming (fresh design pass).
- Visual separation: preferred layout for history vs current vs upcoming (chips, subheaders, dividers)?

## UI Requirements
- Hero/mini: collapse/expand pattern maintained; mini sticky while browsing; mini dismiss via gesture (not button). Dismissing while playing stops playback; when stopped, mini hides.
- Player display: show current position and total duration; expose state (ready/playing/paused/stopped); show playback speed options (0.75x/1.5x/2x).
- Queue visuals: current item clearly distinct; history visually separated from upcoming (design TBD in fresh pass).
- My Discoveries states: ready (normal), generating (ghosted + spinner + “Generating…”), absent (ghosted + “Create audio guide”), failed (warning tint + retry icon overlay), playing indicator when active.
- My Discoveries actions UI: absent tap opens credit modal (cost 1 credit + current balance, Cancel/OK); failed shows retry overlay; light swipe adds to queue tail with feedback; ready tap plays in place without tab switch.
- Error/feedback: playback errors via inline toast/banner; generation failures visible on item with retry; fetch/prefetch errors inline per item.
- Navigation: mini tap opens Audio Guides page; back gesture returns; gesture-based tab swipe remains (Up Next vs My Discoveries).
