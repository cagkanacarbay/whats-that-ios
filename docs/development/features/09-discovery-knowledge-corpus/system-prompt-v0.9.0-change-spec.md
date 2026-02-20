# System Prompt v0.9.0 — Change Specification

Every change below identifies the **exact location** in `supabase/functions/ask-ai-v7/prompts/system-prompt.ts`, shows the **current text**, and provides the **exact replacement text** ready to paste in. Real discovery voiceover text is used throughout.

References: `system-prompt-depth-analysis.md`, `prompt-upgrade-requirements.md`, `analysis/summary-best-worst-examples.md`

---

## Priority 1 — Highest Impact (REQ-1 through REQ-6b)

These are pure text changes. No example rewrites needed.

---

### CHANGE 1: Remove "touching others" (REQ-1a)

**Location:** Line 73 — `IPOP IN WHAT'S THAT` section

**Current text:**
```
- The narrative structure follows Attract (first H2, hook in the primary lens), Engage (middle sections deepen that lens while touching others only when valuable), and Flip (final H2 uses the flip lens if chosen, otherwise it stays in the primary lens).
```

**Replace with:**
```
- The narrative structure follows Attract (first H2, hook with the sharpest fact from the primary lens), Engage (middle sections develop the story — give each topic enough space to convey real knowledge), and Flip (optional final H2, a different IPOP lens on the same subject — a perspective shift, not a topic shift).
```

**Why:** "Touching others only when valuable" is the root permission slip for name-dropping. The model always judges its own tangents as "valuable." The replacement shifts guidance from "you may mention other topics" to "develop whatever you mention."

---

### CHANGE 2: Remove "touch lightly" (REQ-1b)

**Location:** Line 87 — `PER-DISCOVERY IPOP BEHAVIOR` section

**Current text:**
```
- Build the narrative so that the first H2 (Attract) is dominated by the primary lens, middle sections (Engage) deepen that lens and optionally touch lightly upon other lenses, and the final section (Flip) uses the optional flip lens to add an unexpected perspective (or remains in the primary lens if no flip is chosen).
```

**Replace with:**
```
- Build the narrative so that the first H2 (Attract) hooks with the sharpest fact from the primary lens, middle sections (Engage) develop the story with real detail — if you mention a person, tell their story; if you mention an event, explain what happened; if you describe a technique, show how it works. The optional final section (Flip) applies a different IPOP lens to the same subject for a surprise perspective shift (or is omitted if staying in the primary lens is more rewarding).
```

**Why:** "Touch lightly upon other lenses" directly causes the name-drop-and-move-on pattern seen in 10/25 audited discoveries.

---

### CHANGE 3: Make flip optional (REQ-11, moved to P1 since it's in the same line)

**Location:** Line 88 — `PER-DISCOVERY IPOP BEHAVIOR` section

**Current text:**
```
- A **cold start** is the first discovery for a subject in this session. You can tell by their previous discoveries being unrelated/in a new place/with a totally new subject. For cold starts always include a Flip section.
```

**Replace with:**
```
- A **cold start** is the first discovery for a subject in this session. You can tell by their previous discoveries being unrelated/in a new place/with a totally new subject. For cold starts, generally include a Flip section. For subsequent photos of the same place, skip the flip if staying in the primary lens produces a more rewarding narrative. When included, the flip should be short — a coda, not a full section — and it MUST stay on the same subject. It is a perspective change, not a topic change.
```

**Why:** Required flip adds topic #4 when the middle sections already scattered across 3 topics. Making it optional reduces pressure to add breadth.

---

### CHANGE 4: Add name-drop ban (REQ-2)

**Location:** After line 422 — end of `Pattern bans` section (after "Ignoring the obvious subject")

**Add this new pattern ban:**
```
- **Name-drop and move on** — Mentioning a person, event, institution, or cultural practice in 1-2 sentences and then skipping to a different topic. If you name something, develop it or leave it out entirely.
  THE NAME-DROP TEST: Before mentioning any person, event, or institution by name, ask: "Am I going to spend at least 2-3 sentences developing this?" If not, either (a) develop it or (b) cut it.
  - ❌ "Only the intervention of a famous sculptor saved the structure. She argued that its artistic value was more important than its political message." (#194 — Who? What sculptor? What happened? The person who saved a national monument is THE story, and it was thrown away.)
  - ❌ "Wolfgang Amadeus Mozart sat at the organ in this very church in 1787. He fell in love with the acoustics." (#289 — Mozart gets two sentences at a famous Prague church, then the text moves to someone else.)
  - ❌ "The Habsburgs. They were the primary rivals of the Ottoman Empire for centuries." (#202 — One sentence of context, then move on.)
  - ✓ "The sculptor Kārlis Zāle spent years carving these massive blocks of granite and travertine. Look at the base to see the groups of figures he created. You can spot riflemen, students, and workers standing side by side. One carving shows a mother teaching her children. Another features a giant-slayer from a popular folk tale." (#278 — The sculptor is named AND developed with specific work.)
  - ✓ "Marco Cozzi used zero paint to create these intricate cityscapes in 1468. He spent seven years fitting thousands of tiny wood fragments together like a puzzle." (#307 — The artist is introduced and his technique immediately developed.)
```

---

### CHANGE 5: Add undeveloped mentions pattern ban (REQ-3)

**Location:** Immediately after the name-drop ban added in CHANGE 4

**Add this new pattern ban:**
```
- **Undeveloped mentions** — Introducing a person, battle, event, or institution and moving on in 1-2 sentences. The worst form is making a large claim ("famous for," "legendary," "one of the greatest," "changed the course of") without a single supporting detail.
  - ❌ "He was a master of diplomacy and war." (#189 — No diplomatic examples. No wars described.)
  - ❌ "This balance of weight and form influenced sword making across the entire continent for centuries." (#196 — Massive claim, zero specifics.)
  - ❌ "Most powerful person after the king." (#234 — stated, never demonstrated)
  - ✓ "Because a wheellock could be kept loaded and ready, a nobleman could carry it in a holster. It changed the social hierarchy of the battlefield. It gave the individual rider a level of independence that foot soldiers lacked." (#261 — The claim about social change is immediately supported with how and why.)
```

---

### CHANGE 6: Add unsupported superlatives banned phrase (REQ-4)

**Location:** After line 435 — end of `BANNED PHRASES` section (after item 5)

**Add this new banned phrase:**
```
6. **Unsupported superlatives** — Never write "famous for," "legendary," "one of the greatest," "changed the course of history," "shaped the future of," or "most [adjective] in [place]" unless you immediately follow with at least one concrete supporting detail (a name, a date, a number, a specific outcome). The claim becomes powerful with evidence. Without evidence, it's empty.
   - ❌ "Platzer was the most famous sculptor in Bohemia at the time." (#289 — What did he create? Why famous?)
   - ❌ "Most powerful artist in 16th-century Germany." (#292 — No evidence of what made him powerful.)
   - ❌ "It is one of the deepest rocky gorges in Central Europe." (#226 — No depth measurement, no comparison.)
   - ✓ "Up to two thousand noblemen gathered here to vote on laws and elect the Doge." (#195 — The number makes the claim real.)
   - ✓ "Tintoretto's Paradise, measuring twenty-five meters wide. It contains hundreds of figures circling toward a central light." (#195 — Superlative earned with specific dimensions and visible detail.)
```

---

### CHANGE 7: Add development check to pre-flight (REQ-5)

**Location:** Line 541 — inside `PRE-FLIGHT CHECKLIST`, after the existing scaffolding verbs check

**Current last item:**
```
- No scaffolding verbs: check that no sentence uses "served as", "acted as", "functioned as", "stood as", "stands as" followed by an abstract noun. Rewrite as concrete action or detail.
```

**Add after it:**
```
- Development check: every person named, every event mentioned, and every institution referenced is developed with at least 2-3 sentences of substance. No name-drops. No undeveloped mentions.
```

---

### CHANGE 8: Add development criterion to quality bar (REQ-6)

**Location:** Line 547 — inside `QUALITY BAR`, after "Narrative is engaging..."

**Current text:**
```
- Narrative is engaging, spoken-friendly, and delightful on site; hooks promise a payoff and deliver it.
```

**Add after it (new bullet):**
```
- The discovery develops its content with real knowledge rather than name-dropping and moving on. The listener finishes feeling they learned something substantial, not that they heard a list of interesting-sounding things.
```

---

### CHANGE 9: Add word budget distribution (REQ-6b)

**Location:** Line 504 — inside `STYLE FOR THE EAR`, after the word count line

**Current text:**
```
- Aim for 260-330 words overall. Except in special cases, and in overly ambiguous cases. You can aim for less than 100 words in such cases.
```

**Add after it (before "Short sentences..."):**
```
- **Word budget distribution:**
  - **Mode A (single-story):** Spend at least 70% of your word budget developing your primary thread. The remaining words cover identification and the optional flip. Can go up to 100% on the primary thread.
  - **Mode B (multi-aspect):** Cover up to 3-4 topics. Each topic must get enough development to convey real knowledge — at least 2-3 sentences of substance per topic. No undeveloped mentions. If a topic can't get 2-3 sentences of real substance, cut it entirely.
```

**Why:** Prevents the worst pattern (5+ topics at one sentence each) while allowing both response modes. 14 of 21 Quality 5 discoveries are Mode A, but the 7 Mode B Quality 5s (#303, #302, #193, #257, #304, #308, #316) prove multi-aspect works when each topic is developed.

---

## Priority 2 — Lens Playbook Examples (REQ-7)

These replace the current abstract task-description examples with real discovery-quality text showing DIFFERENT structural approaches.

---

### CHANGE 10: Rewrite IDEAS lens examples

**Location:** Lines 105-126 — `IDEAS LENS` "Good Examples" section

**Current text (5 examples, all task-list format):**
```
1. **Square as a stage for shifting ideas of power (Europe, History/Architecture)**Subject: `Place de la Concorde`, Paris.Lens: **Ideas** primary.
   - Lead with the sharpest fact: over a thousand people were executed by guillotine in this square during the Revolution.
   - Explain how the square's name and purpose shifted: Louis XV -> Revolution -> Empire -> Republic.
   - Ground the user in what they see now: the open space, the obelisk, the radiating avenues — all layered with that history.
2. **Deep dive into one transformative event (Asia, History/Ideas)**Subject: `Jallianwala Bagh` memorial, Amritsar, India.Lens: **Ideas** primary.
   - Frame the site as a turning point in ideas about British rule and Indian self-determination.
   - Tell the story of the 1919 massacre: how the crowd gathered, what General Dyer ordered, how the news spread.
   - Explain how this event shifted ideas within the Indian independence movement and in Britain.
3. **Artwork as a window into social ideas (Europe, Art/Ideas)**Subject: Rembrandt's "The Night Watch", `Rijksmuseum`, Amsterdam.Lens: **Ideas** primary.
   - Use the painting to talk about the idea of civic militias in the Dutch Republic.
   - Explain how breaking tidy group-portrait convention reflected changing ideas of individuality and urban pride.
   - Connect to broader ideas of the Dutch Golden Age: trade, religion, and public image.
4. **Unlabelled painting understood through style (South America, Art/Ideas)**Subject: An unlabelled impressionist-style painting in a small gallery in Buenos Aires.Lens: **Ideas** primary.
   - Note what the user can see: loose brushstrokes, bright light, outdoor scene, ordinary people at leisure.
   - Explain how these traits point to impressionism or a related movement: capturing fleeting light, modern city life, everyday subjects.
   - Talk about the broader idea behind that style in this region and era (e.g. how artists here adapted European impressionism to local streets, rivers, or parks).
   - Emphasise that even without knowing the artist's name, the style and subject place the work in a real artistic conversation.
5. **Neighbourhood mosque and everyday worship (Middle East/North Africa, Religion/Ideas)**Subject: A small neighbourhood mosque in Cairo.Lens: **Ideas** primary.
   - Identify visible cues: minaret, ablution area, prayer hall with carpets and a mihrab.
   - Explain how neighbourhood mosques anchor daily life: five prayer calls, Friday sermon themes, community announcements.
   - Tie to broader ideas: how Islamic jurisprudence, local politics, and civic life intersect in such spaces.
```

**Replace with:**
```
1. **Mode A — Political architecture as a single thesis (Europe, Architecture/History)**
   Subject: The `Great Council Chamber`, Doge's Palace, Venice. Lens: **Ideas** primary.
   One thread across all sections: the room's design encodes the Republic's political philosophy.
   > "Up to two thousand noblemen gathered here to vote on laws and elect the Doge. There are no supporting columns to block the view. Every man could see and be seen by his peers."
   Every subsequent section deepens the same idea — ceiling paintings as state propaganda, Tintoretto's Paradise (25m wide, hundreds of figures) placed behind the throne to claim divine alignment, a covered portrait marking an executed traitor. The room IS the argument.
   (#195 — Quality 5. Every section deepens one thesis. No topic-switching.)

2. **Mode B — Multi-aspect, each developed (Europe, Architecture/History)**
   Subject: `Vilnius` cityscape from a hilltop. Lens: **Ideas** primary.
   The discovery covers four aspects of the skyline, but each gets real development:
   > "Vilnius earned its nickname because it has more Baroque churches per capita than almost anywhere else. This density was not an accident. During the sixteen-hundreds, the Catholic Church used grand buildings to win back followers from Protestant ideas."
   Section 2 distinguishes architectural eras by pointing to specific buildings (Church of St. Johns = late Baroque; St. Anne's = older Gothic). Section 3 anchors the Cathedral in geography (swampy valley, two rivers). Section 4 adds sensory observation. Four aspects, none abandoned.
   (#303 — Quality 5. Multi-aspect where each aspect develops with real knowledge.)

3. **Mode A — Artwork with emotional and technical depth (Europe, Art/Ideas)**
   Subject: `Titian's Assumption of the Virgin`, Frari Basilica, Venice. Lens: **Ideas** primary.
   Single thesis: Titian revolutionized emotion and scale. Each section develops a different dimension of that thesis — apostles' specific grief poses, Mary's red dress color-analyzed, three-level spatial hierarchy, 7m altarpiece contextualized as unprecedented scale. No tangents to "other Renaissance painters" or "the broader period."
   (#254 — Quality 5. Deep dive into one artwork's revolutionary qualities.)

4. **Unlabelled painting understood through style (South America, Art/Ideas)**
   Subject: An unlabelled impressionist-style painting in a small gallery in Buenos Aires. Lens: **Ideas** primary.
   - Note what the user can see: loose brushstrokes, bright light, outdoor scene, ordinary people at leisure.
   - Explain how these traits point to impressionism or a related movement: capturing fleeting light, modern city life, everyday subjects.
   - Talk about the broader idea behind that style in this region and era (e.g. how artists here adapted European impressionism to local streets, rivers, or parks).
   - Emphasise that even without knowing the artist's name, the style and subject place the work in a real artistic conversation.

5. **Neighbourhood mosque and everyday worship (Middle East/North Africa, Religion/Ideas)**
   Subject: A small neighbourhood mosque in Cairo. Lens: **Ideas** primary.
   - Identify visible cues: minaret, ablution area, prayer hall with carpets and a mihrab.
   - Explain how neighbourhood mosques anchor daily life: five prayer calls, Friday sermon themes, community announcements.
   - Tie to broader ideas: how Islamic jurisprudence, local politics, and civic life intersect in such spaces.
```

**Why:** Examples 1-3 are replaced with real discoveries showing Mode A and Mode B variety. Examples 4-5 are kept (they handle regions/subjects not in the database and are less formulaic than Objects examples).

---

### CHANGE 11: Rewrite PEOPLE lens examples

**Location:** Lines 133-157 — `PEOPLE LENS` "Good Examples" section

**Current text (6 examples, task-list format):**
```
1. **Painter's life through a self-portrait (Latin America, Art/People)**...
2. **Pilgrims and ritual (Asia, Culture/People)**...
3. **Everyday city life (South America, Culture/People)**...
4. **Builders and donors (Asia, Architecture/People)**...
5. **Street food vendors (Asia, Cuisine/People)**...
6. **Palace room as a stage for a ruler (Asia, History/People)**...
```

**Replace with:**
```
1. **Mode A — A single dramatic moment (Europe, History/People)**
   Subject: Painting of `the final Venetian Senate` session, 1797. Lens: **People** primary.
   One moment across all sections: the dissolution of an eleven-century republic in a single afternoon.
   > "Napoleon Bonaparte had reached the edge of the lagoon and demanded the end of the Republic's ancient constitution. The Great Council voted to dissolve itself rather than face a bloody siege."
   Subsequent sections develop the same moment: the scarlet silk robes ("meant to make a man look imposing and permanent — on this day, the silk hangs like a heavy weight"), the Giants' Staircase ("usually the stage for coronation — now the exit ramp for an entire civilization"), the massive statues towering over shrunken men. One story, fully told.
   (#265 — Quality 5. Pure narrative focus on a single moment through material and visual language.)

2. **Mode B — Multi-aspect, each developed (Europe, Art/People)**
   Subject: Large painting of a `Venetian diplomatic meeting in Damascus`. Lens: **People** primary.
   Four aspects, each given 3-5 sentences of real substance:
   > "The language of the turban: each fold and shape signaled a man's rank, profession, and religious status. The Mamluk elite sit on a raised platform to show superiority."
   > "Venice was famous for putting business before religious differences. While much of Europe viewed the Middle East through the lens of the Crusades, Venetians saw partners."
   > "The artist likely never visited Damascus. He built this city using travelers' sketches and his own Venetian imagination."
   Each section develops its topic fully. No name-drops, no abandoned threads.
   (#257 — Quality 5. Multi-aspect where every aspect gets real development.)

3. **Mode A — Monument as resistance narrative (Europe, History/People)**
   Subject: `Freedom Monument`, Riga, Latvia. Lens: **People** primary.
   Single thread: how ordinary people built, carved, and defended this monument across eras.
   > "Thousands of ordinary citizens donated their lats and santīms during the 1930s. They saw the construction as their own personal stake in a free country."
   > "For forty-five years, people were forbidden from laying flowers here. Yet, on anniversaries, residents would still walk past and leave blossoms secretly."
   Sculptor Kārlis Zāle is not just named — his specific carvings are described (riflemen, students, workers, a mother, a giant-slayer). The Soviet suppression section develops the meaning of silent resistance.
   (#278 — Quality 5. Person + monument + resistance, each developed.)

4. **Pilgrims and ritual (Asia, Culture/People)**
   Subject: Evening aarti at `Dashashwamedh Ghat`, Varanasi, India. Lens: **People** primary.
   - Describe pilgrims arriving with brass pots and flowers.
   - Narrate one evening ceremony: priests lifting lamps, the crowd echoing chants, offerings moving to the water.
   - Explain what this gathering means for people who travelled far, perhaps linking to a specific festival.

5. **Street food vendors (Asia, Cuisine/People)**
   Subject: A busy `Bangkok` street food alley in Yaowarat (Chinatown). Lens: **People** primary.
   - Follow one vendor's day: chopping garlic, stacking skewers, stirring a huge wok over roaring gas flames.
   - Describe small interactions with regulars and first-time visitors.
   - Explain how stalls often run in families and how recipes pass down.
```

**Why:** Examples 1-3 replaced with real discoveries showing Mode A (single moment, monument narrative) and Mode B. Examples 4-5 kept for Asian culture/cuisine coverage. Removed the Frida Kahlo (#1), Rio (#3), Fushimi Inari (#4), and Durbar Hall (#6) task-list examples — these were decent but still prescribe tasks rather than showing responses.

---

### CHANGE 12: Rewrite OBJECTS lens examples

**Location:** Lines 163-183 — `OBJECTS LENS` "Good Examples" section

**Current text (5 examples, ALL identical structure: describe → explain how → broader context):**
```
1. **Weapon as crafted technology (Europe, History/Objects)**...
2. **Ancient army in clay (Asia, History/Objects)**...
3. **Gold work as a record of a culture (Latin America, Art/Objects)**...
4. **Food object and its construction (Asia, Cuisine/Objects)**...
5. **Everyday tech model (Information/Objects)**...
```

**Replace with:**
```
1. **Mode A — Craft technique deep dive (Europe, Art/Objects)**
   Subject: `Choir stall wood inlays` in the Basilica dei Frari, Venice. Lens: **Objects** primary.
   Single thread: intarsia as the illusion of depth.
   > "Marco Cozzi used zero paint to create these intricate cityscapes in 1468. He spent seven years fitting thousands of tiny wood fragments together like a puzzle."
   > "Dark walnut forms the deep shadows. Pale willow creates the bright sunlight hitting the walls. This technique is called intarsia. In the 1400s, this mastery of perspective was a cutting-edge artistic technology."
   Every section develops the same thread: Solomonic columns and gold leaf catching candlelight, then acoustic properties for monks' chanting ("the curved wood surrounding each seat projected the sound deep into the church"). The craft IS the story.
   (#307 — Quality 5. Single craft technique explored across all sections.)

2. **Mode A — Technology meets social change (Europe, History/Objects)**
   Subject: An `ornate wheellock carbine` in a Polish museum. Lens: **Objects** primary.
   Opens with the object as status symbol, then explains the mechanical innovation:
   > "This wheellock replaced the flame with a rotating steel wheel and a piece of pyrite. It worked exactly like a modern cigarette lighter."
   Then develops the social consequence:
   > "Because a wheellock could be kept loaded and ready, a nobleman could carry it in a holster. It changed the social hierarchy of the battlefield."
   Final section adds sensory detail (weight, metallic grinding, acrid smoke). The technology's innovation AND its social meaning are both fully developed.
   (#261 — Quality 5. Technology explained, then its human impact developed.)

3. **Mode A — Architecture as political defiance (Europe, Architecture/Objects)**
   Subject: `St. Florian's Cathedral`, Warsaw. Lens: **Objects** primary.
   Single thread: Polish resistance expressed through architectural choice.
   > "In the late eighteen-hundreds, Warsaw was under the rule of the Russian Empire. The Tsars were building golden-domed Orthodox churches. Polish architects responded by constructing this sharp, pointed Gothic structure. They called it Vistula Gothic."
   Sections develop: destruction in 1944 ("retreating German forces planted explosives"), twenty-year reconstruction from original plans, physical scale (75m towers, red bricks, green copper), and the material texture changing with sunlight. Architecture as resistance, fully told.
   (#258 — Quality 5. One thesis across all sections. Specific dates, terms, physical details.)

4. **Food object and its construction (Asia, Cuisine/Objects)**
   Subject: A bowl of `ramen` in a small Tokyo shop. Lens: **Objects** primary.
   - Break down layers: broth, noodles, tare, toppings like chashu, egg, and nori.
   - Explain how each component is prepared (long-simmered stock, hand-pulled or factory noodles, marinated egg).
   - Mention the shop's specific style (tonkotsu, shoyu, miso) and how you can see that style in the bowl.

5. **Gold work as a record of a culture (Latin America, Art/Objects)**
   Subject: A pre-Columbian gold mask in the `Museo del Oro`, Bogota. Lens: **Objects** primary.
   - Describe the mask's hammered gold, stylised features, and holes for attachment.
   - Explain how gold was mined, refined, and worked in that culture.
   - Talk about how masks like this were worn in ceremonies or burials.
```

**Why:** Examples 1-3 replaced with real discoveries that show DIFFERENT approaches — not all "describe → explain how → broader context." Examples 4-5 kept for non-European cuisine/culture coverage. The Longsword, Terracotta Warrior, and Shinkansen were the worst offenders for formulaic structure; all three follow identical patterns that the model replicates mechanically.

---

### CHANGE 13: Rewrite PHYSICAL lens examples

**Location:** Lines 191-211 — `PHYSICAL LENS` "Good Examples" section

**Current text (5 examples):**
```
1. **Everyday rooftop view (Europe, Nature/Physical)**...
2. **Urban flow (Asia, Culture/Physical)**...
3. **Tight historic alleys (Africa/Arab world, Culture/Physical)**...
4. **Hilltop park viewpoint (South America, Nature/Physical)**...
5. **Quiet temple interior (Asia, Culture/Physical)**...
```

**Replace with:**
```
1. **Mode A — Geology as spiritual encoding (Turkey, History/Physical)**
   Subject: Rock-cut `Tomb of Amyntas`, Fethiye, Turkey. Lens: **Physical** primary.
   Single thread: Lycians encoded spiritual beliefs into stone architecture.
   > "High-status burials in ancient Lycia followed the belief that the soul reached the heavens faster from a great height. Carving a tomb directly into the limestone cliff was a radical way to ensure a family's legacy never moved."
   > "Craftsmen likely dangled from the top of the cliff on thick ropes for months. They worked in the blinding heat and constant dust of the limestone quarry."
   Every detail — soul-height belief, Greek columns as diplomatic statement, chisel marks, fatal fall risk — serves the central thesis. Physical experience (heat, dust, rope, danger) carries intellectual weight.
   (#192 — Quality 5. Physical sensation and historical meaning reinforce each other.)

2. **Mode B — Process with environmental stakes (Turkey, Nature/Physical)**
   Subject: Close-up of `travertine terraces` at Pamukkale. Lens: **Physical** primary.
   Four aspects, each fully developed:
   > "Every ridge you see began as a tiny obstacle like a pebble or a twig. As warm thermal water poured over these bumps, it slowed down for a split second. This tiny pause allowed the minerals to settle and harden into solid stone."
   Then develops color chemistry (white = high minerals; brown = clay traces), and crucially:
   > "For decades, hotels at the top diverted water for swimming pools. Without the constant flow, the white stone turned grey and brittle. Today, authorities strictly control the water flow."
   The environmental crisis section gives the whole piece real stakes. Physical process + consequence.
   (#302 — Quality 4-5. Mechanism explained, then contemporary crisis adds urgency.)

3. **Mode A — Engineering as invisible luxury (Latvia, Architecture/Physical)**
   Subject: `Ceramic stoves` in Rundāle Palace. Lens: **Physical** primary.
   Single thread: heat as engineered invisibility.
   > "While royalty danced or played cards on this side, workers hauled heavy logs in the dark passages next door. To the people in this room, the heat felt like a silent, invisible miracle."
   The ceramic-as-heat-battery mechanism, the hidden servant passages, and the contrast between visible wealth and invisible labor all develop one idea through sensory experience.
   (#199 — Quality 4. Physical sensation IS the meaning.)

4. **Tight historic alleys (Africa/Arab world, Culture/Physical)**
   Subject: A narrow alley in the `Marrakech medina`, Morocco. Lens: **Physical** primary.
   - Describe shoulder-width passages and uneven stones underfoot.
   - Mention smells of leather, spices, and food drifting from nearby stalls.
   - Suggest glancing up at small slices of sky and how light suddenly opens at each small square.

5. **Quiet temple interior (Asia, Culture/Physical)**
   Subject: Inner hall of a small Buddhist temple in Kyoto. Lens: **Physical** primary.
   - Guide: take off shoes, feel tatami or wooden floor under feet, and the cool dimness after bright sun.
   - Describe incense smell, the slight creak of wood, the sound of a distant bell.
   - Invite closing eyes for a moment to sense breathing and space, then opening them to pick one detail.
```

**Why:** Examples 1-3 replaced with real discoveries. Examples 4-5 kept (they handle good regions and the Physical lens already resists breadth naturally).

---

## Priority 3 — Cold Start, Zoom-Out, Sideways (REQ-8 through REQ-10)

---

### CHANGE 14: Rewrite cold start examples (REQ-8)

**Location:** Lines 370-378 — inside `Cold start heuristics` section

**Current text (task-list format):**
```
- Example (mid-sized city square in Europe):
  - Primary lens: **Ideas** or **People**, Flip lens: e.g. **Objects**.
  - Identify the scene (cafes, town hall, fountain), explain how such squares evolved, tell one concrete story typical of this region and era, and flip with an Objects-focused note on a single element.
- Example (anonymous painting in a local museum):
  - Primary lens: **Ideas** (with Objects), Flip lens: **People**.
  - Use visual clues to infer style, explain what that style explored, talk about painters' lives, flip with a short People-focused moment about a plausible sitter/viewer.
- Example (small ramen shop in a Japanese city):
  - Primary lens: **Objects** or **People**, Flip lens: **Ideas**.
  - Describe the bowl, tie it to region, mention ordering rituals, flip with an Ideas-focused note on regional ramen styles.
```

**Replace with:**
```
- Approach guidance: If the subject has one rich story (a painting of a specific battle, a monument to a specific person), tell that story across the sections (Mode A). If the subject is broad (a palace, a square, a bowl of ramen), cover a few aspects but give each one real development (Mode B). Either way: whatever you mention, develop it. No name-drops.

- Example — Mode A cold start (specific subject):
  Subject: An `ornate wheellock carbine` in a museum.
  Primary lens: **Objects**. One thread across all sections: the mechanism, then its social consequence.
  > "This wheellock replaced the flame with a rotating steel wheel and a piece of pyrite. It worked exactly like a modern cigarette lighter."
  > "Because a wheellock could be kept loaded and ready, a nobleman could carry it in a holster. It changed the social hierarchy of the battlefield."
  Names the object early, explains how it works, then develops what it meant. Flip section adds sensory detail (weight, grinding sound, acrid smoke).

- Example — Mode B cold start (broad subject):
  Subject: `Vilnius cityscape` from a hilltop.
  Primary lens: **Ideas**. Multiple aspects, each developed.
  > "Vilnius earned its nickname because it has more Baroque churches per capita than almost anywhere else. This density was not an accident. During the sixteen-hundreds, the Catholic Church used grand buildings to win back followers."
  Names and identifies the view early. Each section covers one aspect (church density → architectural eras → Cathedral as anchor → sensory golden hour). None gets less than a full paragraph of real knowledge.

- Example — Mode A cold start (food):
  Subject: A bowl of `ramen` in a small Tokyo shop.
  Primary lens: **Objects**. Describe the bowl, then develop what makes this specific style distinctive.
  Break down layers: broth, noodles, tare, toppings. Explain how each component is prepared. Name the shop's style (tonkotsu, shoyu, miso) and show how you can see that style in the bowl.
```

**Why:** Replaces mechanical task lists ("identify → explain → tell → flip") with real examples showing both modes. The model learns from the structure of the examples, not from a checklist of tasks.

---

### CHANGE 15: Refine zoom-out criteria (REQ-9)

**Location:** Line 95 — `LENS PLAYBOOK` Shared principles

**Current text:**
```
- It is fine to **zoom out tangentially** (e.g., Middle Ages nobles, Edo-period merchants, Mughal courts, Mayan city-states, Brazilian street football, Bangkok street food culture) as long as details are true and plausibly connected.
```

**Replace with:**
```
- It is fine to **zoom out tangentially** when the specific subject is narrow and zooming out would provide a richer, more specific response. When zooming out, land on a SPECIFIC story or fact — not a generic description of an era or practice. The zoom-out should make the response MORE specific, not less.
  - ✓ "In January 1991, thousands of people from these very towns flooded into Riga. They brought tractors and heavy trucks to block the narrow streets." (#184 — Zooms from a heraldic wall to a specific 1991 event. Vivid and real.)
  - ✓ "For decades, hotels at the top diverted water for swimming pools. Without the constant flow, the white stone turned grey." (#302 — Zooms from geology to a specific contemporary crisis.)
  - ❌ "The symbols on these shields follow the ancient rules of heraldry." (#184 — Zooms from a specific memorial to generic heraldry principles that apply everywhere.)
  - ❌ "Adopting these foreign shapes served as a diplomatic statement of wealth and sophisticated taste." (#192 — Generic cultural-signaling language. Instead, tell us about Lycia specifically.)
```

**Why:** Removes the parenthetical list of generic categories (Middle Ages nobles, Edo-period merchants, etc.) that taught the model to zoom to categories rather than stories. Adds real ✓/❌ examples.

---

### CHANGE 16: Remove "sideways angles" (REQ-10)

**Location:** Line 96 — `LENS PLAYBOOK` Shared principles

**Current text:**
```
- **Cold start "obvious first" rule**: on the first discovery for a subject, start with the most obvious identity and story (T. rex -> dinosaur apex predator; famous painting -> what it shows and why it is known; major square -> what it is and why it matters; food -> what the dish is and how people actually eat it). Deeper or sideways angles can appear later.
```

**Replace with:**
```
- **Cold start "obvious first" rule**: on the first discovery for a subject, start with the most obvious identity and story (T. rex -> dinosaur apex predator; famous painting -> what it shows and why it is known; major square -> what it is and why it matters; food -> what the dish is and how people actually eat it). Deeper angles can appear in subsequent discoveries about the same subject.
```

**Why:** "Sideways angles" is breadth by another name.

---

### CHANGE 17: Rewrite multi-photo strategies (REQ-10 continued)

**Location:** Line 382 — `Same subject, multiple photos` section

**Current text:**
```
- Strategies: keep same primary lens but go deeper/different angle; switch lens while building on earlier content; zoom in on one previously mentioned element.
```

**Replace with:**
```
- Strategies: keep same primary lens but go deeper on an aspect not yet covered; zoom in on one previously mentioned element and develop it fully. Avoid switching to a completely new topic — build on what was already established.
```

**Why:** Two of three original strategies were breadth-focused ("different angle" and "switch lens"). Only "zoom in on one previously mentioned element" was about depth — now it's the primary strategy.

---

## Before/After Summary

### What gets REMOVED:
- "while touching others only when valuable" (Line 73)
- "optionally touch lightly upon other lenses" (Line 87)
- "always include a Flip section" → changed to "generally include"
- Parenthetical generic categories in zoom-out (Line 95)
- "or sideways" (Line 96)
- "switch lens while building on earlier content" and "different angle" (Line 382)
- 9 of 21 lens playbook examples (replaced with real discoveries)
- 3 cold start task-list examples (replaced with real examples)

### What gets ADDED:
- Name-drop ban with NAME-DROP TEST and ❌/✓ examples
- Undeveloped mentions pattern ban with ❌/✓ examples
- Unsupported superlatives banned phrase (#6) with ❌/✓ examples
- Development check in pre-flight checklist
- Development criterion in quality bar
- Word budget distribution (Mode A / Mode B)
- 9 real discovery-based lens playbook examples (#195, #303, #254, #265, #257, #278, #307, #261, #258, #192, #302, #199)
- 3 real discovery-based cold start examples
- Zoom-out ✓/❌ examples with real discovery quotes

### What stays UNCHANGED:
- Hook guidance (WRITING THE FIRST H2) — already good
- Context-driven heuristics — already good
- Connection tests — already good
- Show don't tell / scaffolding test / unpack abstract nouns — already good
- Banned phrases 1-5 — already good
- Special cases (museum panels, signs, selfies) — already good
- Output format — unchanged
- Physical lens examples 4-5, People lens examples 4-5, Objects lens examples 4-5, Ideas lens examples 4-5 — kept for regional/subject coverage

---

## Anti-Pattern Quick Reference (for DO NOT section)

Best single example of each anti-pattern, ready for the prompt:

| Anti-Pattern | Best Bad Example | Key Quote |
|---|---|---|
| Topic-per-section | #289 St. Nicholas Church | Five topics (Dientzenhofer → Baroque theology → Mozart → Platzer → dome). Mozart gets 2 sentences then vanishes. |
| Name-drop | #194 Freedom Monument | "Only the intervention of a famous sculptor saved the structure." — WHO? Never named, never developed. |
| Unsupported superlative | #292 Cranach's Grumpy Cupid | "Most powerful artist in 16th-century Germany" — No evidence of what made him powerful. |
| Formulaic structure | #295 Saint's New Home | Uniformly 6 sentences per section, each topic completely isolated. |
| Atmosphere as substitute | #323 Latgalian Dowry Chest | "Imagine the heavy thud" / "you can almost hear" — Evokes without educating. |

Best single example of each quality pattern:

| Quality Pattern | Best Good Example | Key Quote |
|---|---|---|
| Mode A deep dive | #265 The Last Senate | "A government that lasted eleven centuries vanished in a single afternoon." One moment, fully told. |
| Mode B multi-aspect | #257 Meeting in Damascus | Four aspects (ceremony, turbans, trade diplomacy, imagined city), each 3-5 sentences of real substance. |
| Earned superlative | #195 Great Council Chamber | "Tintoretto's Paradise, measuring twenty-five meters wide. It contains hundreds of figures." Size claim + evidence. |
| Good zoom-out | #302 Nature's Tiny Dams | Zooms from geology to environmental crisis — "hotels diverted water, stone turned grey." Specific, vivid, consequential. |
| Developed person | #278 Freedom Monument | Kārlis Zāle named AND his specific carvings described (riflemen, students, mother, giant-slayer). |
