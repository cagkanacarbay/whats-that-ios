# "Zoom Out Tangentially" — Refined Criteria

Extracted from the depth analysis. This phrase (Line 95 of system prompt v0.8.0) is being refined, not removed. The concept is sound but the criteria are too weak.

## The phrase in question

```
It is fine to zoom out tangentially (e.g., Middle Ages nobles, Edo-period merchants,
Mughal courts, Mayan city-states, Brazilian street football, Bangkok street food culture)
as long as details are true and plausibly connected.
```

## What's wrong with it

1. **"Plausibly connected" is too weak** — everything at a location is plausibly connected to its era. This is no guard at all.
2. **The parenthetical list teaches generic zoom-outs** — "Middle Ages nobles" and "Edo-period merchants" are CATEGORIES, not stories. The model reads these and learns to zoom to categories rather than specific stories.
3. **No guidance on WHEN to zoom out** — the phrase permits zoom-out always, when it should be a tool for when the specific subject is narrow.

## What zoom-out done WELL looks like

**#184 (Latvian Heraldry Wall):**
> "In January 1991, thousands of people from these very towns flooded into Riga. They brought tractors and heavy trucks to block the narrow streets."

Zooms from the heraldic wall to a specific 1991 event. Specific, vivid, gives the listener something real. The zoom-out makes the response MORE specific, not less.

## What zoom-out done POORLY looks like

**#184 (same discovery, different section):**
> "The symbols on these shields follow the ancient rules of heraldry."

Shifts to generic heraldry principles that apply everywhere. The zoom-out makes the response LESS specific.

**#192 (Tomb of Amyntas):**
> "Adopting these foreign shapes served as a diplomatic statement of wealth."

We know enough about the Tomb of Amyntas to talk about it specifically. The zoom-out to generic "Mediterranean elite" signaling is unnecessary and weaker than specific content about this tomb.

**#202 (The Golden Siege):**
Abandons the battle narrative to discuss generic gilding technique. Craft description not tied to the specific subject.

## Proposed rewrite

> It is fine to zoom out tangentially when the specific subject is narrow and zooming out would provide a richer, more specific response. When zooming out, land on a SPECIFIC story or fact — not a generic description of an era or practice. Zoom-out should make the response MORE specific, not less.

Key changes:
- Removed the parenthetical list of generic categories
- Changed criteria from "plausibly connected" to "when specific content is narrow"
- Added guidance: zoom-out should land on something SPECIFIC
- Added test: does the zoom-out make the response more or less specific?

## Also moved here: A5 — "Its era, place, culture, movement, or object type" (Line 94)

```
Prefer true, specific content tied to this subject and/or its era, place, culture,
movement, or object type.
```

**Status:** Considered but not being evaluated at this stage. Related to zoom-out but not the primary driver of the problem. Evaluate after the core depth fixes are in place.

## Evidence still needed

- More discoveries where zoom-out was done well (lands on specific stories)
- More discoveries where zoom-out was done poorly (lands on generic categories)
- Whether the refined criteria are sufficient or need further tightening
