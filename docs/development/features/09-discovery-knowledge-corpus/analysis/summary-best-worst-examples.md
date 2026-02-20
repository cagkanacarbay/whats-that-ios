# Discovery Quality Summary — All 100 Analyzed Discoveries

Cross-batch synthesis for system prompt v0.9.0 lens playbook upgrade.

**Source:** batch-1 (IDs 303-325), batch-2 (282-302), batch-3 (259-280), batch-4 (230-258), batch-5 (192-229)

---

## Quality Distribution (100 discoveries)

| Quality | Count | % | Description |
|---------|-------|---|-------------|
| 5 | 25 | 25% | Exemplary — prompt-ready examples |
| 4 | 24 | 24% | Strong — usable with minor caveats |
| 3 | 34 | 34% | Mixed — one good section, 2-3 shallow ones |
| 2 | 14 | 14% | Poor — pervasive anti-patterns |
| 1 | 3 | 3% | Severe — museum placard energy, incomplete |

**Key finding:** Quality is bimodal. Nearly half (49%) are Quality 4-5 and demonstrate what depth looks like. The other half have structural issues that the prompt upgrade must address.

---

## All Quality 5 Discoveries by Lens

### IDEAS (2 Quality 5)

| ID | Title | Mode | What makes it excellent |
|----|-------|------|------------------------|
| **#254** | Titian's Rising Virgin | A | Single thesis: Titian revolutionized emotion and scale. Friars' rejection → apostles' grief poses → Mary's red dress color → three-level composition → 7m altarpiece as statement. Every section deepens understanding of one artwork. |
| **#270** | The Anti-Alkoran of 1614 | A | Single thesis: theological attack as political weapon. Author's 7 years in Istanbul → political context of Bohemian civil war → visual woodcut symbolism → eschatological framework. Every element developed with specificity. |

**Ideas gap:** Only 2 Quality 5 in Ideas lens. Supplement with strong Quality 4s: #247 (Massacre of the Innocents), #252 (Stealing Saint Mark), #257 (Meeting in Damascus), #308 (Brazen Serpent). Of these, **#257** is strongest — 4 aspects each fully developed, great Mode B example.

### PEOPLE (6 Quality 5)

| ID | Title | Mode | What makes it excellent |
|----|-------|------|------------------------|
| **#316** | Ghetto Heroes Monument | A | Hitler's stone repurposed, military specifics of 1943 revolt, Rapoport's sculptural choices, front-vs-back duality. One story fully told. |
| **#297** | Prague's National Theatre | A | Czech cultural resistance: citizen funding → symbolic foundation stones → fire and rebuilding in 6 weeks → craftsmen proving Czech excellence. One narrative arc. |
| **#259** | Collegium Novum | B | Four aspects each developed: Neo-Gothic identity, red brick as Polish statement, Copernicus/Wojtyla legacy, 1939 Nazi arrest of 183 professors. |
| **#260** | The Doge's Humble Plea | A | Dandolo's crawl to the Pope → earned nickname "The Dog" → Paolo Veneziano as first Venetian master → tomb surviving architectural demolition. |
| **#233** | King Stephen Báthory | B | Electoral system, religious tolerance ("ruler of people, not consciences"), military modernization, personal outsider detail (never learned Polish). |
| **#198** | Blackhead Epitaph | A | Bachelor merchants' guild: trade duties → legendary feasts → Saint Maurice patronage → woodwork craftsmanship. Single institution across all sections. |

### OBJECTS (7 Quality 5)

| ID | Title | Mode | What makes it excellent |
|----|-------|------|------------------------|
| **#307** | Wood Inlays of Frari | B | Intarsia technique: perspective illusion with wood species → Solomonic columns + gold leaf → acoustic function for monks. Craft IS the story. |
| **#311** | Raspberry Garnets | B | Mineral deep dive: dodecahedral geometry → manganese chemistry → contact metamorphism thermometry. Scientific precision. |
| **#313** | Neuruppin Picture Sheet | B | Cheap prints: hand-coloring technique → Neuruppin's printing dominance → saints-as-household-insurance. Social function developed. |
| **#323** | Latgalian Dowry Chest | A | Single narrative: pre-marriage weaving → wedding-day inspection → Latgale regional style + ironwork → sensory journey. |
| **#282** | A Hoplite in Red | B | Citizen-soldier identity → symposium culture → red-figure technique evolution → artistic revolution. Each aspect 4+ sentences. |
| **#290** | The Granite Basin | B | Social gathering → Hummel's perspective mastery → civic transformation → 70-ton boulder engineering. |
| **#199** | Stoves of Rundāle | B | Ceramic aesthetics → heat-battery mechanism → hidden servant labor. Technical precision + social dimension. |

### PHYSICAL (10 Quality 5)

| ID | Title | Mode | What makes it excellent |
|----|-------|------|------------------------|
| **#306** | Kaunas Castle | A | Defensive engineering: river convergence → stone-to-brick transition → peninsula geography → weaponized landscape. |
| **#312** | Trakai's Water Fortress | A | Three-zone water barrier: town → peninsula → island. Painting-as-historical-map thread connects all. |
| **#317** | Tower of Seven Lives | A | Seven collapses: merchant-vs-bishop power → 1941 fire → Soviet steel reconstruction → golden rooster legend. |
| **#293** | The Virgin's Crown | B | Plague vow (1/3 of Venice died) → Longhena's 50-year obsession → octagonal crown geometry → white stone color changes. |
| **#268** | Byzantium in the West | B | Serbian Orthodox church: Habsburg free port → economic rivalry with Venice → architectural identity contest → gold mosaic technique. |
| **#230** | Chapel of St. Kinga | A | Salt chapel materiality: carved floor → salt chandeliers → Last Supper in salt → 100m underground air quality. |
| **#232** | Hallstatt Market Square | B | Salt trade → Holy Trinity Column → vertical geography forcing architecture → recycled cemetery. |
| **#192** | Tomb of Amyntas | B | Soul-height belief → wooden-house-to-stone translation → Greek columns as diplomacy → cliff-face construction danger. |
| **#195** | Great Council Chamber | B | 2000 noblemen voting → art as state propaganda → Tintoretto's 25m Paradise → sensory weight of gilded ceiling. |
| **#200** | Courtyard of the Doge | B | Coronation staircase → administrative chaos → Mars/Neptune statues → bronze wellheads for drinking water. |

---

## Top Prompt Candidates Per Lens (Recommended Replacements)

Each lens in the current prompt has 5-6 examples. The change spec replaces the top 3 in each lens with real discoveries, keeping 2 synthetic examples for regional/subject diversity.

### IDEAS — Replace examples 1-3 with:

1. **Mode A: #254 (Titian's Rising Virgin)** — Art analysis as single thesis
   > "When this painting was unveiled in 1518, the friars of this church initially tried to reject it."
   Every section deepens one artwork's revolutionary qualities. No tangents to "other Renaissance painters."

2. **Mode B: #257 (Meeting in Damascus)** — Multi-aspect diplomacy (Quality 4, strongest Ideas Mode B available)
   > "The language of the turban: each fold and shape signaled a man's rank, profession, and religious status."
   Four aspects (ceremony, turbans, trade pragmatism, imagined city), each 3-5 sentences.

3. **Mode A: #270 (Anti-Alkoran of 1614)** — Theological text as political weapon
   > "Published in 1614, the Anti-Alkoran was a fierce theological attack on the Ottoman Empire and its faith."
   Author's credentials → political context → visual symbolism → eschatological framework.

### PEOPLE — Replace examples 1-3 with:

1. **Mode A: #316 (Ghetto Heroes Monument)** — Single dramatic moment
   > "The stone used to build this monument was originally ordered by Adolf Hitler for a victory arch."
   One story: Hitler's stone → 1943 revolt specifics → Rapoport's sculpted fighters → front-vs-back duality.

2. **Mode B: #233 (King Stephen Báthory)** — Political biography with depth
   > "Most European kings in the sixteenth century gained power through birth. Stephen Báthory took a different path."
   Electoral system, religious tolerance, military reform, personal outsider detail. Each aspect 4+ sentences.

3. **Mode A: #297 (Prague's National Theatre)** — Cultural resistance narrative
   > "The people of Prague built this theater twice in three years to prove their culture survived."
   Citizen funding → symbolic stones → fire and 6-week rebuild → craftsmen's sandstone and gold leaf.

### OBJECTS — Replace examples 1-3 with:

1. **Mode B: #307 (Wood Inlays of Frari)** — Craft technique deep dive
   > "Marco Cozzi used zero paint to create these intricate cityscapes in 1468."
   Intarsia as perspective technology → wood species as color palette → Solomonic columns → acoustic function.

2. **Mode B: #282 (A Hoplite in Red)** — Object-as-social-window
   > "This painted warrior was likely a real person in the eyes of the ancient Greeks. He is a hoplite."
   Citizen-soldier identity → symposium culture → red-figure technique → artistic revolution.

3. **Mode A: #323 (Latgalian Dowry Chest)** — Single narrative through one object
   > "A Latgalian bride arrived at her new home with years of labor locked inside this chest."
   Pre-marriage weaving → wedding inspection → Latgale regional style + ironwork → sensory journey.

### PHYSICAL — Replace examples 1-2 with:

1. **Mode A: #306 (Kaunas Castle)** — Defensive engineering as single thread
   > "This castle was the first brick fortress built in Lithuania to stop a religious war."
   River convergence → stone-to-brick tech → peninsula trap → weaponized landscape.

2. **Mode B: #192 (Tomb of Amyntas)** — Geology + spirituality + craft
   > "High-status burials in ancient Lycia followed the belief that the soul reached the heavens faster from a great height."
   Soul belief → wood-to-stone translation → Greek columns as diplomacy → cliff construction danger.

3. **Mode A: #230 (Chapel of St. Kinga)** — Single material explored through senses
   > "Everything you see in this massive chamber is carved from solid rock salt."
   Floor polish → salt chandeliers → Last Supper in relief → 100m depth + air quality.

---

## Anti-Pattern Catalogue — The Worst Examples

### Anti-Pattern 1: Topic-Per-Section (most common, ~40% of all discoveries)

Each H2 introduces an unrelated topic with 3-4 sentences, then moves on. The listener gets a tour of disconnected facts.

**Clearest example: #267 (Drechsler Palace)** — Quality 2
Four completely unrelated topics: opera rivalry → pension fund → ballet school → luxury hotel. No narrative thread.
> "In the mid-twentieth century, the palace underwent a radical change. The state converted the grand apartments into the Hungarian National Ballet Institute."
[New topic introduced, zero connection to opera rivalry in previous section]

**Other strong examples:**
- **#280 (Chapel Carter's Snap)** — Quality 1. Nail clipper gets 4 disconnected micro-topics. Museum placard energy.
- **#239 (Kaunas Castle)** — Quality 1. Ghost legend → 1362 siege → prison → building materials → river. Five topics, none connected.
- **#266 (Heart of the State)** — Quality 2. Generic Doge's room: decisions → Veronese → Tintoretto → 24-hour clock.
- **#324 (Roland of Gdansk)** — Quality 2. Free city symbol → Hanseatic League → Charlemagne legend. Each H2 new topic.

### Anti-Pattern 2: Name-Drop and Move On

A person, event, or institution is mentioned in 1-2 sentences then abandoned. The most interesting story gets thrown away.

**Clearest example: #194 (Freedom Monument, batch 5 version)** — Quality 2
> "Only the intervention of a famous sculptor saved the structure. She argued that its artistic value was more important than its political message."
A famous sculptor who saved a national monument from demolition — WHO? Never named, never developed. THE story of this monument gets two sentences.

**Compare with #278 (Freedom Monument, batch 3 version)** — Quality 3 (improved but still not 5)
> "The sculptor Kārlis Zāle spent years carving these massive blocks of granite and travertine. Look at the base to see the groups of figures he created."
Same monument, sculptor now NAMED and DEVELOPED. This contrast demonstrates the fix.

**Other strong examples:**
- **#289 (St. Nicholas Church)** — Mozart gets 2 sentences: "sat at the organ in 1787. He fell in love with the acoustics." Then text moves to Platzer.
- **#253 (Altar of Saint Anthony)** — "miracle of a greedy man whose heart was found in a money chest" — ONE sentence, then abandoned. That's a whole story.
- **#255 (Hofburg Palace)** — Empress Elisabeth "felt trapped by the strict rules of this royal court. She frequently fled the palace." One sentence, done.

### Anti-Pattern 3: Unsupported Superlatives

Large claims made with zero supporting evidence. "Famous for," "legendary," "one of the greatest" followed by nothing.

**Clearest example: #231 (King Augustus III)** — Quality 2
> "Augustus was famous for hating the battlefield. He never once led his troops into a major combat."
What did he do INSTEAD? "Sought glory through beauty" — which beauty? "Master paintings that still fill museums" — which paintings? Which museums? Nothing specific.

**Other strong examples:**
- **#289 (St. Nicholas Church)** — "Platzer was the most famous sculptor in Bohemia at the time." What did he sculpt? Why famous?
- **#251 (Vienna Jubilee Church)** — "Neo-Romanesque for a very specific reason" → "project an image of ancient and unbreakable strength." That's a generic observation, not a specific reason.
- **#299 (Portrait of Duke Biron)** — "For ten years, Biron effectively ruled Russia." Massive claim, zero examples of what decisions he made.

**Compare with examples that EARN their superlatives:**
- **#195** — "Tintoretto's Paradise, measuring twenty-five meters wide. It contains hundreds of figures." Size claim backed by measurement.
- **#195** — "Up to two thousand noblemen gathered here to vote." Number makes the claim real.
- **#306** — "In 1362, the Teutonic Knights spent three weeks trying to break through." Specific date, specific duration, specific attacker.

### Anti-Pattern 4: Atmosphere as Substitute for Knowledge

Evocative sensory language used to fill space where historical/technical content should be. The listener feels something but learns nothing.

**Clearest example: #239 (Kaunas Castle)** — Quality 1
> "A legendary queen and her army supposedly sleep beneath these massive brick walls. Locals say Queen Bona Sforza hid her treasure. People believe the ghosts of those soldiers still march through the courtyard at night. If you listen closely, you might hear the faint sound of iron boots on stone."
Entire opening section is unverifiable folklore using "supposedly," "locals say," "people believe."

**Other examples:**
- **#265 (The Last Senate)** — "Imagine the heavy silence in the courtyard. The only sound is the rhythmic clicking of leather shoes against the marble." Manufactured emotion replaces historical content about what happened after the Republic fell.
- **#323 (Latgalian Dowry Chest, final section)** — "Imagine the heavy thud of this lid closing. You can almost hear the iron hinges creak." — Note: this is borderline. The REST of #323 is excellent Quality 5 — the atmospheric section works BECAUSE the previous 3 sections delivered real knowledge. Atmosphere fails when it REPLACES knowledge. It works when it SUPPLEMENTS it.

### Anti-Pattern 5: Formulaic Structure

Every section follows the same length and pattern. Uniform 5-6 sentences per H2, each topic completely isolated from the others.

**Clearest example: #295 (The Saint's New Home)** — Quality 3
Every H2 is exactly 5-6 sentences. Railway displacement → Grand Canal facade → Lucy's body → church interior. Sections could be reordered with no loss of coherence, proving they have no narrative connection.

---

## Mode Distribution Analysis

### Quality 5 discoveries by mode:

| Mode | Count | % |
|------|-------|---|
| Mode A (single-story) | 13 | 52% |
| Mode B (multi-aspect) | 12 | 48% |

**Key insight:** Both modes work equally well at top quality. The problem isn't choosing one mode over the other — it's the EXECUTION. Quality 5 Mode B discoveries develop each aspect. Quality 2 Mode B discoveries mention each aspect.

### Mode A vs Mode B by lens:

| Lens | Mode A Q5 | Mode B Q5 | Observation |
|------|-----------|-----------|-------------|
| Ideas | 2 | 0 | Ideas lens favors single-thesis deep dives |
| People | 4 | 2 | People lens works both ways, slight Mode A advantage |
| Objects | 1 | 6 | Objects lens strongly favors multi-aspect (material + technique + social meaning) |
| Physical | 4 | 6 | Physical works both ways, slight Mode B advantage |

**Implications for prompt:**
- Ideas examples should emphasize Mode A (single thesis)
- Objects examples should show Mode B variety (material, technique, social impact — but DEVELOP each)
- People and Physical should show both modes

---

## Bad Example Quick Reference for DO NOT Section

Best single example of each anti-pattern, ready for prompt use:

| Anti-Pattern | Best Example | Discovery Text |
|---|---|---|
| **Topic-per-section** | #267 Drechsler Palace | 4 unrelated topics (opera → pension → ballet → hotel). No thread. |
| **Name-drop** | #194 Freedom Monument | "Only the intervention of a famous sculptor saved the structure." — WHO? Never named. |
| **Unsupported superlative** | #231 King Augustus III | "Famous for hating the battlefield" → no evidence of what he did instead. |
| **Atmosphere replaces knowledge** | #239 Kaunas Castle | "Locals say ghosts still march at night." Entire section is unverifiable folklore. |
| **Formulaic structure** | #295 Saint's New Home | 5-6 sentences per section, each completely isolated, sections reorderable. |

Best single example of each quality pattern:

| Quality Pattern | Best Example | Key Feature |
|---|---|---|
| **Mode A deep dive** | #316 Ghetto Heroes Monument | "A government that lasted eleven centuries vanished in a single afternoon." One story, fully told through material and visual language. |
| **Mode B multi-aspect** | #282 A Hoplite in Red | Four aspects (citizen-soldier, symposium, red-figure technique, artistic revolution), each 4+ sentences of real substance. |
| **Earned superlative** | #195 Great Council Chamber | "Tintoretto's Paradise, measuring twenty-five meters wide. It contains hundreds of figures." Size claim + specific evidence. |
| **Good zoom-out** | #302 Nature's Tiny Dams | Zooms from geology to environmental crisis — "hotels diverted water, stone turned grey." Specific, vivid, consequential. |
| **Developed person** | #316 Ghetto Heroes Monument | Mordechai Anielewicz named, his role explained, his sculpted expression described, his fighters' month-long stand developed. |
| **Technical depth** | #307 Wood Inlays of Frari | "Dark walnut forms the deep shadows. Pale willow creates the bright sunlight." Technique explained through specific materials. |

---

## Cross-Batch Patterns

### What separates Quality 5 from Quality 3:

Quality 5 discoveries **commit** to their threads. Quality 3 discoveries **sample** threads.

A Quality 3 discovery typically has one good section (4-6 sentences of real depth) surrounded by 2-3 thin sections (3-4 sentences of surface-level description). The writer shows they CAN do depth — they just don't sustain it.

Example: #223 (St. Mark's Basilica, Quality 3)
- Section about gold mosaics: EXCELLENT (glass tiles at angles, sun makes walls "glow like living fire")
- Section about bronze horses: 3 sentences, abandoned
- Section about stolen saint: 3 sentences, abandoned

The fix is not "write longer." The fix is "cover fewer things and develop each one."

### Batch quality variation:

| Batch | Q5 | Q4 | Q3 | Q1-2 | Best Batch? |
|-------|----|----|----|----|---|
| Batch 1 (303-325) | 8 | 4 | 5 | 3 | **YES — highest Q5 count** |
| Batch 2 (282-302) | 4 | 3 | 12 | 1 | Most Q3 (many almost-good) |
| Batch 3 (259-280) | 4 | 3 | 8 | 5 | Most Q1-2 |
| Batch 4 (230-258) | 4 | 8 | 1 | 7 | Strongest Q4 showing |
| Batch 5 (192-229) | 5 | 6 | 8 | 1 | Strong top-end |

### What the best discoveries share:

1. **Every mention is developed.** If a person is named, their story is told (3+ sentences). If an event is referenced, what happened is explained.
2. **Sections build or connect.** Even in Mode B, sections feel related rather than random.
3. **Specific > generic.** "In 1362, the Teutonic Knights spent three weeks" beats "for centuries, armies attacked."
4. **Sensory detail supplements knowledge.** Atmosphere works when it follows substance. It fails when it replaces substance.
5. **Numbers and dates are used sparingly but precisely.** "Twenty-five meters wide" or "two thousand noblemen" — not "many people" or "a large painting."

---

## Implementation Checklist

For upgrading the system prompt lens playbook (Changes 10-13 in the change spec):

- [ ] IDEAS lens: Replace examples 1-3 with #254 (Mode A), #257 (Mode B), #270 (Mode A)
- [ ] PEOPLE lens: Replace examples 1-3 with #316 (Mode A), #233 (Mode B), #297 (Mode A)
- [ ] OBJECTS lens: Replace examples 1-3 with #307 (Mode B), #282 (Mode B), #323 (Mode A)
- [ ] PHYSICAL lens: Replace examples 1-2 with #306 (Mode A), #192 (Mode B), #230 (Mode A)
- [ ] Cold start examples: Use #261 (Objects Mode A), #303/similar (Ideas Mode B), ramen (Objects Mode B kept)
- [ ] Zoom-out ✓/❌: Use #302 good zoom-out, #192 bad zoom-out (generic Mediterranean elite)
- [ ] Anti-patterns for DO NOT: #267 (topic-per-section), #194 (name-drop), #231 (superlatives), #239 (atmosphere filler)

### Discovery IDs needed for database text extraction:

**For lens playbook examples:** 192, 230, 233, 254, 257, 270, 282, 297, 306, 307, 316, 323

**For cold start examples:** 261, 303

**For anti-pattern ❌ examples:** 194, 231, 239, 267, 289, 253, 255

**For ✓ examples already in change spec:** 195, 278, 302, 261
