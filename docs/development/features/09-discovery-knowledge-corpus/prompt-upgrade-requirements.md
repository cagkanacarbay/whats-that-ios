# Prompt Upgrade Requirements — v0.9.0

Requirements for upgrading the system prompt based on the depth analysis. These are the concrete tasks needed to implement the changes described in `system-prompt-depth-analysis.md`.

## Guiding Principle

The problem is **shallow breadth** — name-dropping and moving on. The fix is NOT forcing single-topic responses. It's ensuring that whatever we mention gets developed. Both single-story deep dives and multi-aspect explorations are valid, as long as each topic gets sufficient attention.

---

## REQ-1: Remove "Touch Lightly" Language (Priority 1)

**What:** Rewrite Lines 73 and 87 of the system prompt to remove "while touching others only when valuable" and "optionally touch lightly upon other lenses."

**Replace with:** Guidance that says Engage sections should develop their content with real detail — if you mention a person, tell their story; if you mention an event, explain what happened.

**Why:** These phrases are the root permission slip for name-dropping. Removing them is the single highest-impact change.

---

## REQ-2: Add Name-Drop Ban (Priority 1)

**What:** Add to DO NOT / AVOID section: "Name-drop and move on" ban with the name-drop test ("Am I going to spend at least 2-3 sentences developing this?").

**Include:** The ❌/✓ examples from the depth analysis.

---

## REQ-3: Add Undeveloped Mentions Pattern Ban (Priority 1)

**What:** Add to Pattern Bans: "Undeveloped mentions" — introducing a person, battle, event, or institution and moving on in 1-2 sentences.

**Include:** Evidence references (#183, #189, #196).

---

## REQ-4: Add Unsupported Superlatives Banned Phrase (Priority 1)

**What:** Add to Banned Phrases: "Unsupported superlatives" — never write "famous for," "legendary," "one of the greatest" etc. unless immediately followed by concrete supporting detail.

**Include:** ❌/✓ examples.

---

## REQ-5: Add Development Check to Pre-Flight (Priority 1)

**What:** Add to Pre-Flight Checklist: "Development check — every person named, every event mentioned, and every institution referenced is developed with at least 2-3 sentences of substance."

---

## REQ-6: Add Development Criterion to Quality Bar (Priority 1)

**What:** Add to Quality Bar: "The discovery develops its content with real knowledge rather than name-dropping and moving on."

---

## REQ-6b: Add Word Budget Distribution (Priority 1)

**What:** Add to STYLE FOR THE EAR section, after the existing 260-330 word count guidance:

> **Word budget distribution:**
> - **Mode A (single-story):** Spend at least 70% of your word budget developing your primary thread. The remaining words cover identification and the optional flip. Can go up to 100% on the primary thread.
> - **Mode B (multi-aspect):** Cover up to 3-4 topics. Each topic must get enough development to convey real knowledge — at least 2-3 sentences of substance per topic. No undeveloped mentions.

**Why:** Gives concrete guidance that prevents the worst pattern (5+ topics at one sentence each) while allowing both response modes.

---

## REQ-7: Rewrite Lens Playbook Examples (Priority 2)

**What:** Replace all lens playbook examples (currently 21 across 4 lenses) with examples that show VARIETY of response types.

**Requirements:**
- Each lens should show at least two different response approaches (single-story deep dive AND multi-aspect exploration)
- Replace abstract task descriptions ("describe the blade's shape, explain medieval steel production") with real response-quality examples
- Use actual good discoveries from the database as templates where possible (#191, #182, #199, #219, #193 are good candidates)
- Show the model it has OPTIONS, not a formula
- No image-observation flips (don't suggest fabricating details from image inspection like "the wear suggests a right-handed fighter")

**Action required first:** Query the database for the best discoveries across each lens type. Pull the actual response text. Use these as the basis for new examples, refined as needed for clarity and conciseness.

**Specific issues in current examples:**
- All 5 Objects examples use identical structure: describe → explain how → broader context
- Ideas examples are better (some show depth) but still follow task-list format
- People examples have more variety (Frida Kahlo, Durbar Hall, Varanasi aarti are decent)
- Physical examples are naturally good because sensory experience resists breadth

---

## REQ-8: Rewrite Cold Start Examples (Priority 3)

**What:** Replace the cold start examples (Lines 370-378) which are currently task lists (identify → explain → tell → flip).

**Requirements:**
- Replace with real response-quality examples, or at minimum guidance that allows both modes
- Don't prescribe "do only one thing" and don't prescribe "do four things"
- Show: if the subject has one rich story, tell that story; if it's broad, cover aspects but develop each
- Either way: no name-dropping

**Action required first:** Same database query as REQ-7 — find good cold-start discoveries that show both approaches.

---

## REQ-9: Refine Zoom-Out Criteria (Priority 3)

**What:** Rewrite Line 95 to change zoom-out criteria from "plausibly connected" to "when specific content is narrow and zooming out would provide a richer, more specific response."

**Requirements:**
- Remove the parenthetical list of generic categories (Middle Ages nobles, Edo-period merchants, etc.)
- Add guidance: zoom-out should land on a SPECIFIC story or fact, not a generic description of an era
- Zoom-out should make the response MORE specific, not less

---

## REQ-10: Remove "Sideways Angles" Language (Priority 3)

**What:**
- Line 96: Cut "or sideways" from "Deeper or sideways angles can appear later"
- Line 382: Remove "switch lens while building on earlier content" and "different angle" from the multi-photo strategies. Keep "zoom in on one previously mentioned element."

---

## REQ-11: Make Flip Optional (Priority 3)

**What:** Update flip guidance so it's optional rather than required.

**Requirements:**
- On cold starts, generally include one
- On subsequent photos, skip if staying in primary lens is better
- When included, keep it short (a coda, not a full section)
- Flip must stay on same subject — perspective change, not topic change
- Flip should use genuine knowledge-based connections, NOT observations fabricated from the image

---

## Open Task: Find Good Real Examples from Database

**Blocking:** REQ-7, REQ-8

**What:** Query the discovery database for the best responses across each lens type. We need:
- 2-3 strong Objects lens responses showing different approaches
- 2-3 strong Ideas lens responses showing different approaches
- 2-3 strong People lens responses showing different approaches
- Physical lens examples are already good, may need less work
- Good cold-start responses (both single-story and multi-aspect)
- Good zoom-out examples (where zoom-out lands on something specific and vivid)

**Source:** Use the discoveries from the audit that scored well (#182, #191, #193, #199, #219) plus search for others in the broader database.

**Purpose:** These become the new lens playbook examples, replacing the abstract task descriptions with real response-quality text.

---

## What NOT to Do

These were considered and rejected. Do not implement:

- **Hook must come from the thread you develop** — over-constrains hook selection
- **Up to one topic per discovery** — 3-4 topics are fine if developed
- **Attract hook framing instructions** — existing hook guidance is good enough
- **Breadth-over-depth ban** — the enemy is SHALLOW breadth, not breadth itself. Multi-aspect done well is great.
