# System Prompt v0.8.0 — Depth Analysis & Upgrade Strategy

## The Problem

An audit of the 25 most recent dev discoveries found that **every single one** exhibits a "name-drop and move on" pattern: the narrative introduces an interesting person, event, idea, or cultural practice, mentions it in 1-2 sentences, and then skips to something else entirely.

- 4/25 scored **severe** (museum placard energy)
- 13/25 scored **moderate** (multiple interesting threads opened and abandoned)
- 8/25 scored **minor** (mostly focused, occasional drops)
- 0/25 were clean

**Average severity: 1.9 / 3.** This is structural, not occasional.

### Why It Happens

The prompt currently pulls in five directions at once within 260-330 words:

1. **Attract** (first H2) — hook with a sharp fact
2. **Engage** (middle H2s) — "deepen that lens while touching others"
3. **Flip** (final H2) — switch to a different IPOP dimension
4. **Cold start "obvious first" rule** — cover the most obvious identity
5. **Show don't tell** — each fact needs concrete detail, not labels

The result: ~60-80 words per section, spread across 3-5 topics. Every topic gets mentioned; none gets developed. The narrative reads like a confident tour guide speed-walking through a museum — pointing at things and saying "that's interesting" without stopping.

### What We Want Instead

The user listens to one discovery and thinks: *"That's fascinating — tell me more."* They take another photo. We pick up where we left off and go deeper. Then another photo, another layer. Each discovery is satisfying on its own but creates a pull toward more.

This means:
- **Each discovery goes deep on ONE thread** — not five shallow ones
- **Other interesting threads get planted as breadcrumbs** — tantalizing 1-sentence hints woven into the narrative
- **Consecutive photos build a layered story** — breadcrumbs from discovery 1 become the deep thread of discovery 2
- **The flip section stays** — it's the final H2, a different IPOP angle on the same subject (not a new topic)

---

## Section-by-Section Analysis

### ROLE (Lines 19-21) — No change needed
The role description is solid. "Specific, story-driven, and engaging" already implies depth.

### DELIVERABLES (Lines 23-25) — No change needed
Format is fine.

### INPUT SIGNALS (Lines 27-33) — No change needed
All signals are well-defined.

### IMAGE SOURCE & NARRATIVE STANCE (Lines 35-39) — No change needed
This section works well and was a good addition.

### IDENTIFICATION STRATEGY (Lines 41-46) — No change needed
"Favor specific over generic" is the right instinct.

### IPOP OVERVIEW (Lines 48-66) — No change needed
The theory section is fine as reference material.

### IPOP IN WHAT'S THAT (Lines 68-75) — NEEDS CHANGE

**Current problem (Line 73):**
> "Engage (middle sections deepen that lens **while touching others only when valuable**)"

This "touching others" language is the root permission slip for breadth. The middle sections should **stay on the primary thread**, not branch to other lenses. Other lenses should only appear if they organically serve the primary thread's story.

**Proposed direction:**
Rewrite to emphasize that Attract + Engage sections all serve ONE thread. The Engage sections go *deeper* into the same story — not wider into adjacent topics. The flip is the only deliberate lens change.

### SPECIAL CASES (Lines 77-82) — No change needed

### PER-DISCOVERY IPOP BEHAVIOR (Lines 84-90) — NEEDS SIGNIFICANT CHANGE

**Current (Line 87):**
> "middle sections (Engage) deepen that lens and optionally touch lightly upon other lenses"

This is the same "touching lightly" permission that leads to the name-drop pattern. "Touching lightly" on a person means naming them without telling their story. "Touching lightly" on an event means mentioning it without explaining what happened.

**Proposed direction:**
Replace the Attract/Engage/Flip structure description with a "One Thread Deep" model:
- **Attract (H2 #1):** Hook with the sharpest fact from the primary thread. Name the subject.
- **Engage (H2 #2-3, possibly #4):** Develop the SAME thread deeper. Tell the story. Give the details. Stay with it.
- **Flip (final H2):** A different IPOP lens on the SAME subject — not a new topic. This is a perspective shift, not a topic shift.

The key phrase should be: **"Stay with your thread. Develop it. If you mention something, earn it with at least 2-3 sentences of real substance."**

### LENS PLAYBOOK (Lines 92-210) — NEEDS ADJUSTMENT

**Current problem:**
The examples in each lens playbook show 3 bullet points per discovery, each covering a different sub-topic. This models breadth:
- Longsword example: bullet 1 (blade shape), bullet 2 (steel production), bullet 3 (maintenance)
- Frida Kahlo example: bullet 1 (specific moment), bullet 2 (painting elements), bullet 3 (life arc)

The Frida Kahlo example is actually closer to what we want — it's one thread (Frida's personal story) developed across three angles. The longsword example is three separate mini-topics.

**Proposed direction:**
Revise the examples to show ONE thread developed across 3 bullets, with 1 breadcrumb hint. For example:

Longsword (Objects primary):
- Bullet 1: Describe the visible blade — shape, fuller, crossguard. Explain how the fuller reduces weight without weakening the blade. A smith would fold the steel dozens of times.
- Bullet 2: This specific style of crossguard dates to roughly 1250. Knights needed a wider guard as fighting shifted from horseback to foot combat. The pommel counterbalances the blade — hold your hand out flat and imagine the weight.
- Bullet 3 (breadcrumb woven in): The scabbard is missing, but a sword like this would have been someone's most expensive possession — worth more than a house.
- Flip: Who carried it — a knight, a town militia leader? The wear pattern on the grip suggests a right-handed fighter who actually used this blade.

vs. the current version which jumps: blade shape → steel production → maintenance. Three separate topics, none developed.

### FICTIONAL VIGNETTES (Lines 212-224) — No change needed

### WRITING THE FIRST H2 / ATTRACT HOOK (Lines 226-267) — MINOR TWEAK

**Current state:** This section is excellent. The good/weak examples are among the best parts of the prompt.

**One addition needed:**
The hook should come from the primary thread — the one thing the discovery will develop. Currently there's no explicit connection between "deliver something immediately" and "this should be the thread you're about to spend 260 words on." The hook can accidentally promise one thread and then the narrative develops another.

**Proposed addition:**
> "The hook must come from the thread you intend to develop. If your strongest hook is about a person, the discovery should be about that person. Do not hook with an event and then spend the body talking about architecture."

### CONTEXT-DRIVEN HEURISTICS (Lines 269-394) — NEEDS EXPANSION

This section handles connections between discoveries. It's thorough on when to connect and when not to. But it's missing the **progression model** — how consecutive photos of the same subject build a deepening story.

**Current "Same subject, multiple photos" (Lines 380-384):**
> "Strategies: keep same primary lens but go deeper/different angle; switch lens while building on earlier content; zoom in on one previously mentioned element."

This is too vague. "Zoom in on one previously mentioned element" is the right idea but needs to be explicit and tied to the breadcrumb system.

**Proposed expansion — "BUILDING DEPTH ACROSS DISCOVERIES":**

This is the biggest new section. It should describe the progression model:

**Photo 1 (cold start):**
- Go deep on the most obvious, strongest thread
- Weave in 1-2 breadcrumbs — single sentences that hint at other fascinating angles without developing them
- Breadcrumbs should make the listener think "wait, what about...?"

**Photo 2 (same subject):**
- Check `recentFullDiscoveries` for breadcrumbs planted in photo 1
- Pick up one breadcrumb as the new deep thread
- Can plant new breadcrumbs from the current angle
- Build on photo 1's context — the user already knows the basics, go deeper

**Photo 3+ (same subject):**
- Continue the pattern: previous breadcrumbs become deep threads
- Can return to the original thread from a completely different angle
- At this point, the user has a rich, layered understanding built across multiple discoveries

**Example:**
> Subject: Doge's Palace, Venice
>
> **Photo 1** (exterior): Deep thread = how the palace's pink-and-white facade was designed to intimidate foreign ambassadors arriving by sea. Breadcrumb: "Behind these walls, the Council of Ten kept loaded firearms in a secret armory."
>
> **Photo 2** (secret armory): Deep thread = picks up the breadcrumb. The Council of Ten maintained this cache to prevent noble families from building private armies. Develops: who the Ten were, how they operated, what they feared. Breadcrumb: "One floor above, the Great Council chamber held two thousand nobles who elected the Doge — with one portrait covered by a black veil."
>
> **Photo 3** (Great Council chamber): Deep thread = the black veil. Marin Faliero tried to seize total power in 1355. Develops: the plot, the betrayal, the execution, and why Venice kept the black mark visible for 600 years as a warning. Breadcrumb: "Above it all hangs Tintoretto's Paradise — so large he needed a warehouse to paint it."

Each discovery is complete and satisfying alone. Together they build a layered story that rewards the user for exploring.

### COLD START HEURISTICS (Lines 363-378) — NEEDS TWEAK

**Current:**
The cold start examples show 3 different topics per discovery (identify scene, explain evolution, tell story, flip with object note). This models breadth.

**Proposed direction:**
Rewrite examples to show ONE deep thread + breadcrumb + flip:

> Example (mid-sized city square in Europe):
> - Primary lens: **Ideas** or **People**. Flip lens: **Objects**.
> - **Deep thread**: Pick the single strongest story about this square — the execution that happened here, the revolution that started here, the market that defined the town's economy for 400 years.
> - **Develop it**: Who was involved? What happened? What changed because of it?
> - **Breadcrumb**: One sentence hinting at another angle ("The fountain at the center has its own story — the sculptor hid a face in the stonework.")
> - **Flip**: An Objects note on a single visible element — the cobblestones, the sundial, the coat of arms above a doorway.

### DO NOT / AVOID (Lines 405-422) — NEEDS NEW BANNED PATTERN

**Add: "Name-drop and move on" pattern ban**

This should be as prominent as the scaffolding verb ban. Proposed text:

> **Name-drop and move on** — Mentioning a person, event, institution, or cultural practice in 1-2 sentences and then skipping to a different topic. If you name something, develop it or leave it out entirely.
>
> THE NAME-DROP TEST: Before mentioning any person, event, or institution by name, ask: "Am I going to spend at least 2-3 sentences developing this?" If not, either (a) develop it, (b) cut it, or (c) make it a deliberate breadcrumb — a single tantalizing sentence designed to make the listener want to take another photo.
>
> ❌ "They were famous for winning battles against much larger armies." (Which battles? What armies? What happened?)
> ❌ "Chomętowski was a powerful leader in the early seventeen hundreds." (Doing what? Why does he matter?)
> ❌ "Within twenty years of his death, Venice would fall to Napoleon." (How? Why? What happened?)
> ❌ "The Council of Ten kept these firearms loaded and ready." (Who are the Council of Ten?)
>
> ✓ "At the Battle of Kircholm in 1605, three thousand hussars charged eleven thousand Swedish infantry. The Swedes broke in under half an hour."
> ✓ "Chomętowski earned this mace after holding the eastern border against Ottoman raids for fifteen years."
> ✓ [As breadcrumb] "This painting was finished just twenty years before Napoleon dissolved the Republic forever." (Tantalizing — user wants to know more. That's the next discovery.)

### PATTERN BANS (Lines 414-422) — ADD TO EXISTING LIST

Add as a new bullet after "Ignoring the obvious subject":

> **Undeveloped mentions** — Introducing a person, battle, event, or institution and moving on in 1-2 sentences. The worst form is making a large claim ("famous for," "legendary," "one of the greatest," "changed the course of") without a single supporting detail. If something is worth mentioning, it is worth developing. If it is not worth developing in this discovery, either cut it or reduce it to a deliberate breadcrumb.

### BANNED PHRASES (Lines 424-448) — MINOR ADDITION

Add a new item:

> 6. **Unsupported superlatives** — Never write "famous for," "legendary," "one of the greatest," "changed the course of history," or "shaped the future of" unless you immediately follow with at least one concrete supporting detail (a name, a date, a number, a specific outcome). The superlative must be earned by the next sentence.
>    - ❌ "They were famous for winning battles against much larger armies."
>    - ✓ "At Kircholm, three thousand of them broke eleven thousand Swedes in thirty minutes."

### STYLE FOR THE EAR (Lines 503-507) — POSSIBLE WORD COUNT CHANGE

**Current:** 260-330 words.

**Analysis:** The word count isn't the problem — discoveries that score 1/3 (Stoves of Rundāle, Winged Guardian) achieve depth within 300 words. The issue is how those words are distributed.

**Recommendation:** Keep 260-330 but add distribution guidance:

> Spend at least 70% of your word budget (roughly 180-230 words) developing your primary thread. The remaining words cover identification, breadcrumbs (1-2 sentences max), and the flip section.

### PRE-FLIGHT CHECKLIST (Lines 535-542) — ADD DEPTH CHECK

Add:

> - **Depth check**: Every person named, every event mentioned, and every institution referenced is developed with at least 2-3 sentences of substance — OR it is a deliberate breadcrumb (a single tantalizing sentence). No undeveloped mentions.
> - **Thread coherence**: The Attract hook, Engage sections, and primary thread all tell ONE story, not three loosely related ones.

### QUALITY BAR (Lines 544-549) — ADD DEPTH CRITERION

Add:

> - The discovery develops one thread with real depth rather than surveying multiple threads at surface level. The listener finishes feeling they learned something substantial, not that they heard a list of interesting-sounding things.

---

## The New Concept: BREADCRUMBS

This is the most important new addition to the prompt. It needs its own section, placed after PER-DISCOVERY IPOP BEHAVIOR and before the LENS PLAYBOOK.

### Proposed Section: "BREADCRUMBS — PLANTING DEPTH FOR LATER"

> A **breadcrumb** is a single sentence woven into the narrative that hints at a fascinating angle you are deliberately NOT developing in this discovery. Its purpose is to create curiosity — to make the listener think "wait, tell me more about that" — so they take another photo.
>
> **Rules for breadcrumbs:**
> - Maximum 1-2 per discovery. More than that and the narrative feels scattered.
> - A breadcrumb is ONE sentence. Not a paragraph. Not two sentences.
> - It must be woven naturally into the main narrative — not tacked on as a separate thought.
> - It should hint at something genuinely interesting that you COULD develop if the user returns.
> - It should NOT feel like a cliffhanger or a sales pitch. It should feel like a guide casually mentioning something fascinating in passing.
>
> **Good breadcrumbs** (natural, tantalizing, one sentence):
> - "The sculptor who carved this was later exiled for insulting the king."
> - "Behind that door, the Council of Ten kept a loaded armory — but that is another story."
> - "This painting was finished just twenty years before Napoleon dissolved the Republic forever."
> - "The real mystery is why the builders carved a face into the underside of the arch where nobody could see it."
>
> **Bad breadcrumbs** (cliffhangers, sales pitches, or too much):
> - "But the most fascinating part of this building's history is what happened next..." (cliffhanger)
> - "There is so much more to discover about this place!" (sales pitch)
> - "The sculptor was exiled for insulting the king. He fled to Rome where he built three churches and married a countess." (too much — that's development, not a breadcrumb)
>
> **When the user returns:**
> If `recentFullDiscoveries` contains a breadcrumb about the current subject, you should pick it up as your primary thread. The user came back because they were curious — reward that curiosity with depth.

---

## Summary of All Proposed Changes

### New sections to add:
1. **"ONE THREAD DEEP" principle** — inserted after IPOP IN WHAT'S THAT, before SPECIAL CASES
2. **"BREADCRUMBS" section** — after PER-DISCOVERY IPOP BEHAVIOR, before LENS PLAYBOOK
3. **"BUILDING DEPTH ACROSS DISCOVERIES"** — expands the current "Same subject, multiple photos" subsection in CONTEXT-DRIVEN HEURISTICS

### Sections to modify:
4. **IPOP IN WHAT'S THAT (Line 73)** — remove "touching others" permission; emphasize single-thread depth
5. **PER-DISCOVERY IPOP BEHAVIOR (Line 87)** — rewrite Engage description to "develop the same thread deeper"
6. **LENS PLAYBOOK examples** — revise to show one-thread-deep + breadcrumb pattern
7. **ATTRACT HOOK section** — add "hook must come from the thread you develop"
8. **Cold start examples** — rewrite to show one deep thread + breadcrumb + flip
9. **Same subject, multiple photos** — expand into the full progression model
10. **DO NOT / AVOID** — add "Name-drop and move on" pattern ban
11. **Pattern bans** — add "Undeveloped mentions" ban
12. **BANNED PHRASES** — add unsupported superlatives ban
13. **STYLE FOR THE EAR** — add word budget distribution (70% on primary thread)
14. **PRE-FLIGHT CHECKLIST** — add depth check and thread coherence check
15. **QUALITY BAR** — add depth criterion

### Sections that stay unchanged:
- ROLE, DELIVERABLES, INPUT SIGNALS, IMAGE SOURCE, IDENTIFICATION STRATEGY, IPOP OVERVIEW, SPECIAL CASES, FICTIONAL VIGNETTES, SHOW DON'T CATEGORIZE, UNPACK ABSTRACT NOUNS, THE SCAFFOLDING TEST, OUTPUT FORMAT

---

## The Flip Section — Why It Still Works

The user asked about the flip and it should stay. Here's why it's compatible with the one-thread-deep approach:

The flip is not a topic change — it's a **perspective change on the same subject**. A discovery about the Battle of Grunwald (Ideas primary) can flip to Physical: "Stand where the Lithuanian cavalry would have assembled. The ground slopes gently toward the tree line. Imagine the sound of fifteen thousand horses beginning to move." That's still Grunwald — just experienced through the body instead of the mind.

**The flip section (final H2) should:**
- Stay on the same subject as the rest of the discovery
- Apply a different IPOP lens to that subject
- Be 40-60 words (short — it's a coda, not a new chapter)
- Feel like a surprise angle, not a new topic

**What the flip should NOT do:**
- Introduce an entirely new topic ("And nearby, there's also a church worth seeing")
- Become a second deep thread
- Repeat information from the Engage sections in different words

---

## Before/After Example

### BEFORE (current style — breadth, name-drop and skip):

> ## The knights who terrified Europe
> The Winged Hussars were the elite cavalry of the Polish-Lithuanian Commonwealth. They were famous for winning battles against much larger armies.
>
> ## Born for battle
> Joining this unit was a birthright for the wealthiest families. Each hussar funded his own equipment from the family fortune. The cost of a full set of hussar armor equaled several years of a peasant's wages. They were the celebrities of their day. They wore their armor at weddings and royal funerals.
>
> ## Wings of terror
> The distinctive feathered wings attached to the back of the armor created a terrifying sound at full gallop. The rush of air through the feathers produced a loud whistling noise. This combined noise made it sound like a much larger force was attacking. It frightened enemy horses and confused soldiers.
>
> ## Steel and silk
> Notice the leopard skin draped over the armor. These skins came from Africa through Mediterranean trade routes. A hussar wore this over polished plate armor. You can almost feel the vibration and wind that would follow such a massive charge.

**Problems:** "Famous for winning battles" (which battles?). "Celebrities of their day" (how?). Leopard skins "from Africa through trade routes" (one sentence, no development). Four mini-topics (reputation, cost, wings, material), none developed.

### AFTER (one thread deep + breadcrumb):

> ## Thirty minutes at Kircholm
> In September 1605, three thousand Winged Hussars faced eleven thousand Swedish infantry in a field near modern-day Latvia. The Swedish commander assumed his numbers would win. He was wrong.
>
> ## The charge that ended it
> The hussars waited until the Swedes advanced across open ground, stretched thin and tired. Then the charge hit. A hussar in full armor on a heavy horse weighed over half a ton. Three thousand of them moving at a gallop covered the field in under a minute. The Swedish lines did not bend. They shattered. The entire battle lasted less than thirty minutes. Sweden lost over eight thousand men. The hussars lost fewer than a hundred.
>
> ## Why the numbers worked
> Each hussar bought his own armor and horse. A full kit cost more than a peasant earned in a lifetime. These were the sons of the richest families in the Commonwealth, and they trained from childhood. The long lance, called a kopia, was hollow to reduce weight. At impact it exploded into splinters, and the hussar drew his saber without slowing down.
>
> ## The sound before the storm
> Look at the feathered wings attached to the back plate. At full gallop, air rushing through those feathers made a high whistling roar. Swedish soldiers at Kircholm later wrote that it sounded like a thousand birds of prey diving at once. The terror arrived before the cavalry did.

**What changed:** One thread (Kircholm) developed across the full discovery. The listener learns ONE battle in vivid detail and finishes understanding *why* the hussars were legendary — not just being told they were. The leopard skin, celebrity culture, and family wealth are untouched — those are future breadcrumbs or future discoveries.

---

## Implementation Priority

1. **Highest impact:** Add "One Thread Deep" principle + name-drop ban + depth pre-flight check. These three changes directly address the core problem.
2. **Second priority:** Add breadcrumbs section + expand "Same subject, multiple photos" into the progression model. These create the pull loop (curiosity → photo → depth → more curiosity).
3. **Third priority:** Revise lens playbook examples + cold start examples to model the new pattern. Examples are how the model learns style — if the examples show breadth, the output will be broad.
4. **Lowest priority but still valuable:** Word budget distribution guidance, unsupported superlatives ban. These are polish.
