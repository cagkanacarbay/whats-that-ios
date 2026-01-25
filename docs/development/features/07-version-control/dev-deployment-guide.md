# Version Control & Compliance: Dev Deployment & Testing Guide

This guide walks you through deploying and testing the Version Control & Compliance feature on your development environment.

---

## Prerequisites

- Supabase CLI installed and linked to your dev project
- Xcode with the project open
- iOS Simulator or physical device for testing

---

## Step 1: Deploy Database Migration

### 1.1 Push Migration to Dev Database

From the project root, run:

```bash
supabase db push
```

This will apply the migration file:

- `supabase/migrations/20260120143000_version_control.sql`

**What the migration creates:**

- ENUMs: `version_type`, `update_type`
- Tables: `version_log`, `user_agreements`, `app_config`
- RLS policies
- Initial seed data (ToS v1.0, Privacy v1.0, App v1.0.0)
- Database functions: `get_app_config()`, `accept_terms()`

### 1.2 Verify Tables Created

Run these queries to verify:

```sql
-- Check tables exist
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN ('version_log', 'user_agreements', 'app_config');

-- Check seed data
SELECT * FROM public.version_log;
SELECT * FROM public.app_config;
```

You should see:

- 3 rows in `version_log` (tos v1.0, privacy v1.0, app v1.0.0)
- 1 row in `app_config`

### 1.3 Test RPC Functions

Test as an authenticated user:

```sql
-- Test get_app_config (run as authenticated user via Supabase client or test account)
SELECT public.get_app_config();
```

Expected response structure:

```json
{
  "maintenance": { "enabled": false, "message": null },
  "tos": { "version": "1.0", "message": "Initial Terms of Service", "released_at": "..." },
  "privacy": { "version": "1.0", "message": "Initial Privacy Policy", "released_at": "..." },
  "app": { "version": "1.0.0", ... },
  "user_status": { "needs_tos_acceptance": true, "needs_privacy_acceptance": true, ... }
}
```

---

## Step 2: Backfill Existing Users (If Any)

If you have existing test users, run this to mark them as having accepted v1.0 terms:

```sql
INSERT INTO public.user_agreements (user_id, tos_version, privacy_version, accepted_at)
SELECT id, '1.0', '1.0', NOW()
FROM auth.users
WHERE id NOT IN (SELECT DISTINCT user_id FROM public.user_agreements);
```

---

## Step 3: Build and Run iOS App

### 3.1 Clean Build

```bash
cd native/WhatsThatIOS
rm -rf ~/Library/Developer/Xcode/DerivedData/WhatsThat*
xcodebuild clean -project WhatsThatIOS.xcodeproj -scheme WhatsThatIOS
```

### 3.2 Build and Run

Open in Xcode and build (Cmd+B), then run on simulator or device.

---

## Step 4: Test Scenarios

### Test Case 1: New User Signup

1. **Fresh install** the app (delete and reinstall)
2. Go through pre-onboarding carousel
3. Create a new account (email signup)
4. **Expected:** User should complete signup with terms checkbox
5. Check database: `SELECT * FROM user_agreements WHERE user_id = '<new-user-id>';`
6. **Expected:** Row with tos_version='1.0', privacy_version='1.0'

### Test Case 2: Terms Update - Legal Modal Appears

1. Login as an existing user who has accepted v1.0
2. In Supabase, add a new ToS version:
   ```sql
   INSERT INTO public.version_log (type, version, message)
   VALUES ('tos', '1.1', 'Updated Terms of Service - January 2026');
   ```
3. Force app refresh (background then foreground, or kill and relaunch)
4. **Expected:** Legal acceptance modal should appear on the Discoveries tab
5. Toggle checkbox, tap "Accept and Continue"
6. **Expected:** Modal dismisses, app works normally
7. Check database: New row in `user_agreements` with tos_version='1.1'

### Test Case 3: Legal Modal Deferred on Unsafe Screens

1. Make sure user needs to accept new terms (insert new version in DB)
2. Navigate to Camera tab and start taking a photo
3. **Expected:** Legal modal should NOT appear during camera capture
4. Complete or cancel photo capture
5. Navigate back to Discoveries tab
6. **Expected:** Legal modal appears now (on safe screen)

### Test Case 4: Maintenance Mode

1. Enable maintenance mode:
   ```sql
   UPDATE public.app_config SET maintenance_mode = true, maintenance_message = 'Server maintenance in progress. Back in 10 minutes!';
   ```
2. Force app refresh
3. **Expected:** Maintenance blocking screen appears
4. Tap "Check Again" (should be rate-limited to 1 per minute)
5. Disable maintenance:
   ```sql
   UPDATE public.app_config SET maintenance_mode = false;
   ```
6. Tap "Check Again"
7. **Expected:** App returns to normal

### Test Case 5: Force Update (Below Min Version)

1. Update app_config to require version higher than current:
   ```sql
   UPDATE public.app_config SET min_supported_version = '99.0.0';
   ```
2. Force app refresh
3. **Expected:** Force update blocking screen appears
4. Tap "Update Now" should open App Store URL
5. Tap "Check Again" to verify still blocked
6. Reset:
   ```sql
   UPDATE public.app_config SET min_supported_version = '1.0.0';
   ```

### Test Case 6: Force Update with Grace Period

1. Add a force update version (less than min_supported to trigger grace):
   ```sql
   INSERT INTO public.version_log (type, version, message, app_update_type)
   VALUES ('app', '2.0.0', 'Critical security update', 'force');
   ```
2. Force app refresh
3. **Expected:** Grace period warning sheet appears (dismissible)
4. Dismiss the sheet
5. **Expected:** App works normally for 7 days
6. To test expiration, manually set grace period start in the past (requires app modification or UserDefaults manipulation)

### Test Case 7: Soft Update Reminder

1. Add a soft update:
   ```sql
   INSERT INTO public.version_log (type, version, message, app_update_type)
   VALUES ('app', '1.5.0', 'New features and improvements', 'soft');
   ```
2. Force app refresh
3. **Expected:** Soft update sheet appears (Day 1)
4. Tap "Maybe Later" to dismiss
5. **Expected:** Reminder reappears on Day 3, Day 7 (simulate by changing local state)

### Test Case 8: Sign Out Clears State

1. Accept terms, dismiss update reminders
2. Sign out
3. Sign in as different user (or same user)
4. **Expected:** Compliance state is fresh (re-fetched from server)

### Test Case 9: Offline Behavior

1. Enable airplane mode
2. Kill and relaunch app
3. **Expected:** App should work (fail-open) unless maintenance was cached
4. If maintenance was cached and is still valid (< 3 hours), maintenance screen appears

---

## Step 5: Verify Database State

After testing, verify the database looks correct:

```sql
-- Check user agreements
SELECT
    ua.user_id,
    u.email,
    ua.tos_version,
    ua.privacy_version,
    ua.accepted_at
FROM public.user_agreements ua
JOIN auth.users u ON ua.user_id = u.id
ORDER BY ua.accepted_at DESC;

-- Check version log
SELECT * FROM public.version_log ORDER BY released_at DESC;

-- Check app config
SELECT * FROM public.app_config;
```

---

## Step 6: Reset Test Data (Optional)

To reset and start fresh:

```sql
-- Clear user agreements
DELETE FROM public.user_agreements;

-- Reset version log to initial state
DELETE FROM public.version_log;
INSERT INTO public.version_log (type, version, message) VALUES
  ('tos', '1.0', 'Initial Terms of Service'),
  ('privacy', '1.0', 'Initial Privacy Policy'),
  ('app', '1.0.0', 'Initial release');

-- Reset app config
UPDATE public.app_config SET
  min_supported_version = '1.0.0',
  maintenance_mode = false,
  maintenance_message = null;
```

---

## Troubleshooting

### "No ToS version found" Error

Make sure the `version_log` table has entries:

```sql
SELECT * FROM public.version_log WHERE type = 'tos';
```

### Legal Modal Not Appearing

1. Check `user_status` in the config response:
   ```sql
   SELECT public.get_app_config();
   ```
2. Verify `needs_tos_acceptance` or `needs_privacy_acceptance` is `true`
3. Make sure you're on a "safe" screen (Discoveries or Audio Guides, not Camera)

### RPC Function Errors

Check function exists:

```sql
SELECT routine_name FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN ('get_app_config', 'accept_terms');
```

### Build Errors

If you see compilation errors:

1. Clean derived data
2. Resolve Swift packages (File > Packages > Resolve Package Versions)
3. Make sure `USE_REMOTE_DEPS` is set in build configuration

---

## Files Created/Modified Summary

### New Files Created

- `supabase/migrations/20260120143000_version_control.sql`
- `Sources/WhatsThatDomain/VersionControl/AppConfigModels.swift`
- `Sources/WhatsThatDomain/VersionControl/VersionComparisonExtension.swift`
- `Sources/WhatsThatDomain/VersionControl/AppConfigRepository.swift`
- `Sources/WhatsThatDomain/VersionControl/ComplianceUseCase.swift`
- `Sources/WhatsThatDomain/VersionControl/ComplianceLocalStore.swift`
- `Sources/WhatsThatData/Repositories/Compliance/SupabaseAppConfigRepository.swift`
- `Sources/WhatsThatData/Repositories/Compliance/UserDefaultsComplianceLocalStore.swift`
- `Sources/WhatsThatShared/Extensions/Bundle+AppVersion.swift`
- `Sources/WhatsThatPresentation/Features/Compliance/ComplianceOverlayView.swift`
- `Sources/WhatsThatPresentation/Features/Compliance/LegalAcceptanceModalView.swift`
- `Sources/WhatsThatPresentation/Features/Compliance/MaintenanceBlockingView.swift`
- `Sources/WhatsThatPresentation/Features/Compliance/ForceUpdateBlockingView.swift`
- `Sources/WhatsThatPresentation/Features/Compliance/SoftUpdatePromptView.swift`
- `Sources/WhatsThatPresentation/Features/Compliance/ForceUpdateGracePromptView.swift`

### Files Modified

- `Sources/WhatsThatApp/DependencyInjection/AppDependencyContainer.swift`
- `Sources/WhatsThatApp/AppEntry/AppRootView.swift`
- `Sources/WhatsThatPresentation/App/AppRootViewModel.swift`
- `Sources/WhatsThatPresentation/App/RootContentView.swift`
- `Sources/WhatsThatPresentation/App/MainTabView.swift`

---

## Next Steps (Production Deployment)

1. Test thoroughly on dev environment
2. Run migration on **staging** environment
3. Deploy iOS build to TestFlight
4. Test on staging with TestFlight build
5. Run migration on **production** (including existing user backfill)
6. Submit iOS app update to App Store
7. Monitor for errors via Supabase logs and app analytics
