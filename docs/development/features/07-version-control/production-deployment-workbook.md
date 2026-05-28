# Production Deployment Workbook: Version Control System

This is the step-by-step workbook for deploying the Version Control & Compliance feature to production.

**Target Version:** 1.0.5
**Minimum Supported Version:** 1.0.5 (set by migration)

> **Note on 1.0.4 Compatibility:** Existing 1.0.4 users will NOT be affected by the version control system. They don't have the `get_app_config()` implementation, so they'll continue working normally. The min_supported_version only affects clients that check it (1.0.5+).

---

## Pre-Deployment Checklist

Before starting, ensure:

- [x] All code changes are committed and tested on development
- [x] iOS build is ready for TestFlight (version 1.0.5)
- [x] You have access to production Supabase project (`vipghlhvnrdheoydynty`)
- [x] Development database has been tested with these migrations

---

## Step 1: Build iOS App for TestFlight

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

## Step 2: Apply Database Migrations to Production

### 2.1 Link to Production Project

```bash
supabase link --project-ref vipghlhvnrdheoydynty
```

### 2.2 Push Migrations

```bash
supabase db push
```

This will apply in order:

| Order | File | Purpose |
|-------|------|---------|
| 1 | `20260120143000_version_control.sql` | Core schema, tables, functions |
| 2 | `20260122100000_fix_accept_terms_ambiguity.sql` | Parameter naming fix |
| 3 | `20260131000000_semantic_version_comparison.sql` | Semantic version comparison functions |
| 4 | `20260203000000_add_last_force_message.sql` | Force message in config response |
| 5 | `20260203100000_refactor_get_app_config_returns_table.sql` | Config function improvements |
| 6 | `20260203120000_production_seed_data.sql` | **Production data: versions, backfill, config** |

### 2.3 Verify Deployment

Run in Supabase SQL Editor:

```sql
-- Check tables exist
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN ('version_log', 'user_agreements', 'app_config');

-- Check version_log has correct entries
SELECT type, version, message, app_update_type, released_at
FROM public.version_log
ORDER BY type, released_at DESC;

-- Expected:
-- app: 1.0.5 (force), 1.0.4 (soft)
-- privacy: 1.0.0
-- tos: 1.0.0

-- Check app_config
SELECT * FROM public.app_config;
-- Expected: min_supported_version = '1.0.5'

-- Check user backfill completed
SELECT COUNT(*) as backfilled_users FROM public.user_agreements;
SELECT COUNT(*) as total_users FROM auth.users;
-- These should match
```

---

## Step 3: Test with Existing 1.0.4 App

Before releasing the new app:

1. Open the existing production app (1.0.4)
2. Sign in as an existing user
3. **Expected:** App works normally, no legal modal, no update prompts
4. Create a discovery, use all features
5. **Expected:** Everything works as before

This confirms backward compatibility.

---

## Step 4: Release TestFlight Build

1. Go to App Store Connect
2. Select the TestFlight build (1.0.5)
3. Release to internal testers

---

## Step 5: TestFlight Testing Checklist

### 5.1 Existing User Login (CRITICAL)

1. Install new app (1.0.5) from TestFlight
2. Sign in as existing user (who was backfilled)
3. **Expected:** NO legal modal (they already accepted 1.0.0)
4. Navigate through the app - Discoveries, Camera, Audio Guides
5. **Expected:** App works normally, no unexpected prompts

### 5.2 New User Signup

1. Create a new account with fresh email
2. **Expected:** Signup completes with terms checkbox visible
3. Complete onboarding
4. **Expected:** No additional legal modal after onboarding
5. Check database:
   ```sql
   SELECT * FROM public.user_agreements WHERE user_id = '<new-user-id>';
   ```
   Should show `tos_version = '1.0.0'`, `privacy_version = '1.0.0'`

### 5.3 Test Legal Modal Trigger (ToS Update)

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

### 5.4 Test Maintenance Mode

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

### 5.5 Test Force Update (Grace Period)

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

### 5.6 Test Soft Update Reminder

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

### 5.7 Test Safe Screen Deferral

1. Trigger a legal modal (add ToS 1.1.0 as above)
2. Navigate to Camera tab BEFORE the modal can appear
3. **Expected:** Modal should NOT appear during camera use
4. Navigate back to Discoveries tab
5. **Expected:** Modal appears now (safe screen)
6. Clean up as above

---

## Step 6: Release to App Store

Once all tests pass:

1. Go to App Store Connect
2. Submit version 1.0.5 for review
3. Release when approved

---

## Step 7: Monitor

After deployment:

1. Check Supabase logs for any RPC errors
2. Monitor `user_agreements` table for new signups
3. Watch for any user reports of unexpected modals

```sql
-- Monitor new agreements
SELECT user_id, tos_version, privacy_version, accepted_at
FROM public.user_agreements
ORDER BY accepted_at DESC
LIMIT 20;
```

---

## Rollback Plan

If something goes wrong:

### If users are incorrectly seeing legal modal:

```sql
-- Emergency backfill for anyone who was missed
INSERT INTO public.user_agreements (user_id, tos_version, privacy_version, accepted_at)
SELECT id, '1.0.0', '1.0.0', created_at
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

After deployment is complete, use the Claude skills for future releases:

| Task | Skill |
|------|-------|
| Update ToS or Privacy Policy | `/legal-update` |
| Release new app version | `/release-update` |

See `docs/production-management/version-releases.md` for detailed procedures.

---

## Quick Reference

### Database State After Deployment

```sql
-- version_log should have:
-- app: 1.0.5 (force), 1.0.4 (soft)
-- tos: 1.0.0
-- privacy: 1.0.0

-- app_config should have:
-- min_supported_version: '1.0.5'
-- maintenance_mode: false

-- user_agreements should have:
-- All existing users with tos_version='1.0.0', privacy_version='1.0.0'
-- accepted_at = their signup date
```

### Environments

| Environment | Project ID | Use For |
|-------------|------------|---------|
| **Development** | `cywshvmspnvimucwqarc` | Testing |
| **Production** | `vipghlhvnrdheoydynty` | Real users |

---

## TL;DR Deployment Steps

1. **Build:** Create iOS 1.0.5 archive, upload to TestFlight
2. **Database:** `supabase db push` to production
3. **Verify:** Check tables, versions, and backfill in SQL editor
4. **Test 1.0.4:** Confirm old app still works
5. **TestFlight:** Release and run through checklist
6. **Ship:** Submit to App Store when ready

---

*Last updated: 2026-02-03*
