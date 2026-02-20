# Audio Playback UX Plan

## Status: Design Discussion

Building on the streaming infrastructure (direct `Accept: audio/mpeg` path), this plan addresses how the UI communicates audio state and gives users proper playback controls across all surfaces.

---

## Problems to Fix

### P1: Confirm Screen Never Streams
`DiscoveryAudioControls` calls `requestVoiceover()` (non-streaming). The pill shows a spinner for the full 10-30s generation time, then jumps to "Play". It should use streaming and show "Play" after ~1-2s.

### P2: Audio Guides Row Shows "Generating" While Already Playing
`requestAndPlayStreaming()` starts playing in the mini player after ~1s, but the asset status stays `.processing` until the full stream completes + caches. The list row reads `assetStates[id].status` which is still `.processing`, so it shows spinner + "Generating..." while the user is already hearing that audio.

### P3: Generating New Audio Overwrites Current Playback
If the user is playing Discovery A and taps "Generate" on Discovery B from Audio Guides, `requestAndPlayStreaming()` immediately replaces the mini player with Discovery B (which is still buffering). Discovery A's playback is lost. The user didn't ask to stop listening — they asked to generate.

### P4: Mini Player Play/Pause Broken During Streaming
While streaming audio is playing, the play/pause button and skip controls don't work properly. The UI doesn't reflect the streaming playback state correctly.

### P5: No Way to Tell Streaming-Ready From Fully-Ready
The UI has only two states: "Generating..." (spinner) and "Play" (ready). There's no visual distinction between "we have enough to start playing but the stream is still loading" and "the full audio is cached and ready." The mini player, Audio Guides rows, and the confirm screen pill all need a distinct streaming-ready appearance.

---

## Design Decisions (Settled)

### D1: Remove Audio Generation Toasts
**Removed entirely.** No audio generation toasts anywhere. With streaming, audio is playable in ~1-2 seconds — a toast adds noise, not value.

When the user generates while something else is playing, the row state change (spinner → play icon with streaming indicator) is itself the notification. Freshly generated rows get a more colorful/prominent treatment to draw attention naturally (see Visual Design below).

### D2: Auto-Play Rule (All Surfaces)
**Simple rule:** If nothing is currently playing → auto-play. If something is playing → generate in background, don't interrupt.

This applies uniformly to all surfaces: confirm screen, Audio Guides page, retry on failure.

- **Nothing playing:** Generate + auto-play as soon as 16KB is buffered (~1-2s)
- **Something playing:** Generate in background. Row/pill transitions through states. User taps to play when they want to switch.

### D3: Mini Player + Confirm Screen Pill Coexistence
**No changes.** They coexist as they do today. They serve different purposes: the pill is contextual to the discovery being viewed, the mini player is the persistent global control.

### D4: Concurrent Stream Limit
Up to 3 concurrent voiceover streams. Additional requests queue on the client, same pattern as `DiscoverySessionManager`. Each stream generates independently in the background.

### D5: Credit Deduction — No Change
Keep optimistic deduction before the request. If it fails, refresh balance.

### D6: Tapping `.streamingReady` Row
Treat it identically to tapping a `.ready` row. If something is playing, stop it and play this one. Standard row-tap behavior.

### D7: Tapping `.processing` Row
Keep disabled. The 1-2 second wait for `.streamingReady` is negligible. No action on tap.

---

## New Asset State: `.streamingReady`

Add a state between `.processing` and `.ready`:

```
.none/.missing → .processing → .streamingReady → .ready
                                    ↑                 ↑
                              (16KB buffered)   (stream complete + cached)
```

| Status | Meaning | UI Shows |
|--------|---------|----------|
| `.none/.missing` | No voiceover exists | "Generate Audio" with sparkles icon |
| `.processing` | Request sent, no playable audio yet | Spinner + "Generating..." |
| `.streamingReady` | Enough data buffered to play, stream still loading | Play icon + "Play" (with streaming indicator) |
| `.ready` | Full audio cached locally | Play icon + "Play" (standard) |
| `.failed` | Generation failed | Retry icon |

### Visually Distinguishing `.streamingReady` from `.ready`

The UI should make it obvious that audio is playable but still loading. Ideas:

**Mini Player:**
- Progress ring shows a pulsing/animated loading indicator instead of the static progress arc
- Or: a subtle animated gradient sweep on the progress ring while streaming
- The +5s forward button is **disabled/ghosted** (no buffer ahead to seek into)
- The -5s back button works normally (buffered data behind the playhead)

**Audio Guides Row:**
- Thumbnail overlay: instead of spinner (generating) or play icon (ready), show a **play icon with a subtle loading ring** around it
- Status text: "Ready" instead of "Generating..." (or no text — just the playable icon)
- Full opacity (not the 0.5 opacity used for generating)

**Confirm Screen Pill (DiscoveryAudioControls):**
- Button icon: play icon (not spinner) — user can tap to play
- Button text: "Play" (not "Generating...")
- If playing: pause icon with a subtle streaming indicator (e.g., a thin animated line at the bottom of the pill)
- Button is **not disabled** — user can play/pause

**Common pattern:** Wherever we show a play icon for `.streamingReady`, add a subtle loading indicator (pulsing dot, thin progress bar, animated ring) that disappears when the state transitions to `.ready`.

---

## Seek Controls During Streaming

**Forward 5s (+5):**
- **Disabled/ghosted** while in `.streamingReady` state (no buffer ahead to seek into)
- Enabled once audio is fully `.ready`
- Alternative: enable if there's buffered data ahead of the current position, but this adds complexity and the user won't notice the difference for a 2-second stream

**Back 5s (-5):**
- Always enabled (there's always buffered data behind, or we're at the start)

**Scrubber/Progress bar:**
- For `.streamingReady`: show progress as normal but indicate the total duration is unknown (don't show remaining time, or show "..." for remaining)
- For `.ready`: full scrubbing available as today

---

## Unified Generation Method

Replace the two separate paths with a single approach:

### Current
```
requestVoiceover()           → non-streaming, no auto-play, fires toast
requestAndPlayStreaming()     → streaming, auto-plays, no toast
```

### Proposed
```
generateVoiceover(for:preferences:autoPlay:)
  → always streams
  → autoPlay controls whether mini player activates
  → updates assetStates progressively: .processing → .streamingReady → .ready
  → no toast (removed)
```

**Auto-play logic lives inside `generateVoiceover()`:** It checks `playbackState.isActive`. If something is playing → stream in background only. If idle → stream + auto-play.

**Call sites all pass `autoPlay: true`** — the method itself decides whether to actually start playback based on current state. No caller needs to know what's currently playing.

| Surface | Passes | Actual behavior |
|---------|--------|----------------|
| Confirm screen "Generate Audio" | `autoPlay: true` | Auto-plays if idle, background-only if playing |
| Audio Guides row | `autoPlay: true` | Auto-plays if idle, background-only if playing |
| Retry on failure | `autoPlay: true` | Auto-plays if idle, background-only if playing |

---

## State Flow by Scenario

### Scenario 1: Generate from Confirm Screen (Nothing Playing)
```
User taps "Generate Audio"
  ↓
Pill: [spinner] "Generating..."     (assetStatus = .processing)
  ↓ ~1-2s (16KB buffered)
Pill: [pause]   "Pause"             (assetStatus = .streamingReady, auto-play starts)
Mini player: appears with streaming-ready appearance (+5s disabled)
  ↓ user listens...
  ↓ stream completes in background
Pill: [pause]   "Pause"             (assetStatus = .ready, seamless transition)
Mini player: normal appearance (+5s enabled)
  ↓ user taps pause
Pill: [play]    "Play"              (standard playback controls)
```

### Scenario 2: Generate from Confirm Screen (Something Playing)
```
Discovery A playing in mini player
User taps "Generate Audio" on Discovery B's confirm screen
  ↓
Discovery A: continues playing in mini player
Pill: [spinner] "Generating..."     (assetStatus = .processing)
  ↓ ~1-2s (16KB buffered)
Pill: [play]    "Play"              (assetStatus = .streamingReady, NOT auto-played)
  ↓ stream completes
Pill: [play]    "Play"              (assetStatus = .ready)
  ↓ user taps Play
Discovery A: stops
Discovery B: starts playing
```

### Scenario 3: Generate from Audio Guides (Nothing Playing)
```
User taps row → confirms generation
  ↓
Row: [spinner overlay] "Generating..."   (assetStatus = .processing)
  ↓ ~1-2s
Row: [now playing indicator]              (auto-play started, mini player shows)
Mini player: streaming-ready appearance (+5s disabled)
  ↓ stream completes
Mini player: normal appearance (+5s enabled)
Row: normal "now playing" indicator
```

### Scenario 4: Generate from Audio Guides (Something Else Playing)
```
User is listening to Discovery A via mini player
User taps Discovery B row → confirms generation
  ↓
Discovery A: continues playing undisturbed
Discovery B row: [spinner overlay] "Generating..."   (assetStatus = .processing)
  ↓ ~1-2s
Discovery B row: [streaming-ready indicator]          (assetStatus = .streamingReady)
  ↓ stream completes
Discovery B row: [play icon] standard ready state     (assetStatus = .ready)
  ↓ user taps Discovery B
Discovery A: stops
Discovery B: starts playing
```

### Scenario 5: Generate and Navigate Away
```
User generates from any surface, then switches to Camera tab
  ↓
Generation continues in background
  ↓ ~1-2s
assetStatus → .streamingReady (no one is watching)
  ↓ stream completes
assetStatus → .ready
  ↓ user returns to Audio Guides or Discovery Detail
Row/pill shows "Play" — audio is ready
```

No toast. The row/pill state is the notification.

---

## Implementation Scope

### Must Change
1. **`VoiceoverPlaybackController`** — Merge `requestVoiceover()` and `requestAndPlayStreaming()` into unified `generateVoiceover(for:preferences:autoPlay:)`
2. **`DiscoveryVoiceoverModels`** — Add `.streamingReady` to `DiscoveryVoiceoverStatus`
3. **`DiscoveryAudioControls`** — Handle `.streamingReady` as playable state (not disabled)
4. **`AudioGuideRowView` + `AudioGuideRowStateProvider`** — Handle `.streamingReady` state visually
5. **`MiniPlayerView`** — Disable +5s during streaming, add streaming-ready visual indicator
6. **`VoiceoverPlaybackController.requestAndPlayStreaming()`** — Update asset to `.streamingReady` after 16KB buffer instead of waiting for stream completion
7. **Don't-interrupt logic** — When `autoPlay: true` but something is already playing, generate in background only (don't replace current playback)

### Must Remove
1. **`GenerationCompleteToast`** — Delete model
2. **`GenerationCompleteToastView`** — Delete view
3. **`AudioGuideCompletionToastOverlay`** — Delete overlay
4. **`UnifiedToastOverlay`** — Remove audio toast portion (keep discovery completion toast if it exists separately)
5. **`AudioServicesContainer`** — Remove `pendingGenerationToasts`, `onGenerationComplete`, toast-related methods
6. **`AudioGuidesViewModel`** — Remove toast-related callbacks

### Nice-to-Have (Later)
- Buffer progress bar in mini player showing how much audio is loaded
- Estimated remaining duration display during streaming
- Queue position indicator for queued generations (4th+ concurrent)

---

## Visual Design: Streaming-Ready State

The streaming-ready state needs to feel "alive but not distracting" — communicating that audio is playable but still loading. The design uses the brand gold color (`BrandColors.logo`) as an accent for freshly generated items.

### Mini Player — Streaming Indicator
- **Progress ring:** Animated indeterminate sweep in brand gold. Instead of the static progress arc (which requires knowing total duration), show a subtle rotating/pulsing ring segment. Once the stream completes and duration is known, this transitions smoothly to the standard progress arc.
- **+5s button:** Ghosted at 0.3 opacity, non-interactive. Re-enables when asset transitions to `.ready`.
- **-5s button:** Normal, always works.
- **Duration display:** Duration is only shown in the hero player, not the mini player. In the hero player during streaming: show elapsed time only (e.g., "0:12") with no total. When stream completes and duration is known, total appears (e.g., "0:12 / 1:24").

### Audio Guides Row — Streaming-Ready + Freshly Generated Treatment
When a row transitions from `.processing` → `.streamingReady`:
- **Thumbnail overlay:** Dark overlay lifts to full opacity. Play icon appears with a **thin animated ring** around it (brand gold, ~2pt stroke, rotating). This ring disappears when state becomes `.ready`.
- **Status text:** "Ready" in brand gold color (instead of the muted secondary text color used for "Generating..."). This draws the eye to freshly generated items.
- **Row border/highlight:** A subtle brand gold left-edge accent (3pt vertical bar on the leading edge of the row) that fades out after ~5 seconds or when the user taps the row. This makes freshly created items visually pop in the list without being obnoxious.
- **Opacity:** Full 1.0 (up from 0.5 during `.processing`).
- **Transition animation:** Spring animation on opacity change + the gold accent appearing.

When `.streamingReady` → `.ready`:
- The animated ring around the play icon stops and disappears.
- Status text changes from "Ready" (gold) to standard duration text (secondary color).
- The gold left-edge accent continues its fade-out if still visible.

### Confirm Screen Pill (DiscoveryAudioControls) — Streaming States
- **`.processing`:** Spinner in gold circle + "Generating..." — same as today but brief (~1-2s).
- **`.streamingReady` (not playing):** Play icon in gold circle + "Play" — tappable, not disabled. A subtle pulsing glow on the gold circle indicates streaming is still active.
- **`.streamingReady` (playing):** Pause icon in gold circle + "Pause" — the gold circle has a thin animated ring (same treatment as row thumbnail). This ring disappears when stream completes.
- **`.ready`:** Standard play/pause — no animation, no ring. Clean and static.

### Design Principle
The streaming-ready indicator is always **on the play/pause button itself** (animated ring on the gold circle). This is consistent across all surfaces: mini player progress ring, row thumbnail play icon ring, and confirm screen pill button ring. One visual language = "audio is playing/playable but still loading."
