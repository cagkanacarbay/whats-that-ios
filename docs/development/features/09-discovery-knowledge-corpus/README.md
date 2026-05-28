# Discovery Knowledge Corpus

Build a growing corpus of key facts from past discoveries to improve context awareness and prevent repetition across a user's discovery history.

## Problem Statement

### Current Approach

When generating a new discovery, we provide context about the user's recent discoveries to:
1. Avoid repeating the same facts
2. Enable meaningful connections between discoveries
3. Understand what the user has already learned

Currently, we pass:
- **3 full discovery narratives** (~2000 characters each, ~1500 tokens total)
- **Title-only history** for up to 22 more discoveries (e.g., "yesterday in Paris: 'Eiffel Tower', 'Notre Dame'")

### The Problem

1. **Full narratives are token-expensive** - We can only afford to include 3 recent discoveries
2. **Titles tell us nothing useful** - Knowing someone discovered "The Lord of Four Faces" doesn't tell us they learned about elephant offerings or Hindu-Buddhist syncretism
3. **We lose knowledge quickly** - By discovery #4, we have no idea what facts were covered in discovery #1
4. **Repetition risk increases** - The more discoveries a user makes, the more likely we repeat facts they've already heard

### Concrete Example

A user in Thailand makes 5 discoveries:
1. Wat Khao Rang's Peak (Buddhist temple architecture)
2. The Lord of Four Faces (Brahma statue, elephant offerings)
3. Phuket's Lantern Gate (Hokkien Chinese heritage)
4. Kata's Traditional Peaks (modern Thai-style architecture)
5. **New discovery: Another temple**

With current system, discovery #5 only has full context for #3 and #4. We might repeat facts about Buddhist roof symbolism from #1 or explain elephant offerings again from #2.

## Proposed Solution

### Key Facts Extraction

When generating each discovery, also extract 5-6 **key facts** - condensed bullet points capturing the specific information covered:

**Example for "The Lord of Four Faces":**
```
- Four-faced statue = Phra Phrom (Thai Brahma)
- Each face = kindness, mercy, sympathy, impartiality
- Elephant statues left as thank-you offerings
- Shows Hindu-Buddhist overlap in Thai practice
- Holds scepter (power), book (knowledge), prayer beads (time)
```

~60 words vs ~2000 characters of full narrative.

### Token Math

| Approach | Token Cost | Discoveries Covered | Useful Detail |
|----------|------------|---------------------|---------------|
| Current (3 full narratives) | ~1500 | 3 | Everything but verbose |
| Proposed (15-20 key facts) | ~1350 | 15-20 | Specific facts only |

**Similar token budget, 5x more coverage, more actionable information.**

### What Key Facts Enable

1. **Better repetition avoidance** - Know exactly what facts were mentioned, not just what titles exist
2. **Smarter connections** - Can identify when discoveries share specific people, events, or concepts
3. **Cumulative learning** - Build on what the user knows rather than starting fresh each time
4. **Longer memory** - Cover 15-20 discoveries instead of 3

## Implementation Areas

### 1. Prompt Changes (Generation Side)

Add to the AI output requirements: generate a `keyFacts` array alongside the existing metadata and narrative.

**Output format addition:**
```json
{
  "keyFacts": [
    "fact 1",
    "fact 2",
    ...
  ]
}
```

**Prompt guidance needed:**
- What makes a good key fact (specific, unique, not generic)
- How many facts to extract (5-6 suggested)
- Format constraints (token-efficient, no filler)

### 2. Database Changes

**Option A: Repurpose `analysis` field**
- Field already exists, currently stores full AI output but is never read
- Already documented for deletion in post-production-work-list.md
- Would need to change what we store (key facts JSON instead of full output)

**Option B: Add new `key_facts` column**
- Cleaner separation
- Would still need to stop writing to `analysis` (or delete it)

**Recommendation:** Option A - repurpose `analysis` since it's already unused and we'd delete it anyway.

### 3. Edge Function Changes (`ask-ai-v7`)

- Parse `keyFacts` from AI response
- Store in database (either `analysis` field repurposed or new field)
- Current code at `index.ts:1236` already writes to `analysis`

### 4. iOS Client Changes

**Data model:**
- Add `keyFacts: [String]?` to discovery models
- Update `DiscoverySummary` to include key facts

**Context building (`DiscoveryContextBuilder.swift`):**
- Replace full narrative section with key facts section
- Increase discovery limit from 3 to 15-20
- New format for context payload

**Current:**
```
1. "The Lord of Four Faces" - Thailand, today
"""
[Full 2000 character narrative]
"""
```

**Proposed:**
```
1. "The Lord of Four Faces" - Thailand, today
- Four-faced statue = Phra Phrom (Thai Brahma)
- Each face = kindness, mercy, sympathy, impartiality
- Elephant statues left as thank-you offerings
...
```

### 5. User Prompt Changes

Update the user prompt template to reflect new context format:
- Change `recentFullDiscoveries` to something like `recentDiscoveryFacts`
- Update instructions for how AI should use this condensed context

## Current State of `analysis` Field

| Aspect | Status |
|--------|--------|
| Column exists | Yes, in `discoveries` table |
| Written to | Yes, by edge function (full AI response) |
| Read from | Never (no iOS usage, RPC function unused) |
| iOS model | Does not include this field |
| Documented status | Marked for deletion in post-production-work-list.md |
| Current data | ~657 rows with full AI output (~2-3KB each) |

**Cleanup needed:** The `get_discovery_analysis` RPC function can be deleted regardless of approach.

## Migration Considerations

### Existing Discoveries

Existing discoveries won't have key facts. Options:
1. **Backfill** - Run extraction on existing discoveries (expensive, one-time)
2. **Graceful degradation** - Fall back to title-only for old discoveries without key facts
3. **Ignore** - Only new discoveries get key facts; old ones age out of context window anyway

**Recommendation:** Option 2 (graceful degradation) - simplest, and old discoveries naturally leave the context window over time.

### Rollout

1. Deploy prompt changes + edge function changes
2. New discoveries start generating key facts
3. Deploy iOS changes to consume key facts
4. (Optional) Backfill existing discoveries

## Open Questions

1. **Optimal number of key facts** - Is 5-6 right? Could vary by discovery complexity.
2. **Key fact quality** - How do we ensure facts are specific enough to be useful?
3. **Deduplication** - If multiple discoveries mention "Hokkien Chinese heritage", how do we handle?
4. **Connection detection** - Should we explicitly tag facts for easier matching? (e.g., `person:Shah Jahan`, `event:1683 Battle of Vienna`)

## Status

- [x] Problem analysis complete
- [x] Solution designed
- [ ] Prompt changes designed
- [ ] Database migration written
- [ ] Edge function updated
- [ ] iOS client updated
- [ ] Testing complete
