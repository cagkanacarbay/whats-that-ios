# Feature #11: Voiceover Latency Optimization

## Status: Exploration (options not fully thought out)

---

## Current System

### How Voiceover Generation Works Today

The voiceover system is a sequential pipeline spanning three components:

**1. Discovery creation (ask-ai-v7 edge function)**
- User takes a photo, ask-ai-v7 streams AI-generated text via SSE
- Tokens arrive batched (~160 chars), flushed on sentence breaks
- After streaming completes: text parsed, image uploaded, discovery saved to DB
- `complete` SSE event sent to client with `discoveryId`
- ask-ai-v7 has no knowledge of voiceover generation

**2. Client triggers voiceover (iOS app)**
- `onDiscoveryCompleted` callback fires in `CreationFlowCoordinator`
- If `generateAudioGuide` is true, calls `playbackController.requestVoiceover(for: summary)`
- This makes a POST to the `generate-voiceover` edge function
- Users can also trigger voiceover generation later from the Audio Guides tab or discovery detail

**3. Voiceover generation (generate-voiceover edge function)**
- Authenticates user, checks rate limits
- Fetches voice options + discovery text from DB (parallelized as of Feb 2025)
- Calls `start_voiceover_request` RPC (creates DB row, charges 1 credit)
- Sends full discovery text to Fish Audio TTS API
- Fish Audio returns complete MP3 buffer
- If client sends `Accept: audio/mpeg`: returns MP3 bytes directly, uploads to Storage in background
- If old client: uploads to Storage first, returns JSON with signed URL

### Timing Breakdown (measured)

| Step | Duration | Notes |
|------|----------|-------|
| Auth + rate limit + validation | ~1-2s | Sequential DB calls |
| Fish Audio TTS generation | ~25-30s | Proportional to text length. This is the bottleneck. |
| Storage upload + response | ~0-3s | 0s with direct audio (new), 2-6s with old JSON path |
| **Total (new direct audio path)** | **~37s** | Down from ~44s before optimization |

### What We Already Optimized

1. **Eliminated double-transfer latency** — MP3 bytes returned directly to client instead of upload-to-Storage-then-download. Saved ~7s.
2. **Parallelized DB calls** — `fetchVoiceOptions()` and `fetchDiscoveryData()` now run via `Promise.all()`.

---

## The Problem

**Fish Audio TTS generation time is proportional to text length.** A full discovery description (~300 words across multiple sections) takes 25-30s. But Fish Audio generates short text fast:

| Text length | Approx. generation time |
|-------------|------------------------|
| 2 sentences (~50 words) | ~2s |
| 1 section (~100 words) | ~3-5s |
| Full description (~300 words) | ~25-30s |

The current system sends the entire description in one request and waits for the full MP3. The user cannot hear anything until all 300 words are generated.

---

## Goal

Get the user hearing audio in ~2-5 seconds instead of ~37 seconds by splitting the text into chunks and generating them in parallel/progressively.

---

## Options

> **Note:** These options have NOT been fully designed or validated. They represent initial thinking and need further investigation before committing to an approach.

### Option A: Client-Side Chunked Generation

The client splits the discovery text into chunks and makes parallel calls to `generate-voiceover`.

**How it would work:**
1. Client has the full discovery text (from streaming or from DB)
2. Client splits text into ~3 chunks:
   - Chunk 1: First 2 sentences (~50 words)
   - Chunk 2: Rest of section 1 (~100 words)
   - Chunk 3: Remaining sections (bulk)
3. Client fires parallel calls to `generate-voiceover` with each chunk
4. First call creates the DB row + charges 1 credit (existing flow)
5. Subsequent calls are "chunk-only" — just do TTS, no credit charge, no new DB row
6. Each call returns MP3 bytes via `Accept: audio/mpeg`
7. Client plays chunk 1 immediately (~2s), queues chunks 2-3
8. After all chunks arrive, client concatenates into single MP3 for cache/storage

**Expected timing:**
- Chunk 1 ready: ~2-3s (network + 2s Fish Audio)
- Chunk 2 ready: ~4-6s (runs in parallel)
- Chunk 3 ready: ~8-12s (runs in parallel)
- User hears audio at ~3s instead of ~37s

**What needs to change:**

*Edge function (generate-voiceover):*
- New "chunk mode" where client sends raw text directly instead of discovery_id
- Chunk mode skips: credit charging, DB row creation, discovery text fetching
- Chunk mode does: auth, rate limit, Fish Audio TTS, return bytes
- Need to decide: how does chunk mode authenticate that this is a valid request? (Must verify the user has an active voiceover row for this discovery)

*iOS client:*
- Text splitting logic (sentence detection, section detection)
- Parallel request orchestration
- Sequential chunk playback (queue-based: play chunk 1, when it ends play chunk 2, etc.)
- MP3 concatenation after all chunks arrive
- Fallback: if any chunk fails, fall back to single full-text request
- New state management for "partially ready" voiceovers

**Open questions:**
- How does the client split text reliably? The markdown structure (## headers) provides section boundaries, but sentence detection within sections needs a heuristic.
- MP3 concatenation: Fish Audio returns MP3 with consistent settings (bitrate, sample rate, channels), so raw byte concatenation should work — but needs validation. There may be MP3 frame alignment issues at chunk boundaries.
- Rate limiting: 3 concurrent calls per voiceover generation. Current rate limit is 5 requests/60s. Need to ensure chunk calls don't trigger rate limiting.
- How does the voiceover DB row track chunk state? Or do we just let the client manage chunk state locally?
- What happens if the user navigates away mid-generation? Are in-flight chunk requests cleaned up?

**Pros:**
- ask-ai-v7 stays completely unchanged
- generate-voiceover changes are contained (add chunk mode)
- Works for both auto-generation after discovery AND manual "play" later
- No coupling between discovery creation and voiceover generation
- Client already has the text, so splitting is straightforward

**Cons:**
- 3x the network round trips for each voiceover generation
- Client complexity: chunk splitting, parallel orchestration, sequential playback, concatenation
- Rate limiting needs adjustment (3 calls per generation instead of 1)
- Fish Audio concurrent request limit (15 on paid tier) burns through faster with chunked calls across multiple users
- MP3 concatenation on iOS needs implementation and testing
- Edge cases: what if chunk 2 fails but chunks 1 and 3 succeed?


### Option B: Server-Side Chunked Generation (in generate-voiceover)

The generate-voiceover edge function splits the text internally and makes parallel Fish Audio calls.

**How it would work:**
1. Client makes a single request to `generate-voiceover` (same as today)
2. Edge function fetches discovery text, splits into ~3 chunks
3. Fires 3 parallel Fish Audio calls
4. Returns first chunk immediately as soon as it's ready
5. Subsequent chunks... how? Options:
   a. Return all chunks as multipart response
   b. Return first chunk, upload rest to Storage, client fetches later
   c. Stream chunks back (but we're using HTTP request-response, not SSE)

**The problem with this approach:**
The HTTP request-response model doesn't naturally support "return the first chunk now, more later." Options:
- **Multipart response:** Unusual for mobile clients, adds parsing complexity
- **First chunk + polling:** Return chunk 1 immediately, client polls for chunks 2-3. Adds polling logic.
- **SSE from generate-voiceover:** Convert to streaming response. Major architectural change.

**Pros:**
- Single request from client (simple client-side)
- Server controls chunking strategy (can optimize without app update)
- No rate limiting concerns (server makes internal Fish calls)

**Cons:**
- Delivering progressive results over HTTP is awkward
- The edge function would need to hold multiple Fish Audio calls in flight
- Edge function runtime increases (all chunks must complete before response ends, unless using background tasks)
- The "return first chunk fast" benefit is lost if we wait for all chunks


### Option C: Hybrid — Server-Side Parallel Generation, Single Response

A simpler variant of Option B: the edge function splits text and generates chunks in parallel, but returns the concatenated result as a single MP3.

**How it would work:**
1. Client makes single request (same as today)
2. Edge function splits text into 3 chunks
3. Fires 3 Fish Audio calls in parallel via `Promise.all()`
4. Waits for all to complete
5. Concatenates MP3 buffers
6. Returns single MP3 response

**Expected timing:**
- All 3 Fish Audio calls run concurrently
- Total time = max(chunk1, chunk2, chunk3) instead of sum
- Longest chunk (~150 words) takes ~8-12s
- Total: ~12-15s instead of ~25-30s

**Pros:**
- No client changes (client sees same single MP3 response)
- Simple server-side change (parallel calls + concatenation)
- No progressive playback complexity
- No chunk state management
- Works with existing `Accept: audio/mpeg` optimization

**Cons:**
- User still waits ~12-15s for first audio (not the ~2-3s goal)
- MP3 concatenation on the server (Deno runtime, need to validate frame alignment)
- 3x Fish Audio API calls per generation (rate limit / cost consideration)
- Fish Audio failures on any chunk fail the whole request (or need partial recovery)


### Option D: Start Generation During Discovery Streaming (ask-ai-v7 integration)

Trigger voiceover generation from ask-ai-v7 as soon as enough text is available.

**How it would work:**
1. ask-ai-v7 streams AI text as usual
2. After first ~2 sentences accumulated, fire first Fish Audio call (non-blocking)
3. After first section, fire second call
4. After all text, fire final call
5. Send new SSE event types (`audio_chunk`) with signed URLs or inline data
6. Client receives audio chunks during the discovery stream itself

**Why we decided against this:**
- Couples discovery creation with voiceover generation (two separate concerns)
- Users also generate voiceovers independently (from Audio Guides tab, discovery detail), so we need a standalone voiceover flow anyway
- ask-ai-v7 is already complex; adding TTS orchestration increases risk
- Only saves ~2-3 seconds over client-side triggering (the network round-trip)
- Would need to duplicate the chunk logic for the standalone voiceover path

**This option is rejected** in favor of keeping voiceover generation independent.

---

## Comparison

| Aspect | A: Client Chunks | B: Server Progressive | C: Server Parallel | D: ask-ai Integration |
|--------|------------------|-----------------------|--------------------|-----------------------|
| Time to first audio | ~2-3s | ~2-3s (if streaming) | ~12-15s | ~2-3s |
| Client complexity | High | Low | None | Medium |
| Server complexity | Medium (chunk mode) | High (streaming) | Low (parallel + concat) | High |
| Network round trips | 3 per generation | 1 | 1 | 0 (embedded in stream) |
| Works for standalone play | Yes | Yes | Yes | No (needs separate path) |
| Fish Audio calls per gen | 3 | 3 | 3 | 3 |
| Requires app update | Yes | No | No | Yes |
| **Rejected?** | No | Awkward | No | **Yes** |

---

## Fish Audio Constraints

- **Concurrent request limit:** 15 on paid tier. With chunked generation (3 calls per voiceover), can support ~5 concurrent users. Need graceful degradation.
- **Rate limits:** Free: 100 req/min, Paid: 500+ req/min. Chunked generation 3x the request volume.
- **Short text handling:** Excellent. ~150ms first-chunk latency, <2s for ~100 words.
- **MP3 consistency:** Fish Audio returns MP3 with consistent bitrate/sample rate/channels across calls with the same voice model. Raw concatenation likely works but needs validation.

---

## Graceful Failure Strategy

Regardless of which option we choose, chunked generation must fail gracefully:

1. **If a chunk call fails:** Fall back to generating the full text in a single request (existing path). Don't fail the whole voiceover.
2. **If Fish Audio rate limits us (429):** Queue and retry with backoff, or fall back to single request.
3. **If MP3 concatenation produces artifacts:** Detect and fall back to single-request generation.
4. **If concurrent request limit is reached:** The chunks should be batched (e.g., 2 at a time instead of all 3), not all fired simultaneously.

---

## Next Steps

1. Validate MP3 concatenation works with Fish Audio output (test manually: generate 2 short clips, concatenate bytes, verify playback)
2. Decide between Option A (client chunks) and Option C (server parallel) — or a combination
3. If Option A: design the chunk mode API contract for generate-voiceover
4. If Option C: prototype parallel Fish Audio calls + concatenation in the edge function
5. Measure actual Fish Audio latency for different text lengths to validate the timing assumptions
