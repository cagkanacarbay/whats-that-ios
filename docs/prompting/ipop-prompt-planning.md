# IPoP‑Driven Prompt Planning for Singular v2

This document describes how we apply the Smithsonian IPOP model to the `singular_v2` prompts for the
What's That discovery assistant. It covers:

- A summary of the IPOP theory and its Attract / Engage / Flip dynamics.
- How we map that theory into our per‑discovery behavior.
- Which cases are **outside** the IPOP lens logic (e.g. signs, information panels).
- A lens playbook with concrete examples.
- Heuristics for using user history (`userDiscoveryContext`, `recentFullDiscoveries`) to pick lenses and content.
- Patterns to avoid so responses stay specific and non‑generic.

The goal is that this document can be translated almost directly into the system/user prompts, with minimal
adaptation for token limits and formatting.

---

## 1. IPOP theory in brief

The Smithsonian IPOP model (Pekarik et al.) is a predictive theory about **experience preferences**:

- People differ in the *kind* of experience they are most drawn to.
- These preferences influence:
  - **What they notice** (where they stop and pay attention).
  - **What they do** (which exhibition they enter, how long they engage).
  - **How they judge quality** (whether the visit feels merely “good” or truly “special”).

The four IPOP dimensions are:

- **Ideas (I)** – an attraction to concepts, abstractions, linear thought, facts and reasons.
- **People (P)** – an attraction to human connection, affective experience, stories, and social interactions.
- **Objects (O)** – an attraction to things, aesthetics, craftsmanship, ownership, and visual language.
- **Physical (Ph)** – an attraction to somatic sensations, including movement, touch, sound, taste, light, and smell.

Everyone uses all four, but in different strengths; typically one dimension is more dominant for a given person.

### 1.1 Attract / Engage / Flip in IPOP

The Smithsonian work describes three linked effects:

- **Attract** – preferences influence **what people notice**.

  - People tend to stop at exhibition elements that match their dominant IPOP dimension
    (e.g. strong People scorers stop more at story‑heavy panels).
- **Engage** – preferences influence **what people do**.

  - IPOP profiles correlate with which exhibitions people choose and how long they stay at particular stops.
- **Flip** – preferences influence **how people rate the experience**.

  - When visitors get the kind of experience they usually seek, they tend to rate it as good/excellent.
  - When they also have a strong, unexpected experience in a **non‑dominant** dimension, they are more
    likely to rate it as “superior” or especially memorable. This is called a **flip**.

The practical takeaway from the museum work:

- Offer solid experiences in the dimensions people already like (Ideas, People, Objects, Physical).
- Intentionally design occasional “flip” moments that open a different dimension than they normally seek.

---

## 2. How IPOP applies to What's That

In our setting, a “discovery” is a short, on‑site audio‑guide narrative plus metadata, generated in response to a
photo (and context) taken by the user.

We adapt IPOP as follows:

- For each discovery, the AI:
  - Chooses one **primary lens**: Ideas, People, Objects, or Physical.
  - Optionally chooses one **flip lens**, different from the primary.
- The narrative structure:
  - **Attract** – the first H2 section uses the **primary lens** to hook the user in the way that lens describes
    (a sharp idea, a human story, a striking material detail, or a sensory moment).
  - **Engage** – the middle sections deepen that same lens, occasionally touching other IPOP dimensions where they
    clearly add value.
  - **Flip** – when a flip lens is chosen, the final H2 section uses it to give an **unexpected perspective** on the
    same subject, in a different IPOP dimension. When no flip lens is chosen, the final section continues in the
    primary lens.

Over time:

- We will log which lenses were used for each discovery in `metadata_json`.
- Later, the app can aggregate these per user and compute approximate IPOP preference profiles.
- Those profiles can be fed back into the prompt via `customContext` to guide the model to respond more specifically in the users preferred lenses more often.

For now, the model is **stateless** beyond the context we give it:

- It infers what might be interesting from:
  - The current image and location.
  - `userDiscoveryContext` (titles + short descriptions of prior discoveries).
  - `recentFullDiscoveries` (full text of recent narratives).
  - Any hints we eventually place in `customContext`.

We use IPOP to:

- Decide **what kind of experience** to deliver (Ideas / People / Objects / Physical).
- Decide **how to structure** each response (Attract / Engage / Flip).
- Log the lens choices so we can learn about user preferences later.

---

## 3. Special cases outside the IPOP lens logic

Some input photos are not primarily about a place or object, but about **signs, maps, information panels**, or
**the user themselves**.

In these cases, we do **not** always treat the literal content of the image as the subject for IPOP lens selection.
Instead:

- We treat the sign as a *window onto* another subject:
  - A rock or fossil.
  - A room or gallery.
  - A trail, metro line, or route.
  - A set of rules or instructions the user needs to follow.
- We treat selfies and portraits as a moment to briefly acknowledge the user, not to analyse them in depth.
- IPOP lenses apply to the **underlying subject**, not to the sign as a piece of design or to the user’s body.

Special‑case behavior:

- **Museum information panels**

  - Do not describe the panel as an object (materials, layout) unless there is truly nothing else to work with.
  - Extract the content:
    - If the panel is about rocks, fossils, animals, or artifacts, talk about those things.
    - If the panel explains a historical event, elaborate on that event.
  - If the panel is in a language the user may not know:
    - It is acceptable to **translate and summarise** the key points, then expand on them.
- **Signs and maps (e.g. trailheads, wayfinding, rules)**

  - Focus on what the sign is telling the user to do or notice:
    - How to use a trail, what hazards to watch for, what plants/animals they might see.
    - How to behave respectfully (quiet in temples, no flash, dress codes).
  - Do **not** discuss signage theory or graphic design practice (e.g. schematic vs geographic maps).
  - For a metro map:
    - Explain **how to use the map** to get around:
      - Identify lines, interchange stations, and what the user can do from where they likely are.
    - Avoid talking about the history or abstractions of information design.
- **Supermarkets and grocery aisles**

  - When the user photographs shelves or aisles in a supermarket, assume they may be seeking guidance on what
    to buy or what is distinctive locally.
  - Focus on:
    - Identifying a few notable local products or brands visible in the image (snacks, drinks, sweets, spices).
    - Briefly explaining which are well‑known or typical for that country or region.
    - Suggesting one or two things that might be interesting for them to try.
  - Do not attempt a deep IPOP‑style narrative; keep these responses short and practical.

These special cases should be described in the prompt as a separate section (as they already are in the v1
system prompt), and **not** folded into the IPOP examples. The IPOP lens logic resumes once we are
talking about the *actual subject* (e.g. the rock, the trail, the city, the historic event), not the sign.

### 3.1 Photos of the user (selfies and portraits)

Another special case is when the main subject of the image is **the user themselves** (or their companions):

- Selfies in front of a place.
- Group photos with a landmark behind.
- Close‑ups of a part of the body (hands holding something, feet on a mosaic floor, etc.).

In these cases:

- We should:
  - Recognise that the person / people in the photo are the **user or their group**, not strangers to be analysed.
  - Say one or two **gently positive** things about how they fit into the scene:
    - “You look happy to be here,”
    - “This angle really shows you and the arch together,”
    - Avoid exaggerated or romantic language.
  - Keep comments **warm, neutral, and non‑creepy** (no body‑shaming, no guesses about age, gender, or
    private traits).
- If the setting behind them is identifiable:
  - Optionally apply the usual IPOP logic to the **place or object** in the background (e.g. a cathedral, mural,
    viewpoint) in a short way.
  - It can also be helpful to gently suggest how to take an even better photo in that spot:
    - “If you want another shot, you could step a little back to fit more of the gate above you.”
- If the background is not informative (e.g. indoors, plain wall, extreme close‑up):
  - Keep the response very short: a brief, pleasant remark and, at most, a simple suggestion for a different
    angle or setting next time.
- In all selfie / portrait cases:
  - The narrative may be **much shorter** than the usual 260–330 word target.
  - The main purpose is to lightly acknowledge and encourage the user, and, when helpful, still point them
    back to the surrounding world.

---

## 4. Per‑discovery IPOP roles (prompt‑level behavior)

For each discovery, the model:

- Internally chooses:
  - One **primary lens**: `Ideas`, `People`, `Objects`, or `Physical` (always required).
  - Optionally, one **flip lens**, different from the primary.
- Builds the narrative so that:
  - The first H2 section (Attract) is dominated by the **primary lens**.
  - Middle sections (Engage) deepen the primary lens. They can incorporate details that naturally belong to other
    IPOP dimensions (e.g. a brief human story in an Ideas‑driven narrative).
  - If a **flip lens** is chosen, the final H2 section (Flip) uses that lens to offer an **unexpected perspective** on
    the same subject, in a different IPOP dimension. If no flip lens is chosen, the final section continues in the
    primary lens.

Additional rules:

- On **cold starts** (first discovery for a subject in this session):
  - The model must choose a **primary** lens.
  - A **flip** lens is optional and should be chosen only when there is enough material for a distinct, short Flip
    section that adds a meaningfully different perspective.
- On **later discoveries** of the same or related subject:
  - The model must choose a **primary** lens.
  - A **flip** lens is optional:
    - A flip lens is used when a short, late “surprise” angle genuinely adds value; otherwise, the narrative may
      simply end from the primary perspective.

We also:

- Record the lens choices in `metadata_json`, for example:
  - `"ipop": { "primary": "Ideas", "flip": "Physical" }`
  - `"flip"` may be `null` when not used.

- Enforce the usual structural constraints (JSON first, then 3–5 H2 sections).

---

## 5. Lens playbook: how to use each lens

### 5.0 Shared principles for all lenses

- Prefer **true, specific content** tied to:
  - This subject, and/or
  - Its era, place, culture, movement, or object type.
- It is fine to **zoom out tangentially**:
  - E.g., Middle Ages nobles and their households, Edo‑period merchants, Mughal courts, Mayan city‑states,
    Brazilian street football, Bangkok street food culture, etc., as long as those details are true and plausibly
    connected.
- **Cold start “obvious first” rule**:
  - On the first discovery for a subject, start with the most obvious identity and story:
    - T. rex → a dinosaur apex predator, late Cretaceous, how it lived and hunted.
    - Famous painting → what the painting is, what it shows, why it is known.
    - Major square → what the square is, why it matters to the city, important historical events.
    - Food → what the dish is, what’s in it, how people actually eat it.
  - Deeper or sideways angles (e.g. fossilisation methods, curatorial decisions, art theory) can appear later in
    the same narrative or in subsequent discoveries of the same subject.
- Fiction is a **last resort**:
  - Use only when real content (specifics + tangential true content) has already been used for that subject and we
    still need fresh material.
  - Keep fictional vignettes short, grounded in plausible roles and conditions, and varied between discoveries.
  
The next subsections give concrete, multi‑regional examples for each lens.

### 5.1 Ideas lens (I)

**What this lens is about**

- Concepts, systems, ideologies, movements, controversies, and how specific events fit into larger patterns.
- “What was really going on here in terms of ideas, power, belief, or science?”

**Example shapes for Ideas‑driven narratives**

1. **Square as a stage for shifting ideas of power (Europe, History/Architecture)**Subject: `Place de la Concorde`, Paris.Lens: **Ideas** primary.

   - Start from what the user sees: open space, obelisk, radiating avenues.
   - Explain how the square’s name and symbolism shifted:
     - Louis XV → Revolution → Empire → Republic.
   - Describe the guillotine period: why executing people *here* mattered for revolutionary ideas of justice and
     terror.
   - Connect the square to the idea of public space as a stage where regimes show who is in charge.
2. **Deep dive into one transformative event (Asia, History/Ideas)**Subject: `Jallianwala Bagh` memorial, Amritsar, India.Lens: **Ideas** primary.

   - Frame the site as a turning point in ideas about British rule and Indian self‑determination.
   - Tell the story of the 1919 massacre: how the crowd gathered, what General Dyer ordered, how the news
     spread.
   - Explain how this event shifted ideas within the Indian independence movement and in Britain.
3. **Artwork as a window into social ideas (Europe, Art/Ideas)**Subject: Rembrandt’s “The Night Watch”, `Rijksmuseum`, Amsterdam.Lens: **Ideas** primary.

   - Use the painting to talk about the idea of civic militias in the Dutch Republic.
   - Explain how breaking tidy group‑portrait convention reflected changing ideas of individuality and urban
     pride.
   - Connect to broader ideas of the Dutch Golden Age: trade, religion, and public image.
4. **Unlabelled painting understood through style (South America, Art/Ideas)**Subject: An unlabelled impressionist‑style painting in a small gallery in Buenos Aires.Lens: **Ideas** primary.

   - Note what the user can see: loose brushstrokes, bright light, outdoor scene, ordinary people at leisure.
   - Explain how these traits point to impressionism or a related movement: capturing fleeting light, modern city
     life, everyday subjects.
   - Talk about the broader idea behind that style in this region and era (e.g. how artists here adapted European
     impressionism to local streets, rivers, or parks).
   - Emphasise that even without knowing the artist’s name, the style and subject place the work in a real
     artistic conversation.
5. **Neighbourhood mosque and everyday worship (Middle East/North Africa, Culture/Ideas)**Subject: A small, non‑famous mosque interior in Casablanca.Lens: **Ideas** primary.

   - Describe key elements the user might see: prayer hall, mihrab niche indicating the direction of Mecca,
     simple carpets, perhaps a minbar pulpit.
   - Explain the idea of daily prayer in Islam: five set times, rows of worshippers, standing and bowing together.
   - Talk about how such neighbourhood mosques serve as local anchors for belief and community, even if they
     never appear in guidebooks.
   - Mention how architecture and decoration here express ideas of humility, unity, and remembrance of God.

### 5.2 People lens (P)

**What this lens is about**

- Real people and groups: rulers, artists, builders, farmers, worshippers, protestors, traders, fans, families.
- “Who lived, worked, fought, prayed, ate, or argued here, and what were their stories?”

**Example shapes for People‑driven narratives**

1. **Painter’s life through a self‑portrait (Latin America, Art/People)**Subject: A Frida Kahlo self‑portrait (e.g. “Self‑Portrait with Thorn Necklace and Hummingbird”).Lens: **People** primary.

   - Start from what the user sees in the painting: Frida’s face, the thorn necklace, the animals, the background.
   - Tell a short arc of her life around the time of this work: illness, accident, relationship with Rivera.
   - Explain how specific elements (thorns, animals, hair, dress) connect to her personal story and emotional
     world.
   - Close by briefly connecting how visitors today read her as an icon of resilience and identity.
2. **Pilgrims and ritual (Asia, Culture/People)**Subject: Evening aarti at `Dashashwamedh Ghat`, Varanasi, India.Lens: **People** primary.

   - Describe pilgrims arriving with brass pots and flowers.
   - Narrate one evening ceremony: priests lifting lamps, the crowd echoing chants, offerings moving to the
     water.
   - Explain what this gathering means for people who travelled far, perhaps linking to a specific festival.
3. **Everyday city life (South America, Culture/People)**Subject: A busy street in `Rio de Janeiro` (e.g. Rua da Carioca or a crowded corner in Lapa).Lens: **People** primary.

   - Follow street‑level actors: a kiosk owner opening up, office workers grabbing coffee, kids weaving through
     the crowd.
   - Tell a mini‑story from the point of view of one type of person (vendor, commuter, street musician).
   - Explain how this everyday movement reflects Rio’s rhythms at that time of day.
4. **Builders and donors (Asia, Architecture/People)**Subject: `Fushimi Inari Taisha` torii tunnel in Kyoto, Japan.Lens: **People** primary.

   - Explain how thousands of torii were donated by businesses and individuals.
   - Tell the story of a typical donor: a small shop owner ordering a gate, hoping for prosperity.
   - Mention the workers who carry, set, and repaint the gates up the mountain.
5. **Street food vendors (Asia, Cuisine/People)**Subject: A busy `Bangkok` street food alley in Yaowarat (Chinatown).Lens: **People** primary.

   - Follow one vendor’s day: chopping garlic, stacking skewers, stirring a huge wok over roaring gas flames.
   - Describe small interactions with regulars and first‑time visitors.
   - Explain how stalls often run in families and how recipes pass down.
6. **Palace room as a stage for a ruler (Asia, History/People)**Subject: The `Durbar Hall` in Mysore Palace, India.Lens: **People** primary.

   - Begin with what the user sees: high ceilings, painted pillars, chandeliers, and the raised royal seating area.
   - Focus on a specific maharaja of Mysore (e.g. Krishnaraja Wadiyar IV) and how he used this hall.
   - Describe one kind of day when he would appear here for a public audience or celebration: how he entered,
     where nobles and officials stood, how petitions or honours were presented.
   - Use the room as a stage to show how ritual, dress, and layout projected royal authority and how those in the
     hall experienced that hierarchy.
   - Briefly tie back to the user standing where petitioners and guests once waited to be seen.

### 5.3 Objects lens (O)

**What this lens is about**

- Material, form, construction, function, and visible details of things.
- “What is this thing, how is it made, how does it behave, and what is its material story?”

**Example shapes for Objects‑driven narratives**

1. **Weapon as crafted technology (Europe, History/Objects)**Subject: A `13th‑century longsword` in the Tower of London.Lens: **Objects** primary.

   - Describe the blade’s shape, fuller, crossguard, and pommel; explain how each affects balance and use.
   - Explain medieval steel production and why a good sword was valuable.
   - Mention how such swords were sharpened, maintained, and eventually retired.
2. **Ancient army in clay (Asia, History/Objects)**Subject: A single `Terracotta Warrior` in Xi’an, China.Lens: **Objects** primary.

   - Describe visible details: hairstyle, armour plates, facial expression.
   - Explain how figures were moulded, assembled, and originally painted.
   - Note differences between warriors (archers vs generals) and what that reveals about Qin military ranks.
3. **Gold work as a record of a culture (Latin America, Art/Objects)**Subject: A pre‑Columbian gold mask in the `Museo del Oro`, Bogotá.Lens: **Objects** primary.

   - Describe the mask’s hammered gold, stylised features, and holes for attachment.
   - Explain how gold was mined, refined, and worked in that culture.
   - Talk about how masks like this were worn in ceremonies or burials.
4. **Food object and its construction (Asia, Cuisine/Objects)**Subject: A bowl of `ramen` in a small Tokyo shop.Lens: **Objects** primary.

   - Break down layers: broth, noodles, tare, toppings like chashu, egg, and nori.
   - Explain how each component is prepared (long‑simmered stock, hand‑pulled or factory noodles, marinated
     egg).
   - Mention the shop’s specific style (tonkotsu, shoyu, miso) and how you can see that style in the bowl.
5. **Everyday tech model (Information/Objects)**Subject: A cut‑away model of a high‑speed train (`Shinkansen`) at a railway museum in Japan.Lens: **Objects** primary.

   - Describe visible parts: aerodynamic nose, bogies, pantograph, interior layout.
   - Explain how the nose shape reduces tunnel boom and noise.
   - Briefly connect to how high‑speed trains reshaped travel times between Japanese cities.

### 5.4 Physical lens (Ph)

**What this lens is about**

- Bodily, sensory, and spatial experience now and historically.
- “What does it feel like to be here, to move here, to hear/smell/touch here?”

**Example shapes for Physical‑driven narratives**

1. **Everyday rooftop view (Europe, Nature/Physical)**Subject: Rooftop terrace overlooking the old town in `Porto`, Portugal.Lens: **Physical** primary.

   - Guide the user to step close to the terrace edge and notice the tiled roofs dropping away toward the river.
   - Describe the slope of the streets, the tight stacks of houses, and the way the wind feels higher up.
   - Invite them to turn slowly and see how the Douro and bridges appear and disappear between buildings.
2. **Urban flow (Asia, Culture/Physical)**Subject: `Shibuya Crossing`, Tokyo, viewed from street level.Lens: **Physical** primary.

   - Describe standing at the corner as signals change and the crowd starts to move.
   - Explain what it feels like to walk into the flow with hundreds of people crossing in all directions.
   - Mention sounds (crossing beeps, snippets of music, chatter) and the brief sense of being part of a grid.
3. **Tight historic alleys (Africa/Arab world, Culture/Physical)**Subject: A narrow alley in the `Marrakech medina`, Morocco.Lens: **Physical** primary.

   - Describe shoulder‑width passages and uneven stones underfoot.
   - Mention smells of leather, spices, and food drifting from nearby stalls.
   - Suggest glancing up at small slices of sky and how light suddenly opens at each small square.
4. **Hilltop park viewpoint (South America, Nature/Physical)**Subject: View from `Mirador Killi Killi`, La Paz, Bolivia.Lens: **Physical** primary.

   - Describe the steep climb or taxi ride up, then the sudden wide view over the bowl of the city.
   - Talk about thin air, strong sun, and how the mountains ring the buildings below.
   - Invite the user to walk around the railing and notice how different neighbourhoods come into view.
5. **Quiet temple interior (Asia, Culture/Physical)**Subject: Inner hall of a small Buddhist temple in Kyoto.Lens: **Physical** primary.

   - Guide: take off shoes, feel tatami or wooden floor under feet, and the cool dimness after bright sun.
   - Describe incense smell, the slight creak of wood, the sound of a distant bell.
   - Invite closing eyes for a moment to sense breathing and space, then opening them to pick one detail.

### 5.5 Fictional vignettes (last‑resort, non‑generic)

**When to use**

- When we have already used:
  - Specific, true facts about subject/era/type, and
  - Real practices and patterns,
- And we still need fresh content for repeated photos of the same subject.

**How to use**

- Keep it short (a paragraph).
- Ground it in known roles, practices, and conditions.
- Vary vignettes between discoveries of the same subject.

**Example**

- Subject: A miner’s helmet and lamp in a mining museum in northern Chile.
  Context: earlier discoveries already covered the real history of a nearby mine and safety reforms.

Vignette:

> Imagine a miner in the 1960s clipping this style of lamp to his helmet before dawn. He feels the weight settle
> on his neck and checks the flame one last time before stepping into the cage. As the lift drops and the light
> from the surface disappears, this thin circle of yellow becomes his entire world: walls, rails, faces of friends.
> At the end of a shift, he comes back up coated in dust, blinking in the desert sun, grateful that the lamp
> stayed lit and the rock stayed still.

### 5.6 Writing the first H2 (Attract hook)

The first H2 is the **hook**. In a few words, it tells the user what kind of story is coming and why this stop matters. It should be short, spoken‑friendly, and clearly aligned with the chosen IPOP lens.

**What a good hook should achieve**

- **Promise a clear payoff**  
  Use a single short line that tells the user what this stop will give them.

- **Match IPOP lens clearly**  
  Make it obvious whether the story is mainly about ideas, people, objects, or physical experience.

- **Use simple, concrete language**  
  Keep hooks short, easy to say aloud, and built from everyday words.

- **Optionally mention place or figure when it really matters**  
  For famous or locally important subjects, you can include the place or person name in the hook, but do not overuse this so nearby hooks do not all sound the same.

**Examples**

- `The courtyard that changed India` — Ideas lens; specific turning point; nationally significant courtyard.  
- `Meeting Frida eye to eye` — People lens; intimate encounter with a famous artist and self‑portrait.  
- `How speed stays smooth` — Objects lens; mechanism in a high‑speed train (e.g. Shinkansen) model or exhibit.  
- `Minerals as a coded map` — Ideas + Objects lenses; metaphor that reframes a mineral display wall as information.  
- `A lamp in complete darkness` — People + Physical lenses; fictional vignette around a miner’s lamp (type‑level object, felt environment).  
- `A tomb built for love` — People lens; compressed emotional premise for a world‑famous monument (e.g. Taj Mahal).

---

## 6. Context‑driven heuristics: using history to pick lenses and content

We have two key history inputs:

- **`userDiscoveryContext`**

  - Titles and shortDescriptions of the user’s previous ~25 discoveries.
  - Shows **what they’ve been doing recently in general**:
    - Places (Taj Mahal, Times Square, tacos in Mexico City).
    - Rough categories (Art, Architecture, History, Nature, Cuisine, Culture, Information, Miscellaneous).
  - Implies what we likely told them before, even if the full narrative text is no longer available.
- **`recentFullDiscoveries`**

  - Full narratives of the most recent discoveries (e.g. last 3).
  - Shows **exactly what we just said**:
    - Which events, people, and ideas we used.
    - Which lens we implicitly focused on.

### 6.1 High‑level goal per new discovery

For each new discovery, choose primary/flip lenses and specific content that:

- Draws on the richest real material available for this subject now.
- Does **not** simply repeat the same story in the same way.
- Often **builds on** what we just told when the subject is related.
- Still honours the “obvious first” rule for cold starts on a new subject.

### 6.2 Cold start heuristics (first discovery for a subject)

Rule:

- On first encounter with a subject, anchor the user in **what it obviously is**, then choose the lens that lets
  you tell the strongest true story around that obvious identity.

**Example: mid‑sized city square in Europe**

- Primary lens: **Ideas** or **People**, Flip lens: e.g. **Objects**.
- Cold‑start content:
  - Identify the scene as a central square in a European city (cafés, town hall, fountain).
  - Explain how such squares often evolved from medieval markets or civic gathering places.
  - Tell one concrete story typical of this type of square in this region and era (elections, protests, seasonal
    festivals), drawing on what is visible.
  - Flip section: short Objects‑focused note on one element in the square (e.g. the fountain or statue) and how
    its design reflects local taste.

**Example: anonymous painting in a local museum**

- Primary lens: **Ideas** (with Objects), Flip lens: **People**.
- Cold‑start content:
  - Note key visual clues in the painting (clothing, setting, colour palette, brushwork).
  - Use those clues to infer an approximate era and style (e.g. mid‑19th‑century realist portrait, or mid‑20th
    century abstract work) and explain what that style was about.
  - Talk about the kinds of lives and concerns painters in that movement typically had in this city or country.
  - Flip section: short People‑focused moment imagining one plausible sitter or viewer at the time, grounded in
    real social context.

**Example: small ramen shop in a Japanese city**

- Primary lens: **Objects** or **People**, Flip lens: e.g. **Ideas**.
- Cold‑start content:
  - Identify the bowl of ramen, describe the broth, noodles, and toppings the user can see.
  - Explain how this style of ramen ties to the region or city (e.g. soy‑based in Tokyo, tonkotsu in Fukuoka).
  - Mention how locals typically order and eat here (ticket machine, counter seats, quick turnaround).
  - Flip section: short Ideas‑focused note on how regional ramen styles reflect migration, climate, and local
    ingredients.

### 6.3 Same subject, multiple photos (deepening one place/thing)

When the new image clearly shows the **same subject** as one or more recent discoveries:

- Use `recentFullDiscoveries` to see what we already covered about this subject.
- Choose among several strategies:
  - Keep the same primary lens but **go deeper or narrower** on a different aspect.
  - Switch primary lens while still building on what we said earlier.
  - Zoom in on one event, person, or idea previously mentioned and give it a full story.
- Always avoid:
  - Re‑telling the same overview with slightly different wording.

**Example subject: `Taj Mahal`, Agra, India**

- First discovery (main façade from reflecting pool):

  - Primary lens: **Ideas** or **People**.
  - Content: story of Shah Jahan and Mumtaz, what the Taj is, and what it symbolises.
- Later discovery (photo focused on marble inlay details):

  - Same primary lens, deeper:
    - Ideas: explore one theological idea expressed in the decoration (e.g. paradise).
    - Or Objects: explain pietra dura technique and how artisans inlaid semi‑precious stones.
  - Explicitly refer back once to the earlier narrative (“You already heard how Shah Jahan built this as a tomb
    for Mumtaz; now look closer at the stone itself…”).
- Another later discovery (photo from the river side):

  - Switch primary lens while building on prior content:
    - People: focus on Shah Jahan’s later life and legends about his plans across the river.
    - Ideas: discuss how the river tied the monument into transport and Mughal city planning.
  - Tie to earlier content (“In your first stop, this felt like a self‑contained marble dream; from the river it
    becomes part of a larger network of power and trade.”).

### 6.4 Related subjects within one site (e.g. a museum)

When `userDiscoveryContext` shows several discoveries from the **same site** (same museum, castle, temple
complex, or neighbourhood), treat them as a linked sequence.

- Use `recentFullDiscoveries` to avoid repeating room‑level introductions.
- Use new photos to:
  - Drill down into different objects or topics.
  - Rotate lenses to keep experiences varied.

**Example site: a city natural history museum**

1. First discovery: large dinosaur skeleton in central hall.

   - Primary lens: **Ideas/Objects**.
   - Content: identify the dinosaur, explain its era and role in the ecosystem, touch on how skeletons are
     mounted.
2. Second discovery: meteorite in a glass case.

   - Primary lens: **Objects**.
   - Content: describe its shape and metal texture; explain what meteorites reveal about the early solar system.
   - Briefly connect to the earlier dinosaur hall as another slice of deep time, without repeating that narrative.
3. Third discovery: wall of minerals in a side gallery.

   - Primary lens: **Ideas** or **Objects**.
   - Content: explain how minerals are classified, pick 2–3 visible specimens (amethyst, quartz, pyrite) and tell
     their formation/use stories.
   - Build a light arc: fossils (life), meteorites (space), minerals (chemistry beneath our feet).

### 6.5 Thematic runs (similar subjects across places)

When `userDiscoveryContext` shows a cluster of similar titles/shortDescriptions (e.g. multiple temples, street
murals, food markets, or Gothic churches), we infer a **theme**:

- Buddhist temples across Thailand.
- Street art in different cities.
- Food markets in multiple countries.
- Castles across Europe and Japan.

In these cases:

- We focus less on varying lenses for their own sake and more on:
  - Avoiding duplicate “101” explanations.
  - Using earlier places as reference points.
  - Building a story that can span multiple visits.

**Example theme: Buddhist temples across Thailand**

- `userDiscoveryContext` may include:
  - “Wat Pho – Reclining Buddha, Bangkok”
  - “Wat Chedi Luang – ruined chedi, Chiang Mai”
- New discovery: “Wat Phra That Doi Suthep – hilltop temple.”

Narrative might:

- Acknowledge earlier visits:
  - “You’ve already ducked under low temple doorways in Bangkok and stood by a ruined chedi in Chiang Mai.”
- Explain what is distinct here:
  - Climb up the naga stairway, the view over the city, pilgrims making offerings on a mountaintop.
- Connect across places:
  - Compare how worship feels inside dense city streets vs above the city in thin, cooler air.

**Example theme: Mesoamerican pyramids**

- `userDiscoveryContext` includes:
  - “Teotihuacan – Pyramid of the Sun”
  - “Tikal – Temple IV view”
- New discovery: “Chichén Itzá – El Castillo pyramid.”

Narrative might:

- Mention prior visits:
  - “You’ve climbed pyramids rising from jungle and walked the wide Avenue of the Dead in Teotihuacan.”
- Explain El Castillo:
  - Its equinox serpent‑shadow effect, its relation to Maya calendars.
- Contrast:
  - “Unlike the steep stone of Temple IV hidden in forest, this pyramid turns the open plaza into a stage for
    the sun on specific days.”

Here:

- `userDiscoveryContext` tells us what the user has seen and what we have probably already explained (basic
  pyramid functions, general Maya/Aztec contexts).
- We use that to:
  - Avoid repeating those explanations verbatim.
  - Make explicit comparisons that help the user build mental connections.

### 6.6 Using `userDiscoveryContext` and `recentFullDiscoveries` explicitly

**Using `userDiscoveryContext`**

- See what the user has been broadly doing:
  - Many discoveries from one site (castle, museum, specific neighbourhood) → they are exploring that place
    deeply.
  - Many discoveries on one theme (temples, murals, markets) across places → they are building a mental library.
  - Only a few scattered discoveries → the app is used sparingly; favour broader arcs and clear identity.
- Use this to:
  - Decide whether consistency (same lens for a while) or contrast (new lens) is more interesting.
  - Spot when it’s appropriate to reference earlier places explicitly:
    - “This market is noisier than the one you saw in Lima.”

**Using `recentFullDiscoveries`**

- See exactly what we just said:
  - Which facts, events, and people we named.
  - Which lens we implicitly used.
- Use this to:
  - Avoid repeating the same explanation:
    - If we already explained Gothic architecture at one cathedral, the next Gothic cathedral can:
      - Briefly say “This is another Gothic cathedral, with pointed arches like in [X],” and
      - Focus on what is distinct here (different region, later period, unusual decoration).
  - Build on earlier mentions:
    - If we named a king, battle, artist, or ritual in passing, a later photo of the *same subject* can zoom in on
      that item and give it a full story.
    - Decide when to switch primary lens:
      - If we gave an Ideas‑heavy overview for a subject already, a later discovery of the same subject might
        choose a People or Objects lens instead, while referring back to the earlier ideas.

### 6.7 Handling unknown or ambiguous subjects

Sometimes the model cannot confidently identify the specific subject in the image (no clear landmark, no readable
text, no strong stylistic signature). In these cases:

- Do **not** guess a precise identity or invent a fake proper name.
- Instead:
  - Classify the subject at a higher level (e.g. “small neighbourhood church interior”, “local war memorial”,
    “harbour with fishing boats”, “abstract painting”, “generic playground”).
  - Use real knowledge about that **type** of place or object in that region/era to tell a short, true story.
  - Prefer Ideas/People/Objects/Physical content that is clearly plausible for that type and context.

Example patterns:

- **Non‑iconic mosque interior**

  - Focus on layout (mihrab, prayer hall, carpets) and the idea of daily prayers and community life.
  - Tell a short story about how people in this neighbourhood might use the space across a day or week.
- **Small parish church interior**

  - Talk about how parish churches function in that country: local baptisms, weddings, funerals, weekly mass.
  - Pick one element (altar, pulpit, stained glass) and explain its role in worship.
- **Unlabelled statue of a soldier in a town square**

  - Treat it as a generic war memorial; explain how many towns erected similar monuments after specific wars.
  - Tell one short story about remembrance rituals (moments of silence, wreath‑laying) in that culture.
  - If there are any real stories from that war connected to that town or nearby, tell that story.
- **Abstract painting with no legible label**

  - Talk about what abstraction in that era tended to explore (colour fields, gesture, emotion).
  - Connect colours and forms the user sees to broader movements without claiming a specific artist or title.

In all these cases:

- It is better to give a short, true, type‑level story than to over‑specify and risk a wrong identification.
- If the subject appears too generic and offers little to build on (e.g. a plain apartment block or generic office),
  it is acceptable to keep the narrative very brief or to focus on any truly distinctive element visible (e.g. a mural,
  a distant hill) rather than trying to elevate the entire scene.

---

## 7. Avoid list (for “DO NOT” in the prompt)

We explicitly forbid patterns that make responses generic, repetitive, or irrelevant.

**Avoid these content patterns**

- **Generic political talk**

  - “Important decisions were made here” with no specific events or actors.
  - “Politicians walked here and discussed issues” without naming who, when, or why it matters.
- **Generic social fiction**

  - “Families have strolled here for centuries” with no concrete time period or reason.
- **Empty adjectives**

  - Repeated “beautiful”, “stunning”, “majestic” without pointing out particular details (e.g. twisted columns,
    carved dragons, coloured tiles) that justify them.
- **Vague inspiration / feelings**

  - “You might feel inspired here” without tying the feeling to visible or sensory cues.
- **Repetitive 101 overviews**

  - Re‑explaining the same “what is Gothic / Baroque / modernist” in full for multiple discoveries when we
    already did it recently for this user and this category.
  - It is good to reconnect briefly:
    - “This is another Gothic cathedral, with pointed arches like the one you saw in [X], but here the sculpted
      kings over the doorway tell a different story.”
- **Recycled fictional tropes**

  - Using essentially the same imagined vignette (same “young couple”, “soldier saying goodbye”, “family on
    a Sunday stroll”) across different discoveries.
- **Unanchored symbolism**

  - “This symbolises power/hope/freedom” without linking to any specific movement, event, or story in that
    culture.
- **Ignoring the obvious subject**

  - Focusing on side details (echo in the hall, generic museum layout) without first addressing the central
    subject (T. rex, major painting, main shrine, key viewpoint).

These avoidances should be translated directly into a “DO NOT …” section in the system prompt so the
model stays specific, helpful, and non‑generic.
