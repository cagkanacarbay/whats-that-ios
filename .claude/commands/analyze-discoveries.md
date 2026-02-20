# Analyze Discoveries

Analyze discovery narratives from the local SQLite database to find good and bad examples for system prompt improvement. The primary output is **direct quotes** from each discovery, not just evaluations.

## Arguments

The user provides arguments after `/analyze-discoveries`. Supported formats:
- `/analyze-discoveries 192-220` — analyze a range of IDs
- `/analyze-discoveries 192,195,199,219` — analyze specific IDs
- `/analyze-discoveries next` — find the next unanalyzed batch of 20 from the latest 100 dev discoveries
- `/analyze-discoveries all-remaining` — analyze all unanalyzed batches in parallel

## Setup

**Database:** `/Users/cagkanacarbay/Projects/whats-that/discoveries.db` (SQLite)

**Table:** `discoveries` — columns: `id`, `title`, `short_description`, `description`, `source`, `word_count`, `section_count`, `country`, `locality`

**Analysis output folder:** `docs/development/features/09-discovery-knowledge-corpus/analysis/`

**The latest 100 dev discoveries** are the working set. Get them with:
```sql
SELECT id FROM discoveries WHERE source='dev' ORDER BY id DESC LIMIT 100;
```

## Instructions

### Step 1: Determine which IDs to analyze

Parse the user's argument to get a list of discovery IDs.

If `next` or `all-remaining`: Check which batches already have analysis files in the analysis folder (files are named `batch-N-ids-XXX-YYY.md`). Find IDs from the latest 100 dev discoveries that haven't been analyzed yet.

### Step 2: Split into batches and launch parallel agents

Split the IDs into batches of 20. For each batch, launch a **sonnet** agent using the Task tool with `subagent_type: "general-purpose"`, `model: "sonnet"`, and `run_in_background: true`.

Each agent gets this prompt (fill in the IDs, batch number, and file path):

---

**Agent prompt template:**

```
You are analyzing discovery narratives from the What's That? app. Your PRIMARY job is to extract and include DIRECT QUOTES from each discovery. Evaluations without quotes are useless.

Database: /Users/cagkanacarbay/Projects/whats-that/discoveries.db (SQLite)

For each of these IDs: [LIST_IDS_HERE]

Use the Bash tool to query each discovery:
sqlite3 /Users/cagkanacarbay/Projects/whats-that/discoveries.db "SELECT id, title, description FROM discoveries WHERE id = X;"

For EVERY discovery, read the full description text carefully. Then evaluate:

**DEPTH vs BREADTH:**
- Does each H2 section introduce a NEW unrelated topic (bad = "topic-per-section" pattern)?
- Or does the narrative develop topics with real substance (good)?
- Mode A = single-story deep dive (one thread across all sections)
- Mode B = multi-aspect (multiple aspects, each with 2-3+ sentences of real development)

**NAME-DROPPING:**
- People/events/battles/institutions mentioned in 1-2 sentences then abandoned? (bad)
- Developed with specific detail? (good)

**UNSUPPORTED SUPERLATIVES:**
- "Famous for," "legendary," "one of the greatest" without supporting evidence? (bad)

**LENS TYPE:** Primary IPOP lens (Ideas / People / Objects / Physical)

**OVERALL QUALITY (1-5):**
- 5 = Excellent depth, every mention developed, could be a prompt example
- 4 = Good, mostly developed, minor issues
- 3 = Mixed, some good sections but some name-drops or shallow topics
- 2 = Shallow, multiple undeveloped mentions, topic-per-section pattern
- 1 = Severe, museum placard energy, nothing developed

CRITICAL: A discovery that covers 4+ separate topics in 4 sections with 3-4 sentences each is BAD (topic-per-section) even if writing is decent. Good means whatever is mentioned gets DEVELOPED with real knowledge. Be rigorous.

==============================
OUTPUT FORMAT — QUOTES ARE MANDATORY
==============================

# Batch N Results (IDs XXX-YYY)

## Top Candidates (Quality 4-5)

For each top candidate, use this EXACT format:

### #[ID] — [Title] | Quality [N] | [IPOP Lens] | Mode [A/B]
[1-2 sentence verdict — what makes it good]

**Key passages:**

> [Blockquote a passage that shows depth/development — 2-4 sentences from the discovery]

> [Blockquote another strong passage — show the best writing]

> [Blockquote a third passage if the discovery is quality 5]

For Quality 5 discoveries, include 4-5 blockquoted passages covering the best material from each H2 section. These passages will be used directly in the system prompt as examples.

---

## Bad Examples (Quality 1-2)

For each bad example, use this EXACT format:

### #[ID] — [Title] | Quality [N]
[1-2 sentence verdict — what anti-pattern it demonstrates]

**Problematic passages:**

> [Blockquote the problematic text from the discovery]
[Shows: name-drop — person mentioned in one sentence, never developed]

> [Blockquote another problematic passage]
[Shows: unsupported superlative — "famous for" with no evidence]

> [Blockquote another problematic passage]
[Shows: topic-per-section — new unrelated topic introduced]

Include 2-4 problematic passages per bad example. Each quote MUST have a bracketed annotation naming the specific anti-pattern.

---

## Middle Ground (Quality 3)

For each, use this format:

### #[ID] — [Title] | Quality 3
[1 sentence on what works, 1 sentence on what doesn't]

**What works:**
> [Blockquote a passage that shows good development]

**What doesn't:**
> [Blockquote a passage that shows a problem]
[Shows: specific anti-pattern]

---

## Summary Table

| ID | Title | Quality | IPOP | Mode | Prompt Example? |
|----|-------|---------|------|------|----------------|

Use YES for quality 4-5, BAD EXAMPLE for quality 1-2, and Maybe/No for quality 3.

==============================
CRITICAL RULES
==============================

1. EVERY discovery entry MUST include blockquoted passages from the actual discovery text. An entry without quotes is INCOMPLETE.
2. Quotes must be EXACT text from the description column — do not paraphrase or summarize.
3. For Quality 5 discoveries, be thorough — these passages will be used as examples in the system prompt.
4. For Quality 1-2 discoveries, every quote needs a [Shows: anti-pattern] annotation.
5. The sqlite3 output may use | as a separator. The description column contains full markdown with ## headers.

IMPORTANT: After completing your analysis, use the Write tool (NOT Bash) to save the full output to this file:
[OUTPUT_FILE_PATH]
```

---

### Step 3: Collect results and write analysis files

When agents complete, verify each batch's file was written to the analysis folder as `batch-N-ids-XXX-YYY.md`. If any agent failed to write its file, write it yourself from the agent's returned results.

### Step 4: Report summary

After all batches are done, print a summary:
- Total discoveries analyzed
- Count by quality tier (5/4/3/2/1)
- Top candidates list with ID, title, lens, mode
- Bad examples list with ID, title, main problem
- Which lens types are covered (do we have enough for each?)
- Which modes are covered (enough Mode A and Mode B?)
- Any gaps that need filling (e.g., "no good Physical lens example found yet")
