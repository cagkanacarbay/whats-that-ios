# Analysis Column in Discoveries Table

This document tracks all uses of the `analysis` column in the `discoveries` table.

## Overview

**Purpose:** Internal AI analysis storage for debugging and potential future features.
**Type:** `TEXT`
**Status:** Written to, but never read by the application.

---

## Column Definition

**Migration:** `supabase/migrations/20250112_add_analysis_to_discoveries.sql`

```sql
ALTER TABLE public.discoveries ADD COLUMN analysis TEXT;

COMMENT ON COLUMN public.discoveries.analysis IS
  'Internal AI analysis data for debugging and potential future features.
   Not returned to clients by default.';
```

---

## Where It's Written

### ask-ai-v7/index.ts

**Line 1236:** The full raw AI response is stored in the analysis column when creating a discovery.

```typescript
// Line 1111
let analysisSection = '';

// Line 1163: Full raw AI response assigned
analysisSection = outputBody;

// Line 1236: Stored in discovery insert
const discoveryData = {
  // ...
  analysis: analysisSection,
  // ...
};
```

`outputBody` contains the complete AI response including:
- `metadata_json` section (title, short_description, confidence levels)
- Full narrative text

---

## Where It's NOT Read

### get_discoveries_with_location()

This function explicitly **excludes** the analysis column. The migration comment states:

> "Update the get_discoveries_with_location function to EXCLUDE the analysis column. This ensures the analysis is not returned to the client app."

### Swift App

The Swift code does not read this column. References to "analysis" in Swift (e.g., `DiscoveryAnalysisState`, `DiscoveryAnalysisParser`) refer to the **streaming process**, not the database column.

---

## Unused Read Function

### get_discovery_analysis()

A function exists to read the column:

```sql
CREATE OR REPLACE FUNCTION get_discovery_analysis(p_discovery_id bigint)
RETURNS TEXT
```

**However, this function is never called anywhere in the codebase.**

It's listed for removal in `docs/development/post-production-work-list.md`:
> `[ ] Remove the get_discovery_analysis function`

---

## Summary

| Operation | Location | Status |
|-----------|----------|--------|
| Write | `ask-ai-v7/index.ts:1236` | Active |
| Read (client API) | `get_discoveries_with_location()` | Explicitly excluded |
| Read (admin) | `get_discovery_analysis()` | Exists but unused |
| Read (Swift) | N/A | Never reads column |

**The analysis column is write-only in practice.** Data is stored for potential future debugging but is never retrieved or processed by the application.
