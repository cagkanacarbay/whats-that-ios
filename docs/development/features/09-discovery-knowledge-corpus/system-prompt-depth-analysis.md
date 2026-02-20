# System Prompt v0.8.0 — Depth Analysis & Upgrade Strategy

## The Problem

An audit of the 25 most recent dev discoveries (IDs 181-221) found that the vast majority exhibit a "name-drop and move on" pattern: the narrative introduces an interesting person, event, idea, or cultural practice, mentions it in 1-2 sentences, and then skips to something else entirely.

- 4/25 scored **severe** (museum placard energy — multiple objects or topics listed with no development)
- 12/25 scored **moderate** (multiple interesting threads opened and abandoned)
- 9/25 scored **minor** (mostly focused, occasional drops)
- 0/25 were clean

**Average severity: 1.8 / 3.** This is structural, not occasional.

### Why It Happens

The Attract/Engage/Flip structure, the cold start rule, and the show-don't-tell principle are all good ideas that should work together. But the prompt currently lets them pull apart instead of reinforcing each other:

- **Attract** hooks with a sharp fact — good. But there's no instruction that the Engage sections should *develop that same story*. The model interprets Engage as "now talk about something else."
- **Engage** says "deepen that lens while touching others" — the "touching others" becomes the dominant behavior. Each Engage section introduces a new mini-topic instead of developing the story.
- **Flip** is a perspective change on the same subject — good in theory. But when the middle sections already scattered across 3 topics, the flip just adds topic #4.
- **Cold start** determines WHAT the subject should be (the obvious identity). This is about subject selection, not about adding more content.
- **Show don't tell** is about HOW we write — concrete detail, not abstract labels. It shouldn't create pressure to cover more topics.

### What We Want Instead

The core issue is **not breadth vs depth.** The issue is **shallow breadth** — name-dropping interesting things without giving them enough space to develop.

Both of these are good:

**Mode A — Single-story deep dive.** The photo is a door to one specific story. We tell that story fully. Good for: rich historical events, specific people, moments where the photo directly depicts a particular event.
- Example: A painting of Jan Sobieski at the Battle of Vienna → just tell the story of that battle. Pre-war conditions, the siege, Sobieski's arrival, the outcome. All sections develop parts of one story.

**Mode B — Multi-aspect exploration.** The subject is broad — a palace, a church, a square. We cover several aspects, but give each one sufficient attention to develop. Not one sentence per aspect, but a few sentences that give the listener a real sense of each.
- Example: Venice's Secret Arsenal (#191) — covers state monopoly on violence across four angles. Each section develops its angle. The thread holds.
- Example: Basilica of St. James (#182) — covers St. James iconography, the specific technique of this relief, and a legend connected to this church. Different aspects, but each one gets enough room.

The key insight from discoveries that work: **whatever you mention, give it enough space to develop.** Don't name-drop. 3-5 topics are fine IF each gets real attention. But a response that goes truly deep on one story can be more powerful. We want the prompt to enable both modes, and let the subject matter guide which is right.

What makes a discovery feel good:
- The listener finishes feeling they learned something real, not that they heard a list of interesting-sounding things
- Each topic mentioned gets enough space to develop — a few sentences of real knowledge, not a one-liner and move on
- Consecutive photos build layers — the first photo covers the obvious, subsequent photos can go deeper on one thread

---

## Evidence: Problematic Phrases in the System Prompt, Backed by Real Discoveries

Each finding below identifies exact prompt text, explains why it's problematic, and provides **real quotes from real discoveries** that demonstrate the issue.

### Issue Group 1: "Touch Lightly" / "Touch Others" — Permission to Name-Drop

Two separate lines in the prompt explicitly permit the model to mention topics without developing them:

**Line 73:**
```
Engage (middle sections deepen that lens while touching others only when valuable)
```

**Line 87:**
```
middle sections (Engage) deepen that lens and optionally touch lightly upon other lenses
```

"Touching others" is the root permission slip for shallow breadth. "Touch lightly upon" a person means naming them without telling their story. "Only when valuable" is no guard — the model always judges its own tangents as "valuable."

#### Evidence from discoveries:

**#185 (Doge Alvise Mocenigo) — Napoleon name-dropped in one sentence:**
> "Within twenty years of his death, the independent Republic of Venice would finally fall to Napoleon."

Napoleon gets one sentence at the end of a section, then the text moves to describing ceremonial clothing. The fall of Venice to Napoleon is one of the most dramatic events in European history, reduced to a passing mention.

**#189 (Vytautas the Great) — Battle of Grunwald name-dropped:**
> "One of his greatest victories happened far from this castle at the Battle of Grunwald."

One of the most important battles in European medieval history gets exactly one sentence.

**#196 (Noble Steel) — Chomętowski name-dropped:**
> "The inscription at the bottom of the case names Stanisław Chomętowski. He was a powerful leader in the early seventeen hundreds. For him, carrying a bulawa was like holding a scepter."

Chomętowski gets 2.5 sentences: he existed, he was powerful, his mace was important. No battles, no decisions, no story.

**#194 (Freedom Monument) — "Famous sculptor" never named:**
> "Only the intervention of a famous sculptor saved the structure. She argued that its artistic value was more important than its political message."

A "famous sculptor" who saved a national monument from Soviet demolition — never named, never developed.

**#202 (The Golden Siege) — The Holy League, then the Habsburgs:**
> "The man on the horse is likely a high-ranking commander of the Holy League. This was a massive military alliance that included the Republic of Venice."

Then immediately:
> "The Habsburgs. They were the primary rivals of the Ottoman Empire for centuries."

Both get one sentence of context before the text moves on.

**Note on #187 (Alexander the Great):** "Future Roman emperors and even Napoleon studied these features" is a name-drop, but the mention of Philip II ("His father, Philip the Second, was a brilliant general who conquered Greece first") is less problematic — this could work as a breadcrumb if used well, building on the existing story about Alexander rather than jumping away from it.

---

### Issue Group 2: Topic-Per-Section Pattern — Each H2 Introduces a New Topic

This is the most critical structural issue. 16 of 25 discoveries exhibit it. The lens playbook examples teach this pattern: each example uses 3 bullets that each cover a different sub-topic with the same structure. The model replicates it faithfully.

**The problem isn't having multiple topics.** The problem is that ALL examples model the SAME approach — describe it → explain how it's made → broader context. Every Objects lens example follows this pattern. There's no variety. The model learns "this is how I should always structure responses" and replicates it mechanically.

**Prompt examples that model this pattern (OBJECTS LENS — all 5 examples):**

```
Longsword (Lines 164-167):
- Describe the blade's shape, fuller, crossguard, and pommel
- Explain medieval steel production
- Mention how such swords were sharpened, maintained, and eventually retired
```

Three topics: blade design → steel production → maintenance.

```
Terracotta Warrior (Lines 168-171):
- Describe visible details: hairstyle, armour plates, facial expression
- Explain how figures were moulded, assembled, and originally painted
- Note differences between warriors and what that reveals about Qin military ranks
```

```
Gold mask (Lines 172-175):
- Describe the mask's hammered gold, stylised features
- Explain how gold was mined, refined, and worked
- Talk about how masks like this were worn in ceremonies
```

```
Ramen (Lines 176-179):
- Break down layers: broth, noodles, tare, toppings
- Explain how each component is prepared
- Mention the shop's specific style
```

```
Shinkansen (Lines 180-183):
- Describe visible parts: aerodynamic nose, bogies, pantograph
- Explain how the nose shape reduces tunnel boom
- Briefly connect to how high-speed trains reshaped travel
```

Every example: Bullet 1 = describe, Bullet 2 = explain how, Bullet 3 = broader context. The model learns there's only one way to structure a response.

**What we need:** Examples that show DIFFERENT types of responses. Some that go deep on one aspect. Some that cover several aspects but develop each. Some that tell a single story across all sections. The variety teaches the model it has OPTIONS, not a formula.

#### Evidence from discoveries:

**#196 (Noble Steel) — SEVERE. Four objects, none developed:**
- H2 #1: Sarmatian identity myth
- H2 #2: Bulawa maces as commander symbols
- H2 #3: Black Madonna religious icon
- H2 #4: Karabela sword design

Each object gets 3-4 sentences. Directly mirrors the Objects lens examples.

**#200 (Courtyard of the Doge) — Four topics, equal weight:**
- H2 #1: Doge coronation ceremony
- H2 #2: Courtyard as administrative hub
- H2 #3: Mars and Neptune statues
- H2 #4: Bronze wellheads

**#221 (Hill of Three Crosses) — Five topics, none developed:**
- H2 #1: Monk martyrdom legend (1 paragraph)
- H2 #2: Soviet destruction (1 paragraph)
- H2 #3: Secret memory during occupation (1 paragraph)
- H2 #4: Fragments in current monument (1 paragraph)
- H2 #5: View from the hill (1 paragraph)

The discovery mentions the monument was "finished in only fourteen days" — an extraordinary fact that could fill an entire section. Instead it gets one sentence among five competing topics.

---

### Issue Group 3: Unsupported Superlatives

No prompt rule currently bans making large claims without supporting detail. This is a relatively minor fix — add guidance to support big claims with specific evidence.

#### Evidence from discoveries:

**#183 (The Winged Hussars):**
> "For over a century, these riders were considered the most dangerous men on a European battlefield."

No specific battles named, no numbers given. This sentence isn't terrible on its own — but it becomes better immediately with supporting detail: "They were famous for winning battles against much larger armies" → Which battles? What happened?

**#189 (Vytautas the Great):**
> "He was a master of diplomacy and war."

No specific diplomatic examples. No specific war described.

**#196 (Noble Steel):**
> "This balance of weight and form influenced sword making across the entire continent for centuries."

Massive claim with zero supporting detail.

**Fix:** When you make a claim like "most dangerous," "legendary," "greatest" — follow it immediately with at least one specific supporting detail (a name, a date, a battle, a number). The claim becomes much more powerful with evidence.

---

### Issue Group 4: Cold Start Examples as Breadth Checklists

The cold start examples list 3-4 separate tasks per discovery, teaching the model to cover multiple topics mechanically.

**Lines 370-372:**
```
Identify the scene (cafes, town hall, fountain), explain how such squares evolved,
tell one concrete story typical of this region and era, and flip with an
Objects-focused note on a single element.
```

Four tasks: identify → explain evolution → tell story → flip. "Explain how such squares evolved" is itself a breadth instruction asking for a historical survey.

**Lines 373-375:**
```
Use visual clues to infer style, explain what that style explored, talk about
painters' lives, flip with a short People-focused moment about a plausible sitter/viewer.
```

Four tasks. "Talk about painters' lives" (plural) invites name-dropping multiple painters.

**Lines 376-378:**
```
Describe the bowl, tie it to region, mention ordering rituals, flip with an
Ideas-focused note on regional ramen styles.
```

Four tasks. Each gets a sentence or two.

**The real problem:** These examples aren't showing real responses. They're describing how to respond in an abstract, task-list way. We should replace them with actual good examples — real discovery responses or response-quality examples that show what the output should look like, not instructions about what tasks to complete.

#### Evidence from discoveries:

**#181 (Millennium Monument) — follows the cold start checklist pattern:**
- Identifies what the monument is
- Explains who the statues represent
- Tells about WWII damage
- Flips to visitor experience

Four tasks, four topics. Saint Stephen gets 2 sentences before the text moves to "warriors, lawgivers, and reformers" without naming anyone.

---

### Issue Group 5: Tangential Zoom-Out

**Line 95:**
```
It is fine to zoom out tangentially (e.g., Middle Ages nobles, Edo-period merchants,
Mughal courts, Mayan city-states, Brazilian street football, Bangkok street food culture)
as long as details are true and plausibly connected.
```

**The concept is sound.** Sometimes the specific subject is narrow and zooming out gives us richer material. But the criteria ("true and plausibly connected") are too weak. Everything at a location is plausibly connected to its era.

#### Evidence — zoom-out done WELL:

**#184 (Latvian Heraldry Wall):**
> "In January 1991, thousands of people from these very towns flooded into Riga. They brought tractors and heavy trucks to block the narrow streets."

Zooms from the heraldic wall to a specific 1991 event. This is excellent — it's specific, vivid, and gives the listener something real.

#### Evidence — zoom-out done POORLY:

**#184 (same discovery — different section):**
> "The symbols on these shields follow the ancient rules of heraldry. You can see silver fish, golden keys, and red lions decorating the wall."

Shifts from the memorial to generic heraldry principles that apply everywhere. This is the bad kind of zoom-out — generic rather than specific.

**#192 (Tomb of Amyntas):**
> "Adopting these foreign shapes served as a diplomatic statement of wealth and sophisticated taste."
> "It told every traveler that the rulers here were part of the wider Mediterranean elite."

We know enough about the Tomb of Amyntas to talk about it specifically. We don't need to zoom out to generic Mediterranean cultural signaling. We could talk about the specific tomb, the specific culture of Lycia, a specific story.

**#202 (The Golden Siege) — zooms from specific relief to generic gilding:**
The final section abandons the battle narrative entirely to discuss woodworking technique. Generic craft description, not tied to the specific battle depicted.

**Proposed fix:** Change the zoom-out criteria from "plausibly connected" to something like: zoom out tangentially when the specific content is narrow, and when zooming out would provide a deeper, more specific, more meaningful response. The zoom-out should land on a SPECIFIC story or fact, not a generic description of an era or craft. The parenthetical list of generic categories (Middle Ages nobles, Edo-period merchants) should be removed — these teach the model to zoom to categories rather than stories.

---

### Issue Group 6: "Sideways Angles" and Breadth-Focused Strategies

**Line 96:**
```
Deeper or sideways angles can appear later.
```

**Line 382:**
```
Strategies: keep same primary lens but go deeper/different angle; switch lens while
building on earlier content; zoom in on one previously mentioned element.
```

"Sideways angles" is breadth by another name. In Line 382, two of three strategies are breadth-focused ("different angle" and "switch lens"). Only the third ("zoom in on one previously mentioned element") is about depth — and it's listed last.

#### Evidence from discoveries:

**#201 (The Friars' Great Church) — switches topics each section:**
- H2 #1: Franciscan poverty paradox
- H2 #2: Scuola Grande social competition
- H2 #3: Tintoretto's commission trick
- H2 #4: Brick vs. marble texture

**Note:** The Franciscan poverty paradox response IS actually good — the different aspects are interesting and each gets enough development. The "sideways angles" instruction isn't always bad in practice, but the language gives unnecessary permission for shallow topic-switching. We should remove the "sideways" language while keeping the ability to explore related aspects that the subject naturally offers.

---

## Discoveries That Got It Right — What Quality Looks Like

These discoveries show what happens when topics get sufficient attention. Notice: not all of them go deep on ONE thing. Some cover multiple aspects but do each one well.

### Multi-Aspect Done Well

**#191 (Venice's Secret Arsenal) — Severity 1:**
Covers state monopoly on violence across four angles: ready defense, technology as wealth, centralization preventing private armies, sensory experience of firing. Each section develops its angle. The thread holds across all four sections. It zooms out ("they operated on a principle of total state control") but the zoom-out is earned and specific.

> "Imagine the rotten-egg smell of burnt sulfur and the deep boom echoing off the stone walls."

This isn't going deep on one thing — it's exploring multiple aspects of one subject, giving each aspect enough room to develop real knowledge.

**#182 (Basilica of St. James) — Severity 1:**
Three sections covering three aspects of this facade:
1. Saint James iconography — who he was, what Spain and pilgrims meant
2. Ottavio Mosto's technique for THIS specific relief
3. The thief's arm legend connected to THIS specific church

Different topics, but each one gets development. Each section feels like you learned something. Not name-dropping and moving on — giving each aspect its due.

**#193 (Winged Guardian) — Severity 1:**
Coherent around the lion as dual symbol: religious authority + legal authority. Each section develops the same theme from a different angle. Even the connection to the previous discovery works because it's a direct thematic continuation.

### Single-Story Deep Dive Done Well

**#219 (Accidental Sticky Notes) — Severity 1:**
One invention narrative: Silver's failed adhesive → five years of rejection → Fry's choir-singer insight → the microsphere science. Every section advances the same story. This is depth on one thread.

**#199 (Stoves of Rundāle) — Severity 1:**
Single thread: how the heating system worked and what it meant. Visual description → heat storage mechanism → social implications of hidden labor. Every sentence connects to the central thread.

### The Pattern

Discoveries that work — whether covering one topic or several — share one trait: **whatever they mention, they develop.** They don't name-drop and move on. They give each aspect enough sentences to convey real knowledge. The listener finishes feeling informed, not teased.

The current prompt defaults to the worst of both worlds: covering many topics but developing none of them. We need to enable both modes (single-story and multi-aspect) while killing the name-drop pattern.

---

## Items Parked for Later

### A5: "Its era, place, culture, movement, or object type" (Line 94)

```
Prefer true, specific content tied to this subject and/or its era, place, culture,
movement, or object type.
```

The "and/or" with five broadening categories could give the model permission to jump from specific subjects to era-level surveys. This is related to the tangential zoom-out issue.

**Status:** Considered but not being evaluated at this stage. The broadening may be fine as long as the core fixes (removing "touch lightly," improving examples, fixing zoom-out criteria) are in place. Evaluate after those changes are applied. See `zoom-out-tangentially-exploration.md` for more.

---

## Section-by-Section Changes to the Prompt

### IPOP IN WHAT'S THAT (Line 73) — REWRITE

**Current problematic text:**
```
Engage (middle sections deepen that lens while touching others only when valuable)
```

**Proposed rewrite:**
> The narrative structure follows Attract (first H2, hook with the sharpest fact), Engage (middle sections develop the story — give each topic enough space to convey real knowledge), and Flip (optional final H2, a different IPOP lens on the same subject — a perspective shift, not a topic shift).

Key change: remove "while touching others only when valuable." Replace with guidance toward developing whatever you mention.

### PER-DISCOVERY IPOP BEHAVIOR (Line 87) — REWRITE

**Current problematic text:**
```
middle sections (Engage) deepen that lens and optionally touch lightly upon other lenses
```

**Proposed rewrite:**
> Build the narrative so that the first H2 (Attract) hooks with the sharpest fact from the primary lens, middle sections (Engage) develop the story with real detail — if you mention a person, tell their story; if you mention an event, explain what happened; if you describe a technique, show how it works. The optional final section (Flip) applies a different IPOP lens to the same subject for a surprise perspective shift (or is omitted if staying in the primary lens is more rewarding).

Key changes:
- Replace "touch lightly upon other lenses" with guidance on developing whatever you mention
- Make flip explicitly optional
- Add concrete guidance without prescribing a single format

### FLIP — Make Optional

**Current behavior:** Flip is always the final H2, required on cold starts.

**Proposed change:**
- Flip is optional. On cold starts, generally include one. On subsequent photos of the same place, skip it if staying in the primary lens is more rewarding.
- When included, flip should be short — a coda, not a full section.
- The flip MUST stay on the same subject. It's a perspective change, not a topic change.
- The flip should be a genuine knowledge-based connection (e.g., "the knight who used this weapon was famous for..."), NOT an observation fabricated from the image (e.g., don't suggest "the wear on the grip suggests a right-handed fighter" as this invites hallucination).

### LENS PLAYBOOK Shared Principles (Lines 94-96) — ADJUST

**Line 95 — Refine zoom-out criteria:**

Current:
```
It is fine to zoom out tangentially (e.g., Middle Ages nobles, Edo-period merchants,
Mughal courts, Mayan city-states, Brazilian street football, Bangkok street food culture)
as long as details are true and plausibly connected.
```

Proposed:
> It is fine to zoom out tangentially when the specific subject is narrow and zooming out would provide a richer, more specific response. When zooming out, land on a SPECIFIC story or fact — not a generic description of an era or practice. Zoom-out should make the response MORE specific, not less.

Remove the parenthetical list of generic categories (Middle Ages nobles, Edo-period merchants, etc.) — these teach the model to zoom to categories rather than stories.

**Line 96 — Remove "sideways":**

Current: `Deeper or sideways angles can appear later.`
Proposed: `Deeper angles can appear in subsequent discoveries about the same subject.`

### LENS PLAYBOOK Examples — REWRITE TO SHOW VARIETY

**The problem:** All examples in each lens follow the same structural pattern. All 5 Objects examples use describe → explain how → broader context. The model learns there's only one way to write a response.

**The fix:** Each lens should have examples showing DIFFERENT response types:
- One example that goes deep on one aspect across all sections (single-story mode)
- One example that covers several aspects but develops each (multi-aspect mode)
- Different structural approaches so the model learns it has OPTIONS

**CRITICAL: Replace synthetic examples with real discoveries from the database.** The current examples are abstract task descriptions ("describe the blade's shape, explain medieval steel production"). We need real response-quality examples — actual good paragraphs that show what the output should look and sound like. Where possible, use the best discoveries from the audit (#191, #182, #199, #219, #193) as templates.

### Cold Start Examples (Lines 370-378) — REWRITE

**Current problem:** These are task lists (identify → explain → tell → flip) that prescribe a mechanical checklist.

**Proposed approach:** Replace task-list format with real example responses, or at minimum with guidance that allows both modes. Don't prescribe "do only one thing" and don't prescribe "do four things." Instead:
- If the subject has one rich story (a painting depicting a specific event, a monument to a specific person), tell that story across the sections
- If the subject is broad (a palace, a square, a bowl of ramen), cover a few aspects but give each enough development
- Either way: no name-dropping. Whatever you mention, develop it

### Same Subject Multiple Photos (Line 382) — REWRITE

**Current problematic text:**
```
Strategies: keep same primary lens but go deeper/different angle; switch lens while
building on earlier content; zoom in on one previously mentioned element.
```

Remove "switch lens" strategy and "different angle" language. Keep "zoom in on one previously mentioned element" as the primary strategy. For subsequent photos of the same subject, the model should go deeper — not sideways.

### DO NOT / AVOID — ADD NAME-DROP BAN

> **Name-drop and move on** — Mentioning a person, event, institution, or cultural practice in 1-2 sentences and then skipping to a different topic. If you name something, develop it or leave it out entirely.
>
> THE NAME-DROP TEST: Before mentioning any person, event, or institution by name, ask: "Am I going to spend at least 2-3 sentences developing this?" If not, either (a) develop it or (b) cut it.
>
> ❌ "They were famous for winning battles against much larger armies." (#183 — which battles?)
> ❌ "Chomętowski was a powerful leader in the early seventeen hundreds." (#196 — doing what?)
> ❌ "Within twenty years of his death, Venice would fall to Napoleon." (#185 — how? what happened?)
>
> ✓ "At the Battle of Kircholm in 1605, three thousand hussars charged eleven thousand Swedish infantry. The Swedes broke in under half an hour."
> ✓ "Chomętowski earned this mace after holding the eastern border against Ottoman raids for fifteen years."

### PATTERN BANS — ADD

> **Undeveloped mentions** — Introducing a person, battle, event, or institution and moving on in 1-2 sentences. The worst form is making a large claim ("famous for," "legendary," "one of the greatest," "changed the course of") without a single supporting detail. Evidence: #183 ("most dangerous men on a European battlefield" — no battles named), #189 ("master of diplomacy and war" — no examples), #196 ("influenced sword making across the entire continent" — no specifics).

### BANNED PHRASES — ADD

> 6. **Unsupported superlatives** — Never write "famous for," "legendary," "one of the greatest," "changed the course of history," or "shaped the future of" unless you immediately follow with at least one concrete supporting detail (a name, a date, a number, a specific outcome).
>    - ❌ "They were famous for winning battles against much larger armies." (#183)
>    - ✓ "At Kircholm, three thousand of them broke eleven thousand Swedes in thirty minutes."

### STYLE FOR THE EAR — ADD WORD BUDGET DISTRIBUTION

Add after the existing word count guidance (260-330 words):

> **Word budget distribution:**
> - **Mode A (single-story):** Spend at least 70% of your word budget developing your primary thread. The remaining words cover identification and the optional flip. Can go up to 100% on the primary thread.
> - **Mode B (multi-aspect):** Cover up to 3-4 topics. Each topic must get enough development to convey real knowledge — at least 2-3 sentences of substance per topic. No undeveloped mentions.

### PRE-FLIGHT CHECKLIST — ADD

> - **Development check**: Every person named, every event mentioned, and every institution referenced is developed with at least 2-3 sentences of substance. No undeveloped mentions.

### QUALITY BAR — ADD

> - The discovery develops its content with real knowledge rather than name-dropping and moving on. The listener finishes feeling they learned something substantial, not that they heard a list of interesting-sounding things.

---

## Word Budget by Mode

Both modes should include guidance on how to spend the ~260-330 word budget:

**Mode A — Single-story deep dive:**
- Spend at least 70% of the word budget (roughly 180-230 words) developing the primary thread. The remaining words cover identification and the optional flip section.
- Can go up to 100% on the primary thread if no flip is needed.

**Mode B — Multi-aspect exploration:**
- Cover up to 3-4 topics. Each topic must get enough development to convey real knowledge — not a one-liner and move on.
- No single topic should be less than ~2-3 sentences of substance.

The word budget guidance helps prevent the worst pattern (5+ topics at one sentence each) without forcing a single response mode.

---

## What NOT to Change

These were considered but rejected as over-specification:

- **"Hook must come from the thread you develop"** — The hook should be the most attractive thing. Don't add constraints on hook-thread alignment.
- **"Up to one topic per discovery"** — 3-4 topics are fine if each is developed. The enemy is name-dropping, not breadth.
- **"Attract hook framing instructions"** — The existing hook guidance is already good. Don't add more.

---

## Before/After Example

### BEFORE (#183 — actual discovery, shallow breadth + name-drop):

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

**Problems traced to prompt:**

| Problem in output | Prompt text that caused it |
|---|---|
| "Famous for winning battles" — no battles named | No ban on unsupported superlatives |
| Four topics (reputation, cost, wings, leopard skin) — none developed | Lens playbook: all Objects examples model 3-topic breadth |
| "Celebrities of their day" — asserted without evidence | Line 87: "optionally touch lightly upon other lenses" |
| Leopard skins "from Africa through trade routes" — one sentence | Line 95: "zoom out tangentially" permits surface-level cultural mentions |
| Each H2 = new topic | Cold start examples list 3-4 separate tasks per discovery |

### AFTER (one thread deep — Mode A):

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

One thread (Kircholm) developed across the full discovery. The listener learns ONE battle in vivid detail and understands *why* the hussars were legendary — not just told that they were.

---

## Summary: Severity Distribution Across 25 Discoveries

| Severity | Count | Discoveries |
|----------|-------|-------------|
| Severe (3) | 4 | #184 (Heraldry Wall), #187 (Alexander), #196 (Noble Steel), #200 (Courtyard of the Doge) |
| Moderate (2) | 12 | #181, #183, #185, #188, #189, #190, #192, #194, #197, #201, #202, #221 |
| Minor (1) | 9 | #182, #186, #191, #193, #195, #198, #199, #219, #220 |
| Clean (0) | 0 | — |

**Most common issue:** Topic-per-section pattern (16/25 discoveries)
**Second most common:** Name-drop and move on (10/25)
**Third:** Unsupported superlatives (8/25)

---

## Implementation Priority

1. **Highest impact:** Rewrite Lines 73 and 87 (remove "touching others" / "touch lightly") + add name-drop ban + add undeveloped mentions pattern ban + add unsupported superlatives banned phrase + add development check to pre-flight. These directly address the two most common issues.
2. **Second priority:** Rewrite lens playbook examples to show variety (not all same pattern) + replace with real discovery-quality examples. Examples are the mechanism by which the model learns what "good" looks like. 14 of 21 currently model the same breadth pattern.
3. **Third priority:** Rewrite cold start examples as real responses (not task lists) + refine zoom-out criteria + remove "sideways angles" language + make flip optional.
4. **Evaluate after:** Whether "zoom out tangentially" (Line 95) and the broadening options (Line 94) need further changes.

---

## Quick Reference: All Changes

| Line | Current text | Change |
|------|-------------|--------|
| 73 | "while touching others only when valuable" | Remove. Replace with guidance on developing whatever you mention |
| 87 | "optionally touch lightly upon other lenses" | Remove. Replace with guidance on developing topics with real detail |
| 87 | (Flip described as always present) | Make flip optional. Short when used. |
| 95 | "zoom out tangentially" with generic category list | Remove generic category list. Refine criteria: zoom out when content is narrow, land on specific stories |
| 96 | "Deeper or sideways angles can appear later" | Cut "or sideways" |
| 105-183 | All lens examples follow same pattern | Rewrite with variety — show different response modes, use real discoveries |
| 370-378 | Cold start examples as task lists | Rewrite as real response examples or remove task-list format |
| 382 | Three strategies (2 breadth, 1 depth) | Remove "switch lens" and "different angle." Keep "zoom in on one element" |
| 405-422 | DO NOT / AVOID section | Add name-drop ban |
| 414-422 | Pattern bans | Add undeveloped mentions ban |
| 424-448 | Banned phrases | Add unsupported superlatives ban |
| 503-507 | Style for the ear | Add word budget distribution (Mode A: 70-100% on primary thread; Mode B: up to 3-4 topics, each developed) |
| 535-542 | Pre-flight checklist | Add development check |
| 544-549 | Quality bar | Add development criterion |

### Related documents:
- `breadcrumbs-concept.md` — Parked concept for later evaluation
- `zoom-out-tangentially-exploration.md` — Line 95 being refined, generic categories removed
- `prompt-upgrade-requirements.md` — Actionable requirements for implementing these changes
