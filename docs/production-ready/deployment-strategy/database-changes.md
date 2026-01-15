# Database Schema Changes

This document covers how to safely make database schema changes when you have users on multiple app versions.

## The Core Problem

Once your app is in the App Store, you lose control over which version users are running. Your database must support ALL app versions currently in the wild.

## Types of Schema Changes

### ✅ Safe Changes (Additive)

These changes are backwards compatible and safe to deploy immediately:

| Change Type | Why It's Safe |
|-------------|---------------|
| Add new table | Old app versions ignore it |
| Add nullable column | Old app versions ignore it, NULL is valid default |
| Add column with default value | Old app versions ignore it, default fills existing rows |
| Add index | Query optimization only, no API change |
| Add RLS policy | Security improvement, transparent to app |

**Example: Adding a favorites feature**
```sql
-- Safe: new nullable column with default
ALTER TABLE discoveries 
ADD COLUMN is_favorite BOOLEAN DEFAULT false;
```

### ⚠️ Breaking Changes (Dangerous)

These require careful migration planning:

| Change Type | Why It's Dangerous |
|-------------|-------------------|
| Rename column | Old app queries the old name, gets errors |
| Remove column | Old app queries it, gets errors |
| Change column type | Old app may send/receive wrong type |
| Make nullable column required | Old app might not send the value |
| Change column constraints | May reject data old app considers valid |

## Migration Strategies for Breaking Changes

### Strategy 1: Parallel Columns (Recommended)

When you need to rename or change a column:

```
Phase 1: Add new column alongside old
         - Both columns exist
         - Edge functions write to BOTH
         - Old app reads old column
         - New app reads new column

Phase 2: All users updated (weeks/months later)
         - Stop writing to old column
         - Old column becomes stale

Phase 3: Cleanup (optional)
         - Remove old column if certain no old apps remain
```

**Example: Renaming `description` to `detailed_description`**

```sql
-- Phase 1: Add new column
ALTER TABLE discoveries 
ADD COLUMN detailed_description TEXT;

-- Backfill existing data
UPDATE discoveries 
SET detailed_description = description 
WHERE detailed_description IS NULL;
```

```typescript
// Edge function: write to both during transition
await supabase.from('discoveries').update({
  description: text,           // for old app versions
  detailed_description: text   // for new app versions
});
```

### Strategy 2: API Versioning

For complex changes, expose different API behavior:

```typescript
// Edge function checks app version
const appVersion = req.headers.get('X-App-Version');

if (compareVersions(appVersion, '2.0.0') >= 0) {
  // New behavior for v2+ apps
  return newResponseFormat(data);
} else {
  // Legacy behavior for v1.x apps
  return legacyResponseFormat(data);
}
```

### Strategy 3: Feature Flags

Use a feature flags table to control rollout:

```sql
CREATE TABLE feature_flags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  enabled BOOLEAN DEFAULT false,
  min_app_version TEXT,
  rollout_percentage INTEGER DEFAULT 100
);
```

## Never Do These Directly

| Action | Why Not | Alternative |
|--------|---------|-------------|
| `DROP COLUMN` | Breaks old apps immediately | Wait 6+ months, then drop |
| `ALTER COLUMN SET NOT NULL` | Old apps may send NULL | Handle NULL in edge function |
| `RENAME COLUMN` | Breaks old app queries | Use parallel columns |
| `ALTER COLUMN TYPE` | May break serialization | Add new column with new type |

## Testing Schema Changes

1. **Test on Development first**
   - Apply migration to dev database
   - Test with current app version (ensure nothing breaks)
   - Test with new app version (ensure new feature works)

2. **Apply to Production**
   - Run migration during low-traffic period
   - Monitor logs for errors
   - Have rollback plan ready

3. **Deploy app update after**
   - Backend is already ready
   - New app version uses new schema
   - Old app versions unaffected

## Rollback Considerations

### Easy to Rollback
- New columns (just ignore them, or drop if unused)
- New tables (drop if unused)
- New indexes (drop if performance issue)

### Hard to Rollback
- Removed columns (data is gone)
- Type changes (data may be converted)
- Constraint changes (data may now violate old constraints)

> [!CAUTION]
> Always keep backups before running migrations on production. Supabase provides point-in-time recovery, but verify it's enabled for your project.

## Checklist: Before Any Schema Change

- [ ] Is this change additive (safe) or breaking (dangerous)?
- [ ] If breaking, which migration strategy will I use?
- [ ] Have I tested on the development database?
- [ ] Have I tested with both old and new app versions?
- [ ] Do I have a rollback plan?
- [ ] Have I scheduled the migration for low-traffic time?
- [ ] Am I deploying backend first, then app?
