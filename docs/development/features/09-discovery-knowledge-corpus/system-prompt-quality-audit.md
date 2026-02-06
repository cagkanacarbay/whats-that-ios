# System Prompt Quality Audit (v0.7.2)

Analysis of ~188 dev discoveries + 20 most recent DB discoveries to identify recurring output quality issues, trace them to root causes in the system prompt, and collect good/bad counter-examples for prompt improvement.

---

## Issue 1: "Served as / Acted as" Scaffolding (CRITICAL — 65% of recent discoveries)

### The Problem

The prompt bans "represents/reflects" scaffolding. The model stopped using those exact words but substituted synonyms that do the same thing:

| Banned (model avoids) | Substitutes (model uses freely) |
|---|---|
| "represents" | "served as", "acted as" |
| "reflects" | "functioned as", "stood as" |
| "the idea of" | "became a [abstract noun]", "stands as" |

**Bad examples from discoveries:**
- "This space **served as** a spiritual fortress for a people without a state." (#275)
- "This site **became** a massive monument to both religious gratitude and imperial strength." (#274)
- "This Serbian Orthodox church **stands as** a massive monument to that invitation." (#268)
- "These pieces **functioned as** portable diplomatic statements." (#261)
- "Warsaw's Field Cathedral **serves as** the spiritual headquarters for the entire Polish military." (#263)
- "These spires **acted as** a silent protest against foreign imperial influence." (#258)
- "This building **stands as** a monument to the power of culture over politics." (#056)
- "This colonnade **acts as** a visual history book for anyone walking through the square." (#181)
- "This tower. . . **served as** a vital landmark for sailors." (#001)
- "This building was **an idea made of stone**." (#005)
- "It **acted as** a physical statement of cultural independence." (#248)

**Timeline observation:** Early discoveries (1-130) used "represents" and "the idea of" heavily. After those phrases were banned, discoveries 131+ switched to "served as / acted as / stood as" — the same pattern with different words.

### Root Causes in the Prompt

1. **The ban is word-level, not concept-level.** The prompt bans specific words ("represents", "reflects") but the underlying problem is the *pattern*: inserting a meta-layer between the reader and the content. Any verb that says "this thing IS [abstract role]" instead of showing what it IS or what people DID with it is the same problem.

2. **No positive rule for what to do instead.** The "Show, Don't Categorize" section has good examples of what NOT to do, but doesn't give a clear affirmative instruction like: *"Say what the thing is. Say what people did with it. Don't tell us what role it played."*

3. **The "Show, Don't Categorize" examples only cover purpose/function.** They show how to fix "Its primary purpose was ceremonial" → "This helmet never saw battle. The king wore it at parades." But they don't cover the "served as / stood as" pattern, which is about ROLE/IDENTITY rather than PURPOSE.

### Good Counter-Examples from Discoveries

These paragraphs deliver the same information WITHOUT scaffolding:

**#174 The Doge's Giant Ego** — Shows what people DID:
> Giovanni Pesaro spent a fortune to ensure no one would ever forget his name. He was one of the wealthiest men in Venice but he was not well liked. He left twelve thousand gold ducats in his will specifically to build this giant tomb. He even chose the location next to the side entrance of this church. He knew every person entering the building would have to look up at him.

No "served as", no "represented", no "stood as". Every sentence is a concrete action or fact about a real person.

**#220 Latvian Curd Snacks** — All facts, zero scaffolding:
> Latvians eat millions of these small curd blocks every single year. You are holding a cult-classic snack called Karums. Every Latvian child grew up with these bright orange wrappers in their lunchbox. The name itself translates to "sweet treat" or "delicacy." It is far more central to local life than a standard candy bar. Former presidents have even served these at high-level diplomatic meetings.

The last sentence SHOWS importance through a concrete detail (presidents serving it at meetings) instead of TELLING us "it serves as a national symbol."

**#158 The Woman in Gold** — Shows HOW something was made:
> Gustav Klimt used real gold leaf to create this shimmering portrait of Adele Bloch-Bauer. He applied thin metal sheets directly to the canvas with a special adhesive. This technique makes the painting glow like a religious icon. The metallic surface reflects light in different ways as you move past it.

No "this painting represents the peak of the Vienna Secession." Just what Klimt DID and what you SEE.

**#199 Stoves of Rundāle** — Concrete visual detail:
> Nearly eighty hand-painted ceramic tiles cover this massive heating tower from top to bottom. Each tile shows a unique miniature scene of Dutch landscapes or tiny sailing ships. This specific blue and white glaze was the height of fashion in the mid-1700s.

Compare to how this COULD have been written badly: "This heating tower served as a showcase for the artistic tastes of the Baltic aristocracy. It represents the cultural influence of Dutch craftsmanship on Latvian interior design."

**#237 Palace of Culture** — Numbers and actions:
> Joseph Stalin sent forty million bricks and five thousand Soviet workers to build this skyscraper in 1955. It was officially a gift from the Soviet Union to the people of Poland. At the time, it was the tallest building in the country.

Compare to: "This building served as a massive symbol of Soviet control over postwar Poland. It represented the dominance of socialist ideology over the city of Warsaw."

### Suggested Fix

**A. Expand the ban list** to include the synonym family:
- "served as", "acted as", "functioned as", "stood as", "stands as", "became a [role/symbol]"
- Any pattern where the verb assigns an abstract role or meaning to the subject

**B. Add a concept-level rule** (more important than word bans):

> **THE SCAFFOLDING TEST**
> Before writing a sentence, ask: Am I describing what this thing IS, what it LOOKS LIKE, or what people DID with it? Or am I assigning it an abstract role?
> - "This church served as a spiritual fortress" → assigning a role. CUT.
> - "Farmers stopped here to pray before the harvest" → showing what people did. KEEP.
> - "This column acted as a symbol of imperial power" → assigning a role. CUT.
> - "Emperor Theodosius shipped this obelisk from Egypt to prove his capital rivaled Rome" → showing what someone did. KEEP.
>
> If a sentence could start with "[Subject] served as / acted as / stood as / became / functioned as / was a symbol of", it is scaffolding. Rewrite it as an action, a visible detail, or a concrete fact.

**C. Add "served as / acted as" examples to the "Show, Don't Categorize" section:**

Under a new sub-heading like "Role and Identity":
- BAD: "This church served as the spiritual headquarters for the Polish military."
- GOOD: "Soldiers came here to pray before deployment. Chaplains wore uniforms alongside clerical robes."
- BAD: "This building acted as a physical statement of cultural independence."
- GOOD: "The Serbian merchants refused to copy the local Italian style. They hired an architect to study Byzantine domes."
- BAD: "This colonnade stands as a visual history book for anyone walking through the square."
- GOOD: "Every statue on the colonnade tells a specific chapter: Arpad arriving on horseback, Stephen receiving the crown from the Pope."

---

## Issue 2: Grand Abstract Noun Phrases (40% of recent discoveries)

### The Problem

The model compresses complex realities into impressive-sounding but empty noun phrases. These sound intellectual but communicate nothing specific.

**Bad examples:**
- "manifesto of national identity" (#275)
- "monument to both religious gratitude and imperial strength" (#274)
- "rigid structure of power" (#273)
- "portable diplomatic statements" (#261)
- "a canvas for art" (#261)
- "political theology" (#260)
- "national symbol of resilience" (#263)
- "physical statement of cultural independence" (#248)
- "the ideological power of Urartu" (#070)
- "a visual manifesto for the city of Berlin" (#051)
- "a permanent record of the city's official decisions" (#038)

### Root Cause in the Prompt

The "Show, Don't Categorize" section addresses replacing abstract PURPOSE labels but doesn't address abstract NOUN PHRASES used as descriptions. The model has learned not to say "its primary purpose was ceremonial" but still says things like "this was a manifesto of national identity" — same abstraction, different grammar.

### Good Counter-Examples

**#174 Doge's Giant Ego** — Instead of "monument to personal vanity":
> He left twelve thousand gold ducats in his will specifically to build this giant tomb. He even chose the location next to the side entrance. He knew every person entering would have to look up at him.

**#231 King Augustus III** — Instead of "symbol of the tension between military duty and artistic sensibility":
> He stands before you in a suit of polished steel armor. However, do not let the military gear fool you. Augustus was famous for hating the battlefield. He never once led his troops into a major combat. He preferred the quiet halls of art galleries and the soaring music of the opera house.

**#130 Tower of Warnings** — Instead of "gruesome symbol of absolute imperial power":
> In 1621, after a failed revolt, twenty-seven noblemen were executed in the square nearby. Their severed heads were placed in iron baskets and hung from this tower. They stayed there for ten long years as a warning to the citizens.

### Suggested Fix

Add a rule and examples under "Show, Don't Categorize":

> **UNPACK ABSTRACT NOUNS**
> If you find yourself writing a compressed phrase like "monument to X", "symbol of Y", "statement of Z", or "manifesto of W" — stop and unpack it into the concrete reality it refers to.
>
> - BAD: "a manifesto of national identity"
> - GOOD: "Matejko filled the walls with folk patterns from the Tatra mountains and scenes from Polish legends"
> - BAD: "a monument to both religious gratitude and imperial strength"
> - GOOD: "Charles VI vowed to build this church if the plague stopped. When it did, he kept his word — and made sure the result dwarfed every other church in Vienna"
> - BAD: "portable diplomatic statements"
> - GOOD: "A nobleman carried this to a meeting with a foreign king. The ivory inlays proved he could afford the best craftsmen in Europe."

---

## Issue 3: Weak Attract Hooks — Encyclopedia Openers (50% of recent discoveries)

### The Problem

The prompt's "Writing the First H2" section has good guidance and examples, but the model's actual failure mode doesn't match the listed bad examples.

**What the prompt warns against:**
- "You are standing before one of the most important landmarks in Germany."
- "This building has a fascinating history."

**What the model actually does (not covered by prompt):**
- "This [building/painting/object] serves as the [abstract role] of [place]." (encyclopedia identification)
- "This [thing] was built/designed to [abstract purpose]." (intent framing)

**Bad hooks from discoveries:**
- "This room was the inner sanctum where the real work of the Venetian Empire happened." (#266)
- "Warsaw's Field Cathedral serves as the spiritual headquarters for the entire Polish military." (#263)
- "This red brick building serves as the administrative heart of the Jagiellonian University." (#259)
- "This pillar links the newly reborn Lithuania of 1994 back to its medieval golden age." (#271)
- "These ornate firearms were designed to demonstrate political power through expensive technology." (#261)
- "This massive brick church was built by monks who swore an absolute vow of poverty." (#201)
- "This building was designed to prove that Budapest had finally arrived on the world stage." (#248)

### Good Hooks from Discoveries

These deliver a specific fact, a surprise, or a vivid image immediately:

| # | Discovery | Hook |
|---|-----------|------|
| 265 | The Last Senate | "In 1797, a government that lasted eleven centuries vanished in a single afternoon." |
| 254 | Titian's Rising Virgin | "When this painting was unveiled in 1518, the friars of this church initially tried to reject it." |
| 267 | Drechsler Palace | "The architects of this palace had one specific goal: do not let the Opera House across the street win." |
| 173 | Rebel Monk Methodius | "Methodius spent two years in a dark dungeon for preaching in a language people actually understood." |
| 174 | Doge's Giant Ego | "Giovanni Pesaro spent a fortune to ensure no one would ever forget his name." |
| 180 | Lady of Health | "In 1630, a plague killed nearly a third of everyone living in Venice." |
| 219 | Accidental Sticky Notes | "In 1968, a scientist named Spencer Silver was trying to invent a super-strong adhesive for aircraft. He failed completely." |
| 237 | Palace of Culture | "Joseph Stalin sent forty million bricks and five thousand Soviet workers to build this skyscraper in 1955." |
| 230 | Chapel of St. Kinga | "Everything you see in this massive chamber is carved from solid rock salt." |
| 231 | King Augustus III | "This man is King Augustus III of Poland. He stands before you in a suit of polished steel armor. However, do not let the military gear fool you." |
| 150 | Powder Tower | "Every king who wore the crown of Bohemia began his coronation journey beneath this arch." |
| 177 | Inferno in the Palace | "This nightmare vision of the afterlife hung in the most secretive room in Venice." |
| 130 | Tower of Warnings | "In 1621, after a failed revolt, twenty-seven noblemen were executed in the square nearby. Their severed heads were placed in iron baskets and hung from this tower." |
| 197 | Faces of Alberta Street | "Two massive stone faces look out over the street with their mouths wide open in a permanent scream." |
| 282 | A Hoplite in Red | "This painted warrior was likely a real person in the eyes of the ancient Greeks. He is a hoplite, a citizen who paid for his own heavy bronze gear." |

**Common pattern in good hooks:** They lead with a PERSON doing something, a SPECIFIC FACT with a number or date, a SURPRISING CONTRAST, or a VIVID IMAGE. They never start with "[Subject] serves as..." or "[Subject] was designed to..."

### Root Cause in the Prompt

The bad examples in "Writing the First H2" don't match the model's actual failure mode. The model has learned not to write "You are standing before one of the most important..." but now defaults to "[Subject] serves as the [role] of [place]" or "[Subject] was designed/built to [purpose]" which aren't flagged as weak.

### Suggested Fix

**A. Add the model's actual failure patterns to the "Weak first sentences" list:**

> **Weak first sentences** (these just categorize or frame)
> - "Warsaw's Field Cathedral serves as the spiritual headquarters for the Polish military."
> - "This building was designed to prove that Budapest had arrived on the world stage."
> - "This room was the inner sanctum where the real work happened."
> - "These ornate firearms were designed to demonstrate political power."
> - "This red brick building serves as the administrative heart of the university."

**B. Add more good examples that match common subject types** (buildings, paintings, objects — not just famous landmarks):

> **Good first sentences** (for less famous subjects)
> - "Soldiers came here to pray before deployment. Chaplains wore uniforms alongside their robes." (military church)
> - "Methodius spent two years in a dark dungeon for preaching in a language people actually understood." (religious figure)
> - "Giovanni Pesaro left twelve thousand gold ducats in his will to build this tomb." (Venetian monument)
> - "Nearly eighty hand-painted ceramic tiles cover this tower from top to bottom." (decorative object)

---

## Issue 4: Cold Start Identification Weakness (25% of discoveries)

### The Problem

The prompt says "anchor the user in what it obviously is" and "Name the specific subject if plausibly identifiable." But several discoveries fail to name the subject in the first paragraph.

**Examples:**
- #275 (A National Masterpiece): First paragraph never names St. Mary's Basilica
- #262 (The Celestial Contract): Never names this as an "Annunciation" painting
- #271 (Vytautas's Wooden Legacy): Doesn't describe what the wooden pillar physically IS
- #266 (Heart of the State): Never names the specific room (Sala del Collegio)

### Good Counter-Examples

- #179: "This is the Scala d'Oro, or the Golden Staircase, inside the Doge's Palace."
- #150: "This tower marks the official start of the Royal Route."
- #175: "These were the members of the Brotherhood of Blackheads."
- #282: "He is a hoplite, a citizen who paid for his own heavy bronze gear."

### Root Cause in the Prompt

The cold start rule says "anchor the user in what it obviously is" — but this is implicit, not explicit. The model interprets it as "tell the story from the obvious angle" rather than "NAME the thing in the first 1-2 sentences."

### Suggested Fix

Make the rule explicit:

> **Cold start identification (EXPLICIT):** On the first discovery for a subject, NAME the specific subject (building, painting, square, object) within the first two sentences. Do not save the name for a later paragraph. If the name is unknown, describe what the user is looking at in concrete physical terms ("a stone relief of a horseman", "a narrow wooden box with painted figures inside").

---

## Issue 5: Unanchored Symbolism (40% of recent discoveries)

### The Problem

The prompt bans "symbolises power/hope/freedom without linking to any specific movement, event, or story." The model mostly avoids the word "symbolizes" but achieves the same effect through other constructions.

**Bad examples:**
- "a spiritual fortress for a people without a state" (#275)
- "a physical reminder of a city that survived its darkest hour" (#274)
- "a national symbol of resilience" (#263)
- "a silent protest against foreign imperial influence" (#258)
- "It presents freedom as a hard-won inheritance rather than a simple gift" (#271)

### Good Counter-Examples

**#130 Tower of Warnings** — Instead of "symbol of imperial terror":
> Their severed heads were placed in iron baskets and hung from this tower. They stayed there for ten long years.

**#177 Inferno in the Palace** — Instead of "symbol of moral accountability":
> Members of the Council of Ten stared at these flames while deciding who lived and died. These men served as the supreme judges... The three leaders who met in this specific room were changed every month to prevent corruption.

**#180 Lady of Health** — Instead of "symbol of the city's survival":
> In 1630, a plague killed nearly a third of everyone living in Venice. The city was a ghost town of closed shops and black flags. Desperate survivors made a solemn vow to the Virgin Mary. They promised to build a magnificent church if she stopped the sickness.

### Root Cause in the Prompt

The ban on unanchored symbolism says "without linking to any specific movement, event, or story" — but the model has learned to add one vague contextual detail and then attach the symbolism. "This shift turned a local house of worship into a national symbol of resilience" (#263) technically has context (the shift from Piarist to military) but the phrase "national symbol of resilience" is still empty. The rule needs to be tighter: it's not enough to have SOME context — the symbolic claim itself must be replaced with concrete detail.

### Suggested Fix

Tighten the unanchored symbolism ban:

> Don't just add context before a symbolic claim. Replace the symbolic claim entirely with the concrete detail it's trying to compress.
> - BAD: "This shift turned a local house of worship into a national symbol of resilience."
> - GOOD: "After Poland regained independence in 1918, the military claimed this church as its own. Chaplains now deploy with the troops."
> - BAD: "These spires acted as a silent protest against foreign imperial influence."
> - GOOD: "While the Tsars built golden Orthodox domes across the skyline, Polish architects responded with sharp Gothic brick towers — a style they called Vistula Gothic."

Note: #258 actually DOES have the good version in the middle of the paragraph ("The Tsars were building golden-domed Orthodox churches... Polish architects responded by constructing this sharp, pointed Gothic structure. They called it Vistula Gothic.") — the problem is it ALSO adds the bad version as a closing summary. The fix: trust the concrete detail to do the work. Don't add a summarizing label.

---

## Summary: What the Prompt Needs

| Priority | Issue | Fix Type |
|----------|-------|----------|
| **P0** | "Served as / acted as" scaffolding | Expand ban list + add concept-level scaffolding test + new Show Don't Categorize examples |
| **P0** | Grand abstract noun phrases | Add "Unpack Abstract Nouns" sub-section with examples |
| **P1** | Weak attract hooks | Update bad examples list to match actual failure modes |
| **P1** | Cold start identification | Make "name the subject" rule explicit |
| **P2** | Unanchored symbolism | Tighten rule — replace the claim, don't just add context before it |

### Key Insight

The core issue across all five problems is the same: **the model defaults to meta-explanation**. It tells the user what things MEANT, REPRESENTED, SERVED AS, or SYMBOLIZED rather than showing what people DID, what things LOOK LIKE, or what HAPPENED there.

The prompt already has the right instinct in "Show, Don't Categorize" — but it needs:
1. A broader conceptual rule (the scaffolding test)
2. Updated examples that match the model's ACTUAL failure modes (not the old ones it already learned to avoid)
3. More counter-examples from the model's own best work showing what good output looks like

The best discoveries in the corpus (#174, #220, #158, #173, #231, #237, #130, #180) prove the model CAN write without scaffolding — it just needs stronger guardrails to do it consistently.
