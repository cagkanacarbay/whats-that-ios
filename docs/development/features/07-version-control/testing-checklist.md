# Version Control & Compliance - Testing Checklist

This document provides step-by-step test scenarios for the Version Control & Compliance feature. Work through each section in order.

## ✅ Testing Status

**Happy Path Tests (1-17): ALL PASSED**
- All core functionality verified and working correctly
- Legal acceptance, maintenance mode, force updates, soft updates all tested
- See detailed results in Summary section below

---

## Prerequisites

- [x] Dev Supabase project has migrations deployed
- [x] iOS app built and running on simulator or device
- [x] Access to Supabase SQL Editor (dev project)

**Dev Supabase Project ID:** `cywshvmspnvimucwqarc`

---

## Quick Reference: SQL Commands

### Check Current State
```sql
-- View current versions
SELECT type, version, message, app_update_type, released_at
FROM public.version_log
ORDER BY type, released_at DESC;

-- View app config
SELECT * FROM public.app_config;

-- View user agreements (replace user_id)
SELECT * FROM public.user_agreements ORDER BY accepted_at DESC;
```

### Reset to Clean State
```sql
-- Reset version log to initial state
DELETE FROM public.version_log;
INSERT INTO public.version_log (type, version, message) VALUES
  ('tos', '1.0.0', 'Initial Terms of Service'),
  ('privacy', '1.0.0', 'Initial Privacy Policy'),
  ('app', '1.0.0', 'Initial release');

-- Reset app config
UPDATE public.app_config SET
  min_supported_version = '1.0.0',
  maintenance_mode = false,
  maintenance_message = null;

-- Clear user agreements (for fresh testing)
DELETE FROM public.user_agreements;
```

---

## Test 1: New User Signup

**Purpose:** Verify new users can sign up and their terms acceptance is recorded.

### Steps

1. [x] Fresh install the app (delete and reinstall if needed)
2. [x] Go through pre-onboarding carousel
3. [x] Create a new account via email signup
4. [x] Complete post-onboarding
5. [x] Navigate to Discoveries tab

### Verify in Database

```sql
-- Get the new user's ID
SELECT id, email, created_at FROM auth.users ORDER BY created_at DESC LIMIT 1;

-- Check their agreement record (replace <user-id>)
SELECT * FROM public.user_agreements WHERE user_id = '<user-id>';
```

### Expected Results

- [x] User can complete signup flow
- [x] `user_agreements` table has a row with `tos_version='1.0.0'` and `privacy_version='1.0.0'`
- [x] No legal modal appears (user already accepted v1.0.0 at signup)

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 2: Terms Update - Legal Modal Appears

**Purpose:** Verify legal modal appears when ToS is updated.

### Preparation

```sql
-- Insert new ToS version (using semantic versioning: Major.Minor.Patch)
INSERT INTO public.version_log (type, version, message)
VALUES ('tos', '1.1.0', 'Updated Terms of Service - Test Update');
```

### Steps

1. [x] User is logged in from Test 1
2. [x] Kill the app completely (swipe up from app switcher)
3. [x] Relaunch the app
4. [x] Wait for app to load to Discoveries tab

### Expected Results

- [x] Legal acceptance modal appears automatically
- [x] Modal shows "Terms of Service v1.1.0"
- [x] Modal shows message "Updated Terms of Service - Test Update"
- [x] "View Full Document" link works (opens Terms URL)
- [x] Checkbox is unchecked by default
- [x] "Accept and Continue" button is disabled until checkbox is checked

### Verify Acceptance

1. [x] Check the checkbox
2. [x] Tap "Accept and Continue"
3. [x] Modal should dismiss

```sql
-- Verify acceptance recorded
SELECT * FROM public.user_agreements
WHERE user_id = '<user-id>'
ORDER BY accepted_at DESC;
```

- [x] New row exists with `tos_version='1.1.0'`

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: All happy path tests (1-17) completed successfully
```

---

## Test 3: Privacy Policy Update

**Purpose:** Verify privacy policy updates trigger the modal.

### Preparation

```sql
-- Insert new Privacy version (using semantic versioning: Major.Minor.Patch)
INSERT INTO public.version_log (type, version, message)
VALUES ('privacy', '1.1.0', 'Updated Privacy Policy - Added data processing details');
```

### Steps

1. [x] Kill and relaunch app
2. [x] Wait for Discoveries tab to load

### Expected Results

- [x] Legal modal appears
- [x] Modal shows "Privacy Policy v1.1.0"
- [x] Accept → modal dismisses

### Verify

```sql
SELECT * FROM public.user_agreements
WHERE user_id = '<user-id>'
ORDER BY accepted_at DESC;
```

- [x] New row with `privacy_version='1.1.0'`

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 4: Both ToS and Privacy Update

**Purpose:** Verify both documents can be updated and shown together.

### Preparation

```sql
-- Insert new versions for both (using semantic versioning: Major.Minor.Patch)
INSERT INTO public.version_log (type, version, message)
VALUES ('tos', '1.2.0', 'ToS v1.2.0 - Major update');

INSERT INTO public.version_log (type, version, message)
VALUES ('privacy', '1.2.0', 'Privacy v1.2.0 - GDPR compliance');
```

### Steps

1. [x] Kill and relaunch app
2. [x] Wait for modal to appear

### Expected Results

- [x] Modal shows BOTH cards (ToS v1.2.0 AND Privacy v1.2.0)
- [x] Single checkbox says "I have read and agree to the updated Terms of Service and Privacy Policy"
- [x] Accept → both are recorded

### Verify

```sql
SELECT * FROM public.user_agreements
WHERE user_id = '<user-id>'
ORDER BY accepted_at DESC LIMIT 1;
```

- [x] Row has BOTH `tos_version='1.2.0'` AND `privacy_version='1.2.0'`

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 5: Legal Modal Deferred on Camera

**Purpose:** Verify legal modal does NOT interrupt camera flow.

### Preparation

```sql
-- Add new ToS version to trigger modal (using semantic versioning)
INSERT INTO public.version_log (type, version, message)
VALUES ('tos', '1.3.0', 'ToS v1.3.0 - Camera test');
```

### Steps

1. [x] Kill and relaunch app
2. [x] IMMEDIATELY tap Camera tab before modal can appear
3. [x] Start taking a photo (camera should open)

### Expected Results

- [x] Legal modal does NOT appear while camera is active
- [x] User can complete photo capture flow
- [x] After completing/canceling photo, navigate to Discoveries tab
- [x] Legal modal SHOULD appear now

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 6: Legal Modal - Network Failure & Retry

**Purpose:** Verify retry logic when acceptance fails.

### Preparation

This test requires simulating network failure. Options:
- Enable Airplane mode right before tapping Accept
- Or test on simulator with network link conditioner

### Steps

1. [x] Trigger legal modal (add new version if needed)
2. [x] Check the checkbox
3. [x] Enable airplane mode
4. [x] Tap "Accept and Continue"
5. [x] Wait for retries (should see spinner for ~3-4 seconds)

### Expected Results

- [x] Button shows "Accepting..." with spinner
- [x] After 3 failed retries, error message appears
- [x] Error says "Network error. Please check your connection and try again."
- [x] Button re-enables for manual retry
- [x] Disable airplane mode, tap Accept again → works

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 7: Legal Modal - Sign Out

**Purpose:** Verify sign out from legal modal works correctly.

### Preparation

```sql
-- Ensure user needs to accept terms (using semantic versioning)
INSERT INTO public.version_log (type, version, message)
VALUES ('tos', '1.4.0', 'ToS v1.4.0 - Sign out test');
```

### Steps

1. [x] Kill and relaunch app
2. [x] Legal modal should appear
3. [x] Tap "Sign Out" button
4. [x] Confirmation alert should appear
5. [x] Tap "Sign Out" on alert

### Expected Results

- [x] User is signed out
- [x] Returns to authentication screen
- [x] No crash or error

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 8: Maintenance Mode

**Purpose:** Verify maintenance mode blocks app access.

### Preparation

```sql
-- Enable maintenance mode
UPDATE public.app_config
SET maintenance_mode = true,
    maintenance_message = 'Server maintenance in progress. Expected downtime: 30 minutes.';
```

### Steps

1. [x] Kill and relaunch app
2. [x] Wait for app to load

### Expected Results

- [x] Maintenance screen appears (not the normal app)
- [x] Shows wrench emoji 🔧
- [x] Shows "Under Maintenance"
- [x] Shows default message + custom message
- [x] "Check Again" button is visible

### Test Check Again Button

1. [x] Tap "Check Again"
2. [x] Should show spinner briefly
3. [x] Still shows maintenance (because it's still enabled)
4. [x] Tap "Check Again" again immediately
5. [x] Should still show spinner (rate limited but shows feedback)

### Disable Maintenance

```sql
UPDATE public.app_config SET maintenance_mode = false;
```

6. [x] Tap "Check Again"
7. [x] App should return to normal state

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 9: Maintenance Mode - Offline Cache

**Purpose:** Verify maintenance state persists if user goes offline.

### Preparation

```sql
-- Enable maintenance mode
UPDATE public.app_config
SET maintenance_mode = true,
    maintenance_message = 'Offline test maintenance';
```

### Steps

1. [x] Kill and relaunch app (with network)
2. [x] See maintenance screen (this caches the state)
3. [x] Enable airplane mode
4. [x] Kill and relaunch app

### Expected Results

- [x] Maintenance screen still appears (from cache)
- [x] "Check Again" shows spinner but can't fetch (offline)

### Test Cache Expiration

The cache expires after 3 hours. For manual testing, you'd need to:
- Wait 3 hours, OR
- Manually clear UserDefaults (requires code change or app delete)

### Reset

```sql
UPDATE public.app_config SET maintenance_mode = false;
```

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 10: Force Update - Immediate Block (min_supported_version)

**Purpose:** Verify app blocks when below minimum supported version.

### Preparation

```sql
-- Set min_supported_version higher than current app version
-- Current app version is likely 1.0.0 or similar
UPDATE public.app_config SET min_supported_version = '99.0.0';
```

### Steps

1. [x] Kill and relaunch app
2. [x] Wait for app to load

### Expected Results

- [x] Force update screen appears immediately
- [x] Shows lock emoji 🔒
- [x] Shows "Update Required"
- [x] Shows "Update Now" button
- [x] "Update Now" opens App Store URL

### Reset

To test that the blocking is removed:

```sql
UPDATE public.app_config SET min_supported_version = '1.0.0';
```

Then kill and relaunch the app - it should return to normal.

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 11: Force Update - Grace Period

**Purpose:** Verify force update with 7-day grace period.

### Preparation

```sql
-- Add a force update version
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '2.0.0', 'Critical security update - please update', 'force');
```

### Steps

1. [x] Kill and relaunch app
2. [x] Wait for app to load

### Expected Results

- [x] Grace period warning sheet appears (NOT full blocking screen)
- [x] Shows warning emoji ⚠️
- [x] Shows "Required Update"
- [x] Shows "You have X days to update..."
- [x] "Update Now" button opens App Store
- [x] "Remind Me Later" dismisses the sheet
- [x] After dismissing, app works normally

### Verify Grace Period Tracking

1. [x] Dismiss the warning
2. [x] Kill and relaunch immediately
3. [x] Warning should NOT appear again (same session)

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 12: Force Update - Grace Period Expired

**Purpose:** Verify blocking when grace period expires.

### Note

This test requires manipulating the grace period start date. Options:
1. Wait 7 days (not practical)
2. Modify code temporarily to set shorter grace period
3. Manually edit UserDefaults

For practical testing, we'll simulate by checking the blocking screen from Test 10 works correctly, and trust the grace period logic (unit testable).

### Alternative: Test immediate block alongside grace

The key difference:
- `min_supported_version` = immediate block (no grace)
- `last_force_version` = 7-day grace, then block

Test 10 verified immediate block works.

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: Tested with 2-minute grace period for faster verification
```

---

## Test 13: Soft Update Reminder

**Purpose:** Verify soft update prompts appear on schedule.

### Preparation

```sql
-- Add a soft update version
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '1.5.0', 'New features and improvements!', 'soft');
```

### Steps

1. [x] Kill and relaunch app
2. [x] Navigate to Discoveries tab
3. [x] Wait for soft update sheet to appear

### Expected Results

- [x] Soft update sheet appears (bottom sheet, not full screen)
- [x] Shows celebration emoji 🎉
- [x] Shows "New Version Available!"
- [x] Shows version and message
- [x] "Update Now" opens App Store
- [x] "Maybe Later" dismisses

### Test Dismissal

1. [x] Tap "Maybe Later"
2. [x] Sheet dismisses
3. [x] Kill and relaunch immediately
4. [x] Sheet should NOT appear again (already shown for Day 1)

### Reminder Schedule

The reminder appears at Day 1, Day 3, Day 7 then stops. For practical testing, verify Day 1 works and trust the scheduling logic.

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 14: Version Comparison - Semantic Versioning

**Purpose:** Verify version comparison handles edge cases correctly.

### Test Cases

The version comparison is in `VersionComparisonExtension.swift`. These should be unit tested, but manual verification:

```sql
-- Set min_supported to test semantic comparison
-- Test: 1.10.0 should be greater than 1.9.0
UPDATE public.app_config SET min_supported_version = '1.10.0';
```

If your app is version 1.9.0 or lower, it should be blocked.
If your app is version 1.10.0 or higher, it should NOT be blocked.

### Reset

```sql
UPDATE public.app_config SET min_supported_version = '1.0.0';
```

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 15: Sign Out Clears Compliance State

**Purpose:** Verify signing out clears compliance cached state.

### Steps

1. [x] Sign in as a user
2. [x] Navigate around the app
3. [x] Go to Settings → Sign Out
4. [x] Sign in as a different user (or same user)

### Expected Results

- [x] No lingering compliance modals from previous user
- [x] Fresh compliance check happens for new session

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 16: Offline - Fail Open

**Purpose:** Verify app works when offline (no blocking if can't fetch config).

### Preparation

Ensure no maintenance mode or blocking conditions exist:

```sql
UPDATE public.app_config
SET maintenance_mode = false,
    min_supported_version = '1.0.0';
```

### Steps

1. [x] Sign in normally (with network)
2. [x] Kill the app
3. [x] Enable airplane mode
4. [x] Relaunch app

### Expected Results

- [x] App loads normally (fail-open behavior)
- [x] No compliance checks block the user
- [x] App is usable offline

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test 17: Config Staleness Refresh

**Purpose:** Verify config refreshes when stale (> 1 hour) on foreground.

### Steps

1. [x] Sign in and use app normally
2. [x] Background the app for > 1 hour (or modify staleness threshold in code for testing)
3. [x] Return to app

### Expected Results

- [x] Config is refreshed in background
- [x] If new compliance conditions exist, they trigger appropriately

### Note

For practical testing, you can verify the refresh happens by checking logs or temporarily reducing the staleness threshold.

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Error State Tests

The following tests cover error handling, edge cases, and failure scenarios that are critical for production reliability.

### Testing Status Summary

**All Tests Complete!**

**Completed & Passed:**
- ✅ E1: Network Failure - Cold Start (PASS)
- ✅ E2: Network Failure - Terms Acceptance Retry (PASS)
- ✅ E3: Invalid Version String (PASS)
- ✅ E6: Double-Tap Accept Prevention (PASS)
- ✅ E8: Maintenance Mode Long Message (PASS)
- ✅ E11: Server 5xx Errors (PASS)
- ✅ E20: Corrupted UserDefaults (PASS - app recovers gracefully)
- ✅ E26: Force → Force (PASS - grace period doesn't reset)
- ✅ E26b: Soft → Soft (PASS - reminder cycle resets for new version)
- ✅ E26c: Force → Soft (PASS - fixed with Option C implementation)
- ✅ E26d: Soft → Force (PASS - force takes precedence)
- ✅ E27: Soft Update Reminder Cycle (PASS)

**Not Applicable / Dismissed:**
- ⚪ E4: Empty Version String (N/A - column doesn't exist)
- ⚪ E5: Grace Period Boundary (N/A - grace is user-local, not DB-based)
- ⚪ E7: Sign Out During Acceptance (N/A - behavior acceptable)
- ⚪ E9: Rapid Maintenance Toggle (N/A - not critical)
- ⚪ E10: Signup Terms Recording Failure (N/A - not critical)
- ⚪ E12: Request Timeout (N/A - not important)
- ⚪ E13-E19: Database/Version Format Issues (N/A - won't release bad data)
- ⚪ E21-E25: Cache/Clock Tests (N/A - not practical to test)
- ⚪ E28-E30: Reinstall/Race Conditions (N/A - not critical)

**Issues Fixed:**
- ✅ **Force → Soft Scenario (E26c):** Fixed by adding `last_force_message` field to `get_app_config()` RPC response and using it in `ComplianceUseCase.swift` for force grace/expired states.

---

## Test E1: Network Failure - Cold Start (Fail Open)

**Purpose:** Verify app doesn't block when network unavailable on launch.

### Preparation

Ensure no maintenance mode is cached:
```sql
UPDATE public.app_config SET maintenance_mode = false;
```

### Steps

1. [ ] Sign in normally (with network)
2. [ ] Kill the app completely
3. [ ] Enable airplane mode
4. [ ] Wait 5 seconds
5. [ ] Relaunch app

### Expected Results

- [ ] App launches without crashing
- [ ] No blocking screen appears
- [ ] User can navigate the app
- [ ] Config fetch fails silently (check Xcode console for error log)

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: App launched normally offline, no blocking
```

---

## Test E2: Network Failure - Terms Acceptance Retry

**Purpose:** Verify retry logic when acceptance fails mid-request.

### Preparation

```sql
-- Ensure user needs to accept terms
INSERT INTO public.version_log (type, version, message)
VALUES ('tos', '1.5.0', 'Error test ToS');
```

### Steps

1. [ ] Kill and relaunch app (with network)
2. [ ] Legal modal appears
3. [ ] Check the acceptance checkbox
4. [ ] Enable airplane mode
5. [ ] Tap "Accept and Continue"
6. [ ] Watch for spinner and timer

### Expected Results

- [ ] Button shows "Accepting..." spinner
- [ ] App tries 3 times over ~3-4 seconds
- [ ] After 3 failures, error message appears: "Network error. Please check your connection..."
- [ ] Button re-enables for manual retry
- [ ] No crash occurs

### Recovery Test

7. [ ] Disable airplane mode
8. [ ] Tap "Accept and Continue" again
9. [ ] Should succeed

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E3: Invalid Version String in Database

**Purpose:** Verify app handles malformed version strings gracefully.

### Preparation

```sql
-- Insert an invalid version string
UPDATE public.app_config SET min_supported_version = '1.0.invalid';
```

### Steps

1. [ ] Kill and relaunch app (current version e.g., 1.0.6)
2. [ ] Observe behavior

### Expected Results

- [ ] App does NOT crash
- [ ] App does NOT show force update blocking screen (fail-safe)
- [ ] App loads normally
- [ ] Check Xcode console for any parsing warnings

### Why This Matters

The `VersionComparisonExtension.swift` uses `compactMap { Int($0) }` which silently drops non-numeric components. This could cause:
- "1.0.invalid" → parsed as [1, 0] → treated as version 1.0.0
- Could allow user through when they should be blocked

### Cleanup

```sql
UPDATE public.app_config SET min_supported_version = '1.0.0';
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E4: Empty Version String

**Purpose:** Verify app handles empty version gracefully.

### Preparation

```sql
-- Set empty version
UPDATE public.app_config SET current_force_version = '';
```

### Steps

1. [ ] Kill and relaunch app
2. [ ] Observe behavior

### Expected Results

- [ ] No force update prompt appears
- [ ] App loads normally
- [ ] No crash

### Cleanup

```sql
-- Reset (this sets it back to the latest force version from version_log)
UPDATE public.app_config SET current_force_version = (
  SELECT version FROM public.version_log
  WHERE type = 'app' AND app_update_type = 'force'
  ORDER BY released_at DESC LIMIT 1
);
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E5: Grace Period Boundary - Exactly 7 Days

**Purpose:** Verify behavior at exact grace period expiration.

### Preparation

```sql
-- Insert force version released exactly 7 days ago
INSERT INTO public.version_log (type, version, message, app_update_type, released_at)
VALUES ('app', '3.0.0', 'Boundary test', 'force', NOW() - INTERVAL '7 days');
```

### Steps

1. [ ] Kill and relaunch app
2. [ ] Observe which screen appears

### Expected Results

At exactly 7 days:
- [ ] Should show BLOCKING screen (grace period expired), NOT the dismissible warning

### Cleanup

```sql
DELETE FROM public.version_log WHERE version = '3.0.0' AND type = 'app';
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E6: Double-Tap Accept Prevention

**Purpose:** Verify double-tap doesn't cause duplicate submissions.

### Preparation

```sql
INSERT INTO public.version_log (type, version, message)
VALUES ('tos', '1.6.0', 'Double-tap test');
```

### Steps

1. [ ] Kill and relaunch app
2. [ ] Legal modal appears
3. [ ] Check the checkbox
4. [ ] Quickly tap "Accept and Continue" twice

### Expected Results

- [ ] Only one submission occurs
- [ ] No duplicate records in `user_agreements`
- [ ] Button shows spinner/disabled state after first tap

### Verify

```sql
SELECT COUNT(*) FROM public.user_agreements
WHERE user_id = '<user-id>' AND tos_version = '1.6.0';
-- Should be exactly 1
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E7: Sign Out During Terms Acceptance

**Purpose:** Verify sign out cancels pending acceptance cleanly.

### Preparation

```sql
INSERT INTO public.version_log (type, version, message)
VALUES ('tos', '1.7.0', 'Sign out test');
```

### Steps

1. [ ] Kill and relaunch app
2. [ ] Legal modal appears
3. [ ] Check the checkbox
4. [ ] Tap "Accept and Continue"
5. [ ] IMMEDIATELY tap "Sign Out" while spinner is showing

### Expected Results

- [ ] Sign out confirmation alert appears
- [ ] Tapping "Sign Out" cancels the acceptance
- [ ] User is signed out cleanly
- [ ] No crash or hanging state

### Verify

```sql
-- Acceptance should NOT be recorded (or should be, depending on timing)
SELECT * FROM public.user_agreements WHERE tos_version = '1.7.0';
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E8: Maintenance Mode with Very Long Message

**Purpose:** Verify UI handles long maintenance messages.

### Preparation

```sql
UPDATE public.app_config
SET maintenance_mode = true,
    maintenance_message = 'This is a very long maintenance message that spans multiple lines and contains a lot of information about the maintenance. We are upgrading our servers to provide better performance. The maintenance is expected to take approximately 2 hours. Thank you for your patience. During this time, all services will be unavailable. Please try again later. We apologize for any inconvenience caused.';
```

### Steps

1. [ ] Kill and relaunch app

### Expected Results

- [ ] Maintenance screen appears
- [ ] Long message is displayed (scrollable or truncated gracefully)
- [ ] No UI overflow or cut-off text
- [ ] "Check Again" button still accessible

### Cleanup

```sql
UPDATE public.app_config SET maintenance_mode = false, maintenance_message = null;
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E9: Rapid Maintenance Toggle

**Purpose:** Verify app handles rapid state changes.

### Steps

1. [ ] App is running, showing Discoveries
2. [ ] In SQL, enable maintenance:
```sql
UPDATE public.app_config SET maintenance_mode = true;
```
3. [ ] Wait 2 seconds
4. [ ] Disable maintenance:
```sql
UPDATE public.app_config SET maintenance_mode = false;
```
5. [ ] In app, tap "Check Again" on maintenance screen (if it appeared)

### Expected Results

- [ ] App doesn't crash
- [ ] App settles on the correct final state (not maintenance)
- [ ] No stuck states

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E10: New User Signup - Terms Recording Failure

**Purpose:** Verify behavior when terms recording fails during signup.

This test requires simulating network failure at a specific moment during signup flow.

### Steps

1. [ ] Start new user signup flow
2. [ ] Complete email/password entry
3. [ ] Enable airplane mode just BEFORE tapping final signup button
4. [ ] Complete signup (Supabase auth may fail or succeed depending on caching)

### Expected Results

If signup succeeds but terms recording fails:
- [ ] User is authenticated but terms not recorded
- [ ] On next launch, legal modal should appear
- [ ] No crash occurs

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E11: Server 5xx Errors

**Purpose:** Verify app handles server errors gracefully.

### Preparation

Simulate by temporarily disabling the `get_app_config` function in Supabase dashboard, or modify it to raise an exception.

### Steps

1. [ ] Modify function to raise error:
```sql
CREATE OR REPLACE FUNCTION public.get_app_config()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RAISE EXCEPTION 'Simulated server error';
END;
$$;
```
2. [ ] Kill and relaunch app

### Expected Results

- [ ] App launches without crashing
- [ ] Falls back gracefully (fail-open behavior)
- [ ] User can still use app

### Cleanup

Restore the original `get_app_config()` function from migration file.

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E12: Request Timeout

**Purpose:** Verify app doesn't freeze on slow/hanging network.

### Preparation

Use Network Link Conditioner to simulate very slow network (e.g., 1% packet loss, 10000ms delay).

### Steps

1. [ ] Enable Network Link Conditioner with extreme delays
2. [ ] Kill and relaunch app
3. [ ] Observe behavior

### Expected Results

- [ ] App should timeout gracefully (not freeze indefinitely)
- [ ] User sees app load or error, not infinite spinner
- [ ] App remains responsive

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E13: Pre-release Version String (1.0.0-beta)

**Purpose:** Verify handling of pre-release version suffixes.

### Preparation

```sql
UPDATE public.app_config SET min_supported_version = '1.0.0-beta';
```

### Steps

1. [ ] Kill and relaunch app with version 1.0.6

### Expected Results

- [ ] App handles gracefully (comparison may ignore suffix or fail safely)
- [ ] No crash

### Cleanup

```sql
UPDATE public.app_config SET min_supported_version = '1.0.0';
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E14: Extra Version Components (1.0.0.0)

**Purpose:** Verify handling of 4-component versions.

### Preparation

```sql
UPDATE public.app_config SET min_supported_version = '1.0.0.0';
```

### Steps

1. [ ] Kill and relaunch app

### Expected Results

- [ ] Version comparison handles gracefully
- [ ] No crash
- [ ] Correct comparison result (should treat as 1.0.0)

### Cleanup

```sql
UPDATE public.app_config SET min_supported_version = '1.0.0';
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E15: Version with Whitespace

**Purpose:** Verify trimming/handling of versions with spaces.

### Preparation

```sql
UPDATE public.app_config SET min_supported_version = ' 1.0.0 ';
```

### Steps

1. [ ] Kill and relaunch app

### Expected Results

- [ ] App handles gracefully (trims whitespace or fails safely)
- [ ] No crash

### Cleanup

```sql
UPDATE public.app_config SET min_supported_version = '1.0.0';
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E16: Missing app_config Row

**Purpose:** Verify handling when app_config table is empty.

### Preparation

```sql
-- Backup current config
CREATE TEMP TABLE app_config_backup AS SELECT * FROM public.app_config;

-- Delete config row
DELETE FROM public.app_config;
```

### Steps

1. [ ] Kill and relaunch app

### Expected Results

- [ ] RPC function should raise exception
- [ ] Client should fail-open (not block user)
- [ ] App loads, check Xcode console for error

### Cleanup

```sql
INSERT INTO public.app_config SELECT * FROM app_config_backup;
DROP TABLE app_config_backup;
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E17: NULL Version Fields

**Purpose:** Verify handling of NULL version fields.

### Preparation

```sql
-- Try to set ToS version to NULL in version_log
UPDATE public.version_log SET version = NULL WHERE type = 'tos';
```

Note: This may fail due to NOT NULL constraint, which is correct. If it fails, test passes.

### Expected Results

- [ ] Database rejects NULL (constraint violation) - this is correct
- [ ] If somehow NULL gets through, app should handle gracefully

### Cleanup

```sql
-- Restore if needed
UPDATE public.version_log SET version = '1.0.0' WHERE type = 'tos' AND version IS NULL;
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E18: Version Not in version_log

**Purpose:** Verify handling when referenced version doesn't exist.

### Preparation

```sql
-- Delete all ToS versions temporarily
DELETE FROM public.version_log WHERE type = 'tos';
```

### Steps

1. [ ] Kill and relaunch app

### Expected Results

- [ ] App handles gracefully
- [ ] No crash
- [ ] May show error or skip ToS check

### Cleanup

```sql
INSERT INTO public.version_log (type, version, message)
VALUES ('tos', '1.0.0', 'Initial Terms of Service');
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E19: Malformed Date in Grace Period

**Purpose:** Verify handling of corrupted date fields.

### Preparation

This test is difficult to execute as PostgreSQL enforces TIMESTAMPTZ type. If you manually corrupt the date via raw SQL, the database will reject it.

### Expected Results

- [ ] Database type safety prevents malformed dates
- [ ] Test likely N/A due to type enforcement

### Notes
```
Result: [ ] PASS  [ ] FAIL  [ ] N/A
Notes: _______________________________________________
```

---

## Test E20: Corrupted UserDefaults

**Purpose:** Verify app handles corrupted compliance state in UserDefaults.

### Preparation

Use Xcode debugger or manually edit app's UserDefaults file to insert invalid JSON for compliance keys.

### Steps

1. [ ] Pause app in debugger
2. [ ] Set invalid data: `UserDefaults.standard.set("invalid-json", forKey: "app_update_reminder_state")`
3. [ ] Resume and relaunch app

### Expected Results

- [ ] App doesn't crash
- [ ] Resets to clean state
- [ ] Logs warning about corrupted data

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E21: Stale Cache After Terms Accept

**Purpose:** Verify cache invalidates after accepting terms.

### Preparation

```sql
INSERT INTO public.version_log (type, version, message)
VALUES ('tos', '1.8.0', 'Cache invalidation test');
```

### Steps

1. [ ] Kill and relaunch app
2. [ ] Legal modal appears
3. [ ] Accept terms
4. [ ] Immediately check if config refresh happened

### Expected Results

- [ ] Modal dismisses
- [ ] Config is refreshed (check logs)
- [ ] User status updated

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E22: App Crash During Acceptance

**Purpose:** Verify state is recoverable if app crashes mid-acceptance.

### Steps

1. [ ] Trigger legal modal
2. [ ] Tap Accept
3. [ ] Force quit app IMMEDIATELY (during spinner)
4. [ ] Relaunch app

### Expected Results

- [ ] App relaunches normally
- [ ] If acceptance succeeded, modal doesn't reappear
- [ ] If acceptance failed, modal reappears (can retry)
- [ ] No stuck state

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E23: Offline Maintenance Cache Expiration

**Purpose:** Verify maintenance cache expires after 3 hours offline.

### Preparation

```sql
UPDATE public.app_config SET maintenance_mode = true, maintenance_message = 'Cache expiry test';
```

### Steps

1. [ ] Launch app (with network) - sees maintenance
2. [ ] Enable airplane mode
3. [ ] Kill and relaunch - should still see maintenance (cached)
4. [ ] Wait 3+ hours (or manually adjust device clock forward 3+ hours)
5. [ ] Kill and relaunch

### Expected Results

- [ ] After 3+ hours, cache expires
- [ ] App unblocks (fail-open when cache expired and offline)

### Cleanup

```sql
UPDATE public.app_config SET maintenance_mode = false, maintenance_message = null;
```

### Notes
```
Result: [ ] PASS  [ ] FAIL  [ ] N/A (requires 3+ hour wait)
Notes: _______________________________________________
```

---

## Test E24: Device Clock in Future

**Purpose:** Verify grace period uses server time, not device time.

### Preparation

```sql
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '4.0.0', 'Clock test', 'force');
```

### Steps

1. [ ] Launch app normally (force update grace prompt appears)
2. [ ] Dismiss prompt
3. [ ] Change device date to 7+ days in future
4. [ ] Kill and relaunch app

### Expected Results

- [ ] Should still show grace prompt (not blocking)
- [ ] Grace period based on server time, not device
- [ ] Or: May show blocking if client uses device time (implementation detail)

### Cleanup

Reset device clock to automatic.

```sql
DELETE FROM public.version_log WHERE version = '4.0.0' AND type = 'app';
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E25: Device Clock in Past

**Purpose:** Verify app works with device clock set to past.

### Steps

1. [ ] Set device clock to 1 year ago
2. [ ] Kill and relaunch app

### Expected Results

- [ ] App loads normally
- [ ] No time-based blocking issues
- [ ] Grace periods still work correctly

### Cleanup

Reset device clock to automatic.

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E26: Multiple Force Versions in Grace Period

**Purpose:** Verify behavior when multiple force updates released within 7 days.

### Preparation

```sql
-- Insert first force version
INSERT INTO public.version_log (type, version, message, app_update_type, released_at)
VALUES ('app', '5.0.0', 'First force', 'force', NOW() - INTERVAL '2 days');

-- Insert second force version
INSERT INTO public.version_log (type, version, message, app_update_type, released_at)
VALUES ('app', '5.1.0', 'Second force', 'force', NOW());
```

### Steps

1. [ ] Kill and relaunch app (version 1.0.6)

### Expected Results

- [ ] Shows latest force version (5.1.0)
- [ ] Grace period does NOT reset
- [ ] User still has time from first force version seen

### Cleanup

```sql
DELETE FROM public.version_log WHERE version IN ('5.0.0', '5.1.0') AND type = 'app';
```

### Notes
```
Result: [x] PASS  [ ] FAIL
Notes: Grace period did not reset when second force version released
```

---

## Test E26b: Soft → Soft (Multiple Soft Releases)

**Purpose:** Verify reminder cycle resets for each new soft version.

### Preparation

```sql
-- Clean up app versions first
DELETE FROM public.version_log WHERE type = 'app' AND version NOT IN ('1.0.0');

-- Insert first soft update
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '1.7.0', 'First soft update', 'soft');
```

### Steps

1. [ ] Reinstall app to clear UserDefaults
2. [ ] Launch app (version 1.0.6)
3. [ ] Soft update sheet appears for 1.7.0
4. [ ] Tap "Maybe Later" (dismiss)
5. [ ] Insert second soft update:
```sql
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '1.8.0', 'Second soft update', 'soft');
```
6. [ ] Kill and relaunch app

### Expected Results

- [ ] Soft update sheet appears again for 1.8.0 (new version)
- [ ] Reminder cycle resets (Day 1 for 1.8.0)
- [ ] Shows "1.8.0" and "Second soft update" message

### Cleanup

```sql
DELETE FROM public.version_log WHERE version IN ('1.7.0', '1.8.0') AND type = 'app';
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E26c: Force → Soft (Force Then Soft Release)

**Purpose:** Verify force grace warning persists when soft update is released after.

### Preparation

```sql
-- Clean up app versions first
DELETE FROM public.version_log WHERE type = 'app' AND version NOT IN ('1.0.0');

-- Insert force update
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '2.0.0', 'Critical security fix - FORCE', 'force');
```

### Steps

1. [ ] Reinstall app to clear UserDefaults
2. [ ] Launch app (version 1.0.6)
3. [ ] Force grace warning appears for 2.0.0
4. [ ] Tap "Remind Me Later" (dismiss)
5. [ ] Insert soft update:
```sql
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '2.1.0', 'Nice new features - SOFT', 'soft');
```
6. [ ] Kill and relaunch app

### Expected Results

- [ ] Force grace warning still appears (NOT soft update sheet)
- [ ] Shows latest version 2.1.0 (what user will get from App Store)
- [ ] **KNOWN ISSUE:** Currently shows soft message instead of force message
- [ ] **Expected fix:** Should show force message "Critical security fix"

### Cleanup

```sql
DELETE FROM public.version_log WHERE version IN ('2.0.0', '2.1.0') AND type = 'app';
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: Force screen appears but shows soft message - needs fix (Option C)
```

---

## Test E26d: Soft → Force (Soft Then Force Release)

**Purpose:** Verify app switches from soft reminder to force grace warning when force update released.

### Preparation

```sql
-- Clean up app versions first
DELETE FROM public.version_log WHERE type = 'app' AND version NOT IN ('1.0.0');

-- Insert soft update first
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '1.7.0', 'Nice new features - SOFT', 'soft');
```

### Steps

1. [ ] Reinstall app to clear UserDefaults
2. [ ] Launch app (version 1.0.6)
3. [ ] Soft update sheet appears for 1.7.0
4. [ ] Tap "Maybe Later" (dismiss)
5. [ ] Insert force update:
```sql
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '2.0.0', 'Critical security fix - FORCE', 'force');
```
6. [ ] Kill and relaunch app

### Expected Results

- [ ] Force grace warning appears (NOT soft update sheet)
- [ ] Shows version 2.0.0 with "Critical security fix" message
- [ ] Higher priority (force) takes precedence over soft reminder
- [ ] Grace period countdown starts fresh

### Cleanup

```sql
DELETE FROM public.version_log WHERE version IN ('1.7.0', '2.0.0') AND type = 'app';
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E27: Soft Update - Dismiss Day 1, Reopen Day 8

**Purpose:** Verify soft update reminder cycle behavior.

### Preparation

```sql
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '1.9.0', 'Soft reminder test', 'soft');
```

### Steps

1. [ ] Launch app - Day 1 reminder appears
2. [ ] Dismiss ("Maybe Later")
3. [ ] Simulate time passing 8 days (requires manual clock adjustment or code modification)
4. [ ] Relaunch app

### Expected Results

- [ ] Should show Day 7 reminder (last in cycle)
- [ ] After Day 7 dismiss, should not show again

### Cleanup

```sql
DELETE FROM public.version_log WHERE version = '1.9.0' AND type = 'app';
```

### Notes
```
Result: [ ] PASS  [ ] FAIL  [ ] N/A (requires time manipulation)
Notes: _______________________________________________
```

---

## Test E28: App Reinstall Mid Soft Update Cycle

**Purpose:** Verify reminder state resets on reinstall.

### Preparation

```sql
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '2.0.0', 'Reinstall test', 'soft');
```

### Steps

1. [ ] Launch app - see Day 1 reminder, dismiss
2. [ ] Delete app completely
3. [ ] Reinstall app
4. [ ] Sign in

### Expected Results

- [ ] Reminder state resets (UserDefaults cleared)
- [ ] Shows Day 1 reminder again

### Cleanup

```sql
DELETE FROM public.version_log WHERE version = '2.0.0' AND type = 'app';
```

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E29: Accept Terms While Config Refreshing

**Purpose:** Verify no race condition when accepting during background refresh.

### Preparation

```sql
INSERT INTO public.version_log (type, version, message)
VALUES ('tos', '1.9.0', 'Race condition test');
```

### Steps

1. [ ] Launch app - legal modal appears
2. [ ] Trigger a background config refresh (bring app to background then foreground after 1+ hour, or manually)
3. [ ] While refresh is happening, tap Accept

### Expected Results

- [ ] Acceptance succeeds
- [ ] No conflict or crash
- [ ] Modal dismisses correctly

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Test E30: Sign Out with Pending Legal Modal

**Purpose:** Verify sign out clears pending modal state.

### Preparation

```sql
INSERT INTO public.version_log (type, version, message)
VALUES ('tos', '2.0.0', 'Sign out pending test');
```

### Steps

1. [ ] Launch app - legal modal appears
2. [ ] Tap "Sign Out" (don't accept)
3. [ ] Confirm sign out
4. [ ] Sign back in

### Expected Results

- [ ] Modal dismisses on sign out
- [ ] State clears
- [ ] On sign in, modal appears again (user still needs to accept)

### Notes
```
Result: [ ] PASS  [ ] FAIL
Notes: _______________________________________________
```

---

## Error Tests Verification

After running error tests, verify:
1. [ ] No crashes occurred (check Xcode console)
2. [ ] Error messages are user-friendly
3. [ ] App recovers gracefully from all error states
4. [ ] Data integrity is maintained (no orphaned records)
5. [ ] State is consistent after errors (sign out, sign in cycle)

---

## Critical Files to Watch During Testing

| File | What to Monitor |
|------|-----------------|
| `SupabaseAppConfigRepository.swift` | Network error logging |
| `ComplianceUseCase.swift` | Version comparison results |
| `AppRootViewModel.swift` | State transitions |
| `VersionComparisonExtension.swift` | Parsing of malformed versions |
| `LegalAcceptanceModalView.swift` | Retry count, error display |

---

## Final Cleanup

After all testing, reset the database:

```sql
-- Reset version log (all versions use semantic versioning: Major.Minor.Patch)
DELETE FROM public.version_log;
INSERT INTO public.version_log (type, version, message) VALUES
  ('tos', '1.0.0', 'Initial Terms of Service'),
  ('privacy', '1.0.0', 'Initial Privacy Policy'),
  ('app', '1.0.0', 'Initial release');

-- Reset app config
UPDATE public.app_config SET
  min_supported_version = '1.0.0',
  maintenance_mode = false,
  maintenance_message = null;

-- Optionally clear test user agreements
-- DELETE FROM public.user_agreements;
```

---

## Summary

### Happy Path Tests

| Test | Description | Priority | Result |
|------|-------------|----------|--------|
| 1 | New User Signup | HIGH | ✅ PASS |
| 2 | ToS Update Modal | HIGH | ✅ PASS |
| 3 | Privacy Update Modal | HIGH | ✅ PASS |
| 4 | Both ToS + Privacy Update | HIGH | ✅ PASS |
| 5 | Modal Deferred on Camera | MEDIUM | ✅ PASS |
| 6 | Network Failure Retry | HIGH | ✅ PASS |
| 7 | Sign Out from Modal | MEDIUM | ✅ PASS |
| 8 | Maintenance Mode | HIGH | ✅ PASS |
| 9 | Maintenance Offline Cache | MEDIUM | ✅ PASS |
| 10 | Force Update Immediate | HIGH | ✅ PASS |
| 11 | Force Update Grace Period | HIGH | ✅ PASS |
| 12 | Force Update Grace Expired | MEDIUM | ✅ PASS |
| 13 | Soft Update Reminder | MEDIUM | ✅ PASS |
| 14 | Semantic Version Compare | HIGH | ✅ PASS |
| 15 | Sign Out Clears State | MEDIUM | ✅ PASS |
| 16 | Offline Fail Open | HIGH | ✅ PASS |
| 17 | Config Staleness Refresh | LOW | ✅ PASS |

### Error State Tests

| Test | Description | Priority | Result |
|------|-------------|----------|--------|
| E1 | Network Failure - Cold Start (Fail Open) | HIGH | ✅ PASS |
| E2 | Network Failure - Terms Acceptance Retry | HIGH | ✅ PASS |
| E3 | Invalid Version String in Database | HIGH | ✅ PASS |
| E4 | Empty Version String | HIGH | ⚪ N/A |
| E5 | Grace Period Boundary - Exactly 7 Days | MEDIUM | ⚪ N/A |
| E6 | Double-Tap Accept Prevention | MEDIUM | ✅ PASS |
| E7 | Sign Out During Terms Acceptance | MEDIUM | ⚪ N/A |
| E8 | Maintenance Mode with Very Long Message | LOW | ✅ PASS |
| E9 | Rapid Maintenance Toggle | LOW | ⚪ N/A |
| E10 | New User Signup - Terms Recording Failure | MEDIUM | ⚪ N/A |
| E11 | Server 5xx Errors | HIGH | ✅ PASS |
| E12 | Request Timeout | HIGH | ⚪ N/A |
| E13 | Pre-release Version String (1.0.0-beta) | MEDIUM | ⚪ N/A |
| E14 | Extra Version Components (1.0.0.0) | MEDIUM | ⚪ N/A |
| E15 | Version with Whitespace | MEDIUM | ⚪ N/A |
| E16 | Missing app_config Row | MEDIUM | ⚪ N/A |
| E17 | NULL Version Fields | LOW | ⚪ N/A |
| E18 | Version Not in version_log | MEDIUM | ⚪ N/A |
| E19 | Malformed Date in Grace Period | LOW | ⚪ N/A |
| E20 | Corrupted UserDefaults | MEDIUM | ✅ PASS |
| E21 | Stale Cache After Terms Accept | MEDIUM | ⚪ N/A |
| E22 | App Crash During Acceptance | MEDIUM | ⚪ N/A |
| E23 | Offline Maintenance Cache Expiration | LOW | ⚪ N/A |
| E24 | Device Clock in Future | MEDIUM | ⚪ N/A |
| E25 | Device Clock in Past | MEDIUM | ⚪ N/A |
| E26 | Force → Force (Multiple Force Versions) | MEDIUM | ✅ PASS |
| E26b | Soft → Soft (Multiple Soft Releases) | MEDIUM | ✅ PASS |
| E26c | Force → Soft (Force Then Soft) | MEDIUM | ✅ PASS (fixed) |
| E26d | Soft → Force (Soft Then Force) | MEDIUM | ✅ PASS |
| E27 | Soft Update - Dismiss Day 1, Reopen Day 8 | LOW | ✅ PASS |
| E28 | App Reinstall Mid Soft Update Cycle | LOW | ⚪ N/A |
| E29 | Accept Terms While Config Refreshing | MEDIUM | ⚪ N/A |
| E30 | Sign Out with Pending Legal Modal | MEDIUM | ⚪ N/A |

---

## Issues Found

Document any issues discovered during testing:

```
Issue #1:
Description: _______________________________________________
Steps to reproduce: ________________________________________
Severity: [ ] Critical  [ ] High  [ ] Medium  [ ] Low

Issue #2:
Description: _______________________________________________
Steps to reproduce: ________________________________________
Severity: [ ] Critical  [ ] High  [ ] Medium  [ ] Low
```
