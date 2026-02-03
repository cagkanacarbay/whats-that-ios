# Legal Document Update

Generate a database migration for Terms of Service and/or Privacy Policy updates.

## Instructions

Work with the user to create a legal document update. When new versions are added, users who haven't accepted them will see an acceptance modal on their next app launch.

### Step 1: Gather Information

Ask the user:
1. **Which document(s)?**
   - Terms of Service only
   - Privacy Policy only
   - Both documents
2. **What version number(s)?** (e.g., 1.1.0 for ToS, 1.2.0 for Privacy)
3. **What changed?** The user can provide either:
   - A description of the changes
   - The full new document content (analyze and extract key changes)

### Version Format Validation (REQUIRED)

**All versions MUST use semantic versioning: `MAJOR.MINOR.PATCH` (e.g., 1.0.0, 1.2.3, 2.0.0)**

Always validate and auto-correct the user's version input:

| User Input | Corrected To | Rule |
|------------|--------------|------|
| `1.1.0` | `1.1.0` | Valid, no change |
| `1.1` | `1.1.0` | Missing patch → append `.0` |
| `2` | `2.0.0` | Missing minor.patch → append `.0.0` |
| `1.01` | `1.0.1` | Leading zero = separate digit |
| `1.10` | `1.10.0` | Missing patch → append `.0` |
| `2.05` | `2.0.5` | Leading zero = separate digit |

**Rules:**
- Version must have exactly 3 parts separated by dots: `X.Y.Z`
- If user provides 2 parts, append `.0` (e.g., `1.1` → `1.1.0`)
- If user provides 1 part, append `.0.0` (e.g., `2` → `2.0.0`)
- Leading zeros indicate separate digits (e.g., `1.01` → `1.0.1`, `2.05` → `2.0.5`)
- **If any correction is made, note it at the end of your message:**
  ```
  Note: Version corrected from `1.01` to `1.0.1`
  ```

### Step 2: Generate Change Notes

Based on the user's input, create well-formatted change notes using Markdown.

**Format:**
```
What's changed in our Terms of Service:

- **Section Name** - Brief description of what changed
- **Another Section** - What was updated or added
```

Or for Privacy Policy:
```
What's changed in our Privacy Policy:

- **Data Collection** - Brief description of change
- **Third Parties** - What was updated
```

**Guidelines:**
- Keep bullet points concise (one line each)
- Use **bold** for the section/topic name
- Keep language user-friendly (not legalese)
- Focus on what matters to users
- 4-8 bullet points max per document
- Put the most significant changes first

### Step 3: Create Migration File

Generate the SQL migration:

1. **Filename conventions:**
   - ToS only: `YYYYMMDDHHMMSS_tos_version_X_X_X.sql`
   - Privacy only: `YYYYMMDDHHMMSS_privacy_version_X_X_X.sql`
   - Both: `YYYYMMDDHHMMSS_legal_update_tos_X_X_X_privacy_Y_Y_Y.sql`
   - Use current date/time for timestamp
   - Replace dots with underscores in versions

2. **SQL for single document (ToS example):**
```sql
-- Terms of Service Version X.X.X
-- Date: YYYY-MM-DD

INSERT INTO public.version_log (type, version, message)
VALUES (
    'tos',
    'X.X.X',
    $$What's changed in our Terms of Service:

- **Section Name** - Brief description of change
- **Another Section** - What was updated$$
);
```

3. **SQL for single document (Privacy example):**
```sql
-- Privacy Policy Version X.X.X
-- Date: YYYY-MM-DD

INSERT INTO public.version_log (type, version, message)
VALUES (
    'privacy',
    'X.X.X',
    $$What's changed in our Privacy Policy:

- **Section Name** - Brief description of change
- **Another Section** - What was updated$$
);
```

4. **SQL for both documents:**
```sql
-- Legal Update: ToS X.X.X, Privacy Y.Y.Y
-- Date: YYYY-MM-DD

INSERT INTO public.version_log (type, version, message)
VALUES (
    'tos',
    'X.X.X',
    $$What's changed in our Terms of Service:

- **Section Name** - Brief description$$
);

INSERT INTO public.version_log (type, version, message)
VALUES (
    'privacy',
    'Y.Y.Y',
    $$What's changed in our Privacy Policy:

- **Section Name** - Brief description$$
);
```

**Important:** Do NOT include `app_update_type` column - it's only used for 'app' type entries.

### Step 4: Confirm with User

Show the user:
1. The generated change notes for each document
2. The full SQL migration
3. The migration filename

Ask if they want any changes before creating the file.

### Step 5: Create File and Deploy

Write the migration file to `supabase/migrations/`.

Remind the user to deploy:
```bash
# Development
supabase db push --linked

# Production
supabase db push --linked --db-url <production-url>
```

## Example Interaction

**User:** I need to update our Terms of Service

**Claude:** What version number should this be? (e.g., 1.1.0)

**User:** 1.1.0

**Claude:** What changed in the Terms of Service? You can describe the changes or share the full document for me to analyze.

**User:** We added a section about AI-generated content and updated our refund policy to be more clear

**Claude:** Here's the change notes I've drafted:

```
What's changed in our Terms of Service:

- **AI-Generated Content** - New section covering how AI features work and user responsibilities
- **Refund Policy** - Clarified the conditions and timeframes for requesting refunds
```

Does this look good, or would you like any changes?

## Example: Both Documents

**User:** I need to update both ToS and Privacy Policy

**Claude:** What version numbers should these be?

**User:** ToS 1.2.0, Privacy 1.1.0

**Claude:** What changed in each document?

**User:** ToS: added arbitration clause. Privacy: we now use a new analytics provider and updated data retention to 2 years

**Claude:** Here are the change notes:

**Terms of Service 1.2.0:**
```
What's changed in our Terms of Service:

- **Dispute Resolution** - Added binding arbitration clause for resolving disputes
```

**Privacy Policy 1.1.0:**
```
What's changed in our Privacy Policy:

- **Analytics** - We now use [Provider Name] for app analytics
- **Data Retention** - Updated retention period to 2 years
```

Does this look good?
