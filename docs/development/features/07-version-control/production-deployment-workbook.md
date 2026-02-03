# Production Deployment Workbook: Version Control System

This is the step-by-step workbook for deploying the Version Control & Compliance feature to production.

**Target Version:** 1.0.5
**Minimum Supported Version:** 1.0.5 (will be set after deployment)

> **Note on 1.0.4 Compatibility:** Existing 1.0.4 users will NOT be affected by the version control system. They don't have the `get_app_config()` implementation, so they'll continue working normally. The min_supported_version only affects clients that check it (1.0.5+).

---

## Pre-Deployment Checklist

Before starting, ensure:

- [ ] All code changes are committed and tested on development
- [ ] Grace period is set to **7 days** (not 2 minutes) in `ComplianceUseCase.swift`
- [ ] iOS build is ready for TestFlight (version 1.0.5)
- [ ] You have access to production Supabase project

---

## Step 1: Prepare Git State

### 1.1 Fix Staged/Untracked Migration Files

```bash
# Unstage the deleted 1.0.6 file (it was added then deleted)
git reset HEAD supabase/migrations/20260202120000_app_version_1_0_6.sql

# Stage the last_force_message migration
git add supabase/migrations/20260203000000_add_last_force_message.sql

# Stage the VersionUpgradeBadge.swift
git add native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/Compliance/VersionUpgradeBadge.swift

# Verify status
git status
```

### 1.2 Update Grace Period to Production Value

In `ComplianceUseCase.swift` line ~242, change:
```swift
// FROM (testing):
let gracePeriodSeconds: TimeInterval = 2 * 60 // 2 minutes

// TO (production):
let gracePeriodSeconds: TimeInterval = 7 * 24 * 60 * 60 // 7 days
```

---

## Step 2: Create Seed Data Migration

Create a new migration file for production seed data:

```bash
# Create the file
touch supabase/migrations/20260203120000_initial_seed_data.sql
```

Add this content:

```sql
-- Initial Seed Data for Production
-- App Version 1.0.4 (current production)
-- ToS and Privacy Policy 1.0.0

-- Seed current production app version
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '1.0.4', 'Initial production release', 'soft')
ON CONFLICT DO NOTHING;

-- Seed ToS version (users accepted this at signup)
INSERT INTO public.version_log (type, version, message)
VALUES ('tos', '1.0.0', 'Initial Terms of Service')
ON CONFLICT DO NOTHING;

-- Seed Privacy Policy version (users accepted this at signup)
INSERT INTO public.version_log (type, version, message)
VALUES ('privacy', '1.0.0', 'Initial Privacy Policy')
ON CONFLICT DO NOTHING;
```

**Note:** The core migration `20260120143000_version_control.sql` already seeds v1.0.0 for ToS/Privacy/App, but App is seeded as "1.0.0" not "1.0.4". If the core migration runs first, you may need to UPDATE the app version instead:

```sql
-- Alternative: Update app version from 1.0.0 to 1.0.4 if already seeded
UPDATE public.version_log
SET version = '1.0.4', message = 'Initial production release'
WHERE type = 'app' AND version = '1.0.0';
```

---

## Step 3: Build iOS App for TestFlight

```bash
# Build with production settings
USE_REMOTE_DEPS=1 xcodebuild \
  -workspace native/WhatsThatIOS.xcworkspace \
  -scheme WhatsThatIOS \
  -destination 'generic/platform=iOS' \
  -configuration Release archive
```

Then upload to TestFlight via Xcode or Transporter.

**DO NOT release the TestFlight build yet** - wait until database is ready.

---

## Step 4: Apply Database Migrations to Production

### 4.1 Link to Production Project

```bash
supabase link --project-ref vipghlhvnrdheoydynty
```

### 4.2 Push Migrations

```bash
supabase db push
```

This will apply in order:
1. `20260120143000_version_control.sql` - Core schema + seed data
2. `20260122100000_fix_accept_terms_ambiguity.sql` - Parameter fix
3. `20260131000000_semantic_version_comparison.sql` - Version comparison
4. `20260203000000_add_last_force_message.sql` - Force message fix
5. `20260203120000_initial_seed_data.sql` - Production seed data (if created)

### 4.3 Verify Tables Created

Run in Supabase SQL Editor:

```sql
-- Check tables exist
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN ('version_log', 'user_agreements', 'app_config');

-- Check seed data
SELECT * FROM public.version_log ORDER BY type, released_at DESC;

-- Check app config
SELECT * FROM public.app_config;
```

Expected:
- 3 tables created
- version_log has entries for app, tos, privacy
- app_config has 1 row

---

## Step 5: Backfill Existing Users (CRITICAL)

**This step is CRITICAL.** Without this, all existing users will see the legal acceptance modal on their next app launch.

### 5.1 Run Backfill Query

In Supabase SQL Editor (PRODUCTION):

```sql
-- Backfill: Give all existing users acceptance records for ToS/Privacy 1.0.0
-- They agreed to these at signup, so they shouldn't be prompted again

INSERT INTO public.user_agreements (user_id, tos_version, privacy_version, accepted_at)
SELECT id, '1.0.0', '1.0.0', NOW()
FROM auth.users
WHERE id NOT IN (SELECT DISTINCT user_id FROM public.user_agreements);
```

### 5.2 Verify Backfill

```sql
-- Check count of backfilled users
SELECT COUNT(*) as agreements_count FROM public.user_agreements;

-- Verify against total users
SELECT COUNT(*) as users_count FROM auth.users;

-- These should match (or be very close)
```

### 5.3 Spot Check

```sql
-- Check a few random users have agreements
SELECT
    u.email,
    ua.tos_version,
    ua.privacy_version,
    ua.accepted_at
FROM auth.users u
LEFT JOIN public.user_agreements ua ON u.id = ua.user_id
LIMIT 10;
```

All users should have `tos_version = '1.0.0'` and `privacy_version = '1.0.0'`.

---

## Step 6: Set Up App Versions in Database

### 6.1 Update Initial App Version to 1.0.4

The core migration seeds app version as 1.0.0. Update it to reflect the actual first production release:

```sql
-- Update to correct first production version
UPDATE public.version_log
SET version = '1.0.4', message = 'Initial production release'
WHERE type = 'app' AND version = '1.0.0';

-- Verify
SELECT * FROM public.version_log WHERE type = 'app';
```

### 6.2 Add Version 1.0.5 Entry

Add the new version we're deploying:

```sql
-- Add 1.0.5 as a soft update (users coming from 1.0.4 won't see this anyway)
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '1.0.5', 'Version control system, bug fixes, and improvements', 'soft');
```

### 6.3 Set Minimum Supported Version to 1.0.5

```sql
-- Set minimum supported version
-- Note: This only affects 1.0.5+ clients. 1.0.4 clients don't check this.
UPDATE public.app_config
SET min_supported_version = '1.0.5';

-- Verify
SELECT * FROM public.app_config;
```

> **Why this is safe:** 1.0.4 users don't have the version control system, so they won't see any blocking screens. They'll continue using the app normally. Only future versions (1.0.5+) will check and enforce the minimum version.

---

## Step 7: Deploy Edge Functions (If Changed)

If you made changes to edge functions:

```bash
supabase functions deploy --project-ref vipghlhvnrdheoydynty
```

---

## Step 8: Test with Existing 1.0.4 App

Before releasing the new app:

1. Open the existing production app (1.0.4)
2. Sign in as an existing user
3. **Expected:** App works normally, no legal modal, no update prompts
4. Create a discovery, use all features
5. **Expected:** Everything works as before

This confirms backward compatibility.

---

## Step 9: Release TestFlight Build

1. Go to App Store Connect
2. Select the TestFlight build
3. Release to internal testers

---

## Step 10: TestFlight Testing Checklist

With the new TestFlight build (1.0.5):

### 10.1 Existing User Login (CRITICAL)

1. Install new app (1.0.5) from TestFlight
2. Sign in as existing user (who was backfilled)
3. **Expected:** NO legal modal (they already accepted 1.0.0)
4. Navigate through the app - Discoveries, Camera, Audio Guides
5. **Expected:** App works normally, no unexpected prompts

### 10.2 New User Signup

1. Create a new account with fresh email
2. **Expected:** Signup completes with terms checkbox visible
3. Complete onboarding
4. **Expected:** No additional legal modal after onboarding
5. Check database:
   ```sql
   SELECT * FROM public.user_agreements WHERE user_id = '<new-user-id>';
   ```
   Should show `tos_version = '1.0.0'`, `privacy_version = '1.0.0'`

### 10.3 Test Legal Modal Trigger (ToS Update)

1. In Supabase SQL Editor, add a new ToS version:
   ```sql
   INSERT INTO public.version_log (type, version, message)
   VALUES ('tos', '1.1.0', 'Test update - delete after testing');
   ```
2. Kill and relaunch app (or background for 1+ hour then foreground)
3. **Expected:** Legal acceptance modal appears on Discoveries tab
4. Check the checkbox, tap "Accept and Continue"
5. **Expected:** Modal dismisses, app continues
6. **Clean up:**
   ```sql
   DELETE FROM public.version_log WHERE type = 'tos' AND version = '1.1.0';
   DELETE FROM public.user_agreements WHERE tos_version = '1.1.0';
   ```

### 10.4 Test Maintenance Mode

1. Enable maintenance:
   ```sql
   UPDATE public.app_config SET maintenance_mode = true, maintenance_message = 'Scheduled maintenance. Back shortly!';
   ```
2. Kill and relaunch app
3. **Expected:** Maintenance blocking screen appears with message
4. Tap "Check Again" - should still show maintenance
5. Disable:
   ```sql
   UPDATE public.app_config SET maintenance_mode = false, maintenance_message = null;
   ```
6. Tap "Check Again"
7. **Expected:** App returns to normal

### 10.5 Test Force Update (Grace Period)

1. Add a force update version higher than 1.0.5:
   ```sql
   INSERT INTO public.version_log (type, version, message, app_update_type)
   VALUES ('app', '2.0.0', 'Critical update required', 'force');
   ```
2. Kill and relaunch app
3. **Expected:** Force update grace period sheet appears (dismissible)
4. Shows "7 days remaining" (or similar)
5. Tap dismiss - app should work normally
6. **Clean up:**
   ```sql
   DELETE FROM public.version_log WHERE type = 'app' AND version = '2.0.0';
   ```

### 10.6 Test Soft Update Reminder

1. Add a soft update version higher than 1.0.5:
   ```sql
   INSERT INTO public.version_log (type, version, message, app_update_type)
   VALUES ('app', '1.1.0', 'New features available', 'soft');
   ```
2. Kill and relaunch app
3. **Expected:** Soft update reminder sheet appears
4. Tap "Maybe Later" - should dismiss
5. **Expected:** App works normally
6. **Clean up:**
   ```sql
   DELETE FROM public.version_log WHERE type = 'app' AND version = '1.1.0';
   ```

### 10.7 Test Safe Screen Deferral

1. Trigger a legal modal (add ToS 1.1.0 as above)
2. Navigate to Camera tab BEFORE the modal can appear
3. **Expected:** Modal should NOT appear during camera use
4. Navigate back to Discoveries tab
5. **Expected:** Modal appears now (safe screen)
6. Clean up as above

---

## Step 11: Monitor

After deployment:

1. Check Supabase logs for any RPC errors
2. Monitor `user_agreements` table for new signups
3. Watch for any user reports of unexpected modals

---

## Rollback Plan

If something goes wrong:

### If users are incorrectly seeing legal modal:

```sql
-- Emergency backfill for anyone who was missed
INSERT INTO public.user_agreements (user_id, tos_version, privacy_version, accepted_at)
SELECT id, '1.0.0', '1.0.0', NOW()
FROM auth.users
WHERE id NOT IN (SELECT DISTINCT user_id FROM public.user_agreements);
```

### If maintenance mode was accidentally enabled:

```sql
UPDATE public.app_config SET maintenance_mode = false;
```

### If need to revert entirely:

The old app (1.0.4) doesn't call `get_app_config()`, so it will continue working regardless of database state. The new tables don't affect old app behavior.

---

## Post-Deployment: Releasing Future Updates

See `deployment-guide.md` for how to:
- Release new ToS/Privacy versions
- Release new app versions (soft/force)
- Use the `/release-update` Claude command

---

## Quick Reference

### Migration Order

| Order | File | Purpose |
|-------|------|---------|
| 1 | `20260120143000_version_control.sql` | Core schema, tables, functions, initial seed |
| 2 | `20260122100000_fix_accept_terms_ambiguity.sql` | Parameter naming fix |
| 3 | `20260131000000_semantic_version_comparison.sql` | Semantic version functions |
| 4 | `20260203000000_add_last_force_message.sql` | Force message in response |

### Version Strategy

| Version | Status | Notes |
|---------|--------|-------|
| 1.0.4 | In production (App Store) | No version control, will keep working |
| 1.0.5 | Deploying now | Has version control, set as min_supported |

### Database State After Deployment

```sql
-- version_log should have:
-- app: 1.0.4 (initial), 1.0.5 (new)
-- tos: 1.0.0
-- privacy: 1.0.0

-- app_config should have:
-- min_supported_version: '1.0.5'
-- maintenance_mode: false

-- user_agreements should have:
-- All existing users with tos_version='1.0.0', privacy_version='1.0.0'
```

---

## TL;DR Deployment Steps

1. **Prep:** Fix git state, set grace period to 7 days, build 1.0.5
2. **Upload:** Submit to TestFlight (don't release yet)
3. **Database:** `supabase db push` to production
4. **Backfill:** Run the user backfill query
5. **Seed:** Update app version to 1.0.4, add 1.0.5, set min_supported_version
6. **Verify:** Check 1.0.4 still works
7. **Test:** Release TestFlight, run through checklist
8. **Ship:** Release to App Store when ready

---

*Last updated: 2026-02-03*
