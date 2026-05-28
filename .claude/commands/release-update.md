# Release Update

Generate a database migration for an app update release.

## Instructions

Work with the user to create an app update release. Follow these steps:

### Step 1: Gather Information

Ask the user:
1. **What version number?** (e.g., 1.1.0, 2.0.0)
2. **What type of update?**
   - `soft` - Optional update, shows dismissible prompt
   - `force` - Required update, 7-day grace period then blocks
3. **What changed in this release?** Ask them to describe:
   - New features
   - Improvements
   - Bug fixes
   - Security updates

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

### Step 2: Generate Update Notes

Based on the user's input, create a well-formatted update message using Markdown:

**Format:**
```
What's new in this update:

- **Feature/Change 1** - Brief description
- **Feature/Change 2** - Brief description
- **Bug fixes** - What was fixed (if applicable)
```

**Guidelines:**
- Keep bullet points concise (one line each)
- Use **bold** for the feature name
- Group related changes together
- Put the most important/exciting changes first
- Don't exceed 6-8 bullet points
- Use user-friendly language (avoid technical jargon)

### Step 3: Create Migration File

Generate the SQL migration:

1. Create filename: `supabase/migrations/YYYYMMDDHHMMSS_app_version_X_X_X.sql`
   - Use current date/time for timestamp
   - Replace X_X_X with version (underscores instead of dots)

2. Write the migration:
```sql
-- App Version X.X.X Release
-- Type: soft/force
-- Date: YYYY-MM-DD

INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES (
    'app',
    'X.X.X',
    $$What's new in this update:

- **Feature 1** - Description
- **Feature 2** - Description$$,
    'soft'
);
```

### Step 4: Confirm with User

Show the user:
1. The generated update notes
2. The full SQL migration
3. The filename

Ask if they want any changes before creating the file.

### Step 5: Create the File

Write the migration file to `supabase/migrations/`.

Remind the user to deploy:
```bash
# Development
supabase db push --linked

# Production
supabase db push --linked --db-url <production-url>
```

## Example Interaction

**User:** I want to release version 1.2.0

**Claude:** What type of update is this - soft (optional) or force (required)?

**User:** Soft

**Claude:** What changes are in this release? Tell me about new features, improvements, or bug fixes.

**User:** We added dark mode support, fixed a crash on older iPhones, and improved the camera performance

**Claude:** Here's the update message I've drafted:

```
What's new in this update:

- **Dark mode support** - The app now follows your system appearance
- **Improved camera** - Faster and more responsive photo capture
- **Bug fixes** - Resolved a crash affecting older iPhone models
```

Does this look good, or would you like any changes?
