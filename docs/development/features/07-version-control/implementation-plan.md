# Implementation Plan: Version Control & Compliance System

## Overview

This system tracks and enforces user acceptance of:
- **Terms of Service (ToS)** — explicit checkbox required
- **Privacy Policy** — explicit checkbox required  
- **App Version** — soft reminders stored locally

### Design Principles

1. **Explicit acceptance for legal documents** — user must tick checkbox to continue
2. **Version log architecture** — each release is a new row, full history preserved
3. **User agreements as audit log** — each acceptance is a new row, full history preserved
4. **Safe-to-present checks** — only show modals on "safe" screens (Discoveries, Audio Guides) to avoid interrupting critical flows
5. **Local storage for app update reminders** — no server round-trip needed
6. **Force update vs. Deprecation** — support both "grace period" updates and "immediate block" for unsupported versions
7. **Graceful offline handling** — if offline, use cached config or skip checks
8. **Silent retry on failures** — user should not be asked to retry; system handles it
9. **Pre-computed compliance status** — server tells client what's needed, not just versions
10. **Client-side caching** — config cached for 24 hours to reduce unnecessary network calls

---

## Database Schema

### `version_log` Table

A log of all version releases (ToS, Privacy, App). Each release creates a new row.

```sql
CREATE TYPE version_type AS ENUM ('tos', 'privacy', 'app');
CREATE TYPE update_type AS ENUM ('soft', 'force');

CREATE TABLE public.version_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- What type of version is this?
  type version_type NOT NULL,
  
  -- Version identifier (e.g., "1.0", "1.1", "2.0.3")
  version TEXT NOT NULL,
  
  -- Optional message to show users about what changed
  message TEXT,
  
  -- For app versions only: update behavior
  -- 'soft' = reminder prompts at 1/3/7 days
  -- 'force' = 7-day grace period, then blocking
  app_update_type update_type DEFAULT 'soft',

  -- For app versions: The minimum version that is still supported
  -- e.g. If current is 1.5.0, and min_supported is 1.2.0, anyone on 1.1.0 is blocked immediately
  min_supported_version TEXT,
  
  -- When this version was released
  released_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for efficient latest-version queries
CREATE INDEX idx_version_log_type_released 
  ON public.version_log(type, released_at DESC);

-- RLS: Public read, admin-only write via service_role
ALTER TABLE public.version_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read version log" ON public.version_log
  FOR SELECT USING (true);
```

**Query for latest versions:**
```sql
SELECT DISTINCT ON (type) *
FROM public.version_log
ORDER BY type, released_at DESC;
```

---

### `user_agreements` Table (Audit Log)

A log of all user acceptances. **Each acceptance creates a new row** for audit trail.

```sql
CREATE TABLE public.user_agreements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Which version was accepted
  tos_version TEXT,      -- Non-null if accepting ToS
  privacy_version TEXT,  -- Non-null if accepting Privacy
  
  -- When this acceptance was recorded
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for efficient lookup of user's latest acceptances
CREATE INDEX idx_user_agreements_user_accepted 
  ON public.user_agreements(user_id, accepted_at DESC);

ALTER TABLE public.user_agreements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own agreements" ON public.user_agreements
  FOR SELECT USING (auth.uid() = user_id);

-- Note: No direct INSERT policy - we use a database function instead
```

---

### `app_config` Table (Global Settings)

A singleton table (one row only) for global configuration that isn't strictly "version history".

```sql
CREATE TABLE public.app_config (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1), -- Enforce singleton
  
  -- Minimum app version supported (e.g. "1.2.0")
  -- Clients below this are FORCE BLOCKED immediately
  min_supported_version TEXT NOT NULL DEFAULT '0.0.0',
  
  -- Maintenance mode: blocks all app usage when TRUE
  maintenance_mode BOOLEAN DEFAULT FALSE,
  
  -- Optional message to display during maintenance
  -- If NULL, app shows default: "We are currently undergoing maintenance. Please check back later."
  -- If set, app shows: "[default text]\n\n[this message]"
  maintenance_message TEXT,
  
  -- Dynamic links
  app_store_url TEXT NOT NULL DEFAULT 'https://apps.apple.com/app/id...',
  
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS: Public read-only
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read app_config" ON public.app_config FOR SELECT USING (true);

-- Initial Seed
INSERT INTO public.app_config (min_supported_version) VALUES ('1.0.0');
```

---

### Initial Data Seed

```sql
INSERT INTO public.version_log (type, version, message) VALUES
  ('tos', '1.0', 'Initial Terms of Service'),
  ('privacy', '1.0', 'Initial Privacy Policy'),
  ('app', '1.0.0', 'Initial release');
```

---

### Existing User Backfill (One-Time Migration)

At feature deployment, all existing users need acceptance records for v1.0 (they agreed at signup):

```sql
-- Run once at feature deployment
INSERT INTO public.user_agreements (user_id, tos_version, privacy_version, accepted_at)
SELECT id, '1.0', '1.0', created_at
FROM auth.users
WHERE id NOT IN (SELECT DISTINCT user_id FROM public.user_agreements);
```

> [!IMPORTANT]
> This must be run after creating the tables but before the iOS app is updated to use this feature.

---

## Database Functions

> [!NOTE]
> We use **Postgres database functions** (not Edge Functions) for simplicity, no cold starts, and direct access to `auth.uid()`.

### `get_app_config()`

Returns the latest version requirements with pre-computed compliance flags.

```sql
CREATE OR REPLACE FUNCTION public.get_app_config()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
  current_user_id UUID := auth.uid();
  
  -- Latest versions from version_log
  latest_tos_version TEXT;
  latest_privacy_version TEXT;
  
  -- User's accepted versions
  user_tos_version TEXT;
  user_privacy_version TEXT;
BEGIN
  -- Get latest ToS version
  SELECT version INTO latest_tos_version 
  FROM public.version_log 
  WHERE type = 'tos' 
  ORDER BY released_at DESC LIMIT 1;
  
  -- Get latest Privacy version
  SELECT version INTO latest_privacy_version 
  FROM public.version_log 
  WHERE type = 'privacy' 
  ORDER BY released_at DESC LIMIT 1;
  
  -- If authenticated, get user's accepted versions
  IF current_user_id IS NOT NULL THEN
    SELECT tos_version INTO user_tos_version 
    FROM public.user_agreements 
    WHERE user_id = current_user_id AND tos_version IS NOT NULL 
    ORDER BY accepted_at DESC LIMIT 1;
    
    WHERE user_id = current_user_id AND privacy_version IS NOT NULL 
    ORDER BY accepted_at DESC LIMIT 1;
  END IF;
  
  -- Build response
  SELECT json_build_object(
    'maintenance', (
      SELECT json_build_object(
        'enabled', c.maintenance_mode,
        'message', c.maintenance_message
      ) FROM public.app_config c
    ),
    'tos', (
      SELECT json_build_object(
        'version', version,
        'message', message,
        'released_at', released_at
      ) FROM public.version_log WHERE type = 'tos' ORDER BY released_at DESC LIMIT 1
    ),
    'privacy', (
      SELECT json_build_object(
        'version', version,
        'message', message,
        'released_at', released_at
      ) FROM public.version_log WHERE type = 'privacy' ORDER BY released_at DESC LIMIT 1
    ),
    'app', (
      SELECT json_build_object(
        'version', v.version,
        'message', v.message,
        'released_at', v.released_at,
        'app_update_type', v.app_update_type,
        'min_supported_version', c.min_supported_version,
        'app_store_url', c.app_store_url
      ) 
      FROM public.version_log v, public.app_config c
      WHERE v.type = 'app' 
      ORDER BY v.released_at DESC LIMIT 1
    ),
    'user_status', CASE 
      WHEN current_user_id IS NOT NULL THEN json_build_object(
        'needs_tos_acceptance', (user_tos_version IS NULL OR user_tos_version < latest_tos_version),
        'needs_privacy_acceptance', (user_privacy_version IS NULL OR user_privacy_version < latest_privacy_version),
        'accepted_tos_version', user_tos_version,
        'accepted_privacy_version', user_privacy_version
      )
      ELSE NULL 
    END
  ) INTO result;
  
  RETURN result;
END;
$$;

-- Grant execute to authenticated and anon users
GRANT EXECUTE ON FUNCTION public.get_app_config() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_config() TO anon;
```

**Called from iOS via:**
```swift
let response = try await supabase.rpc("get_app_config").execute()
```

---

### `accept_terms()`

Records user acceptance. **Validates that user is accepting the LATEST version** — cannot submit arbitrary versions.

```sql
CREATE OR REPLACE FUNCTION public.accept_terms(
  tos_version TEXT DEFAULT NULL,
  privacy_version TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  latest_tos_version TEXT;
  latest_privacy_version TEXT;
  tos_to_insert TEXT := NULL;
  privacy_to_insert TEXT := NULL;
BEGIN
  -- Must be authenticated
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  
  -- Must accept at least one
  IF tos_version IS NULL AND privacy_version IS NULL THEN
    RAISE EXCEPTION 'Must accept at least one version';
  END IF;
  
  -- Get latest versions from version_log (source of truth)
  IF tos_version IS NOT NULL THEN
    SELECT version INTO latest_tos_version 
    FROM public.version_log 
    WHERE type = 'tos' 
    ORDER BY released_at DESC LIMIT 1;
    
    IF latest_tos_version IS NULL THEN
      RAISE EXCEPTION 'No ToS version found in version_log';
    END IF;

    -- VALIDATION: Ensure user is accepting the LATEST version
    IF tos_version != latest_tos_version THEN
      RAISE EXCEPTION 'Version mismatch: You are trying to accept ToS % but latest is %', tos_version, latest_tos_version;
    END IF;
    
    tos_to_insert := latest_tos_version;
  END IF;
  
  IF privacy_version IS NOT NULL THEN
    SELECT version INTO latest_privacy_version 
    FROM public.version_log 
    WHERE type = 'privacy' 
    ORDER BY released_at DESC LIMIT 1;
    
    IF latest_privacy_version IS NULL THEN
      RAISE EXCEPTION 'No Privacy Policy version found in version_log';
    END IF;

    -- VALIDATION: Ensure user is accepting the LATEST version
    IF privacy_version != latest_privacy_version THEN
      RAISE EXCEPTION 'Version mismatch: You are trying to accept Privacy % but latest is %', privacy_version, latest_privacy_version;
    END IF;
    
    privacy_to_insert := latest_privacy_version;
  END IF;
  
  -- Insert acceptance record
  INSERT INTO public.user_agreements (user_id, tos_version, privacy_version)
  VALUES (current_user_id, tos_to_insert, privacy_to_insert);
  
  RETURN json_build_object(
    'success', true,
    'accepted_tos_version', tos_to_insert,
    'accepted_privacy_version', privacy_to_insert
  );
END;
$$;

-- Grant execute to authenticated users only
GRANT EXECUTE ON FUNCTION public.accept_terms(TEXT, TEXT) TO authenticated;
```

**Key Security Features:**
- User MUST send the `version` string they saw (e.g. "1.0")
- Function compares strict equality with `latest_version`
- **Race Condition Prevention**: If a new version deployed while user was reading, the accept call FAILS. Client must catch this error, fetch new config, and reshow the modal.
- Only authenticated users can call this function

**Called from iOS via:**
```swift
let response = try await supabase.rpc("accept_terms", params: [
    "tos_version": "1.0",
    "privacy_version": "1.0"
]).execute()
```

---

## Client-Side Caching (24 Hours)

The app caches the config response locally to avoid unnecessary network calls.

### Cached Config Structure

```swift
struct CachedAppConfig: Codable {
    let config: AppConfigResponse   // The actual config data
    let fetchedAt: Date             // When we fetched it
    
    var isValid: Bool {
        let cacheLifetime: TimeInterval = 24 * 60 * 60  // 24 hours
        return Date().timeIntervalSince(fetchedAt) < cacheLifetime
    }
}
```

### Cache Logic on App Launch

```
App Launch
    ↓
Check for pending acceptance (from previous failed attempt)
    ↓
If pending → Submit it first, then continue
    ↓
Check cached config in UserDefaults
    ↓
┌─────────────────────────────────────────────────────────┐
│ If cache exists AND is < 24 hours old:                  │
│   → Use cached config                                   │
│   → Skip network call                                   │
├─────────────────────────────────────────────────────────┤
│ If cache expired OR doesn't exist:                      │
│   → Fetch fresh config from database                    │
│   → On success: Update cache, use fresh data            │
│   → On failure: Use expired cache if available          │
│   → On failure + no cache: Proceed without checking     │
└─────────────────────────────────────────────────────────┘
    ↓
Compare versions / check user_status flags
    ↓
Show modal if needed
```

### Cache Keys (UserDefaults)

| Key | Type | Purpose |
|-----|------|---------|
| `cached_app_config` | `CachedAppConfig` | Cached config response |
| `pending_acceptance` | `PendingAcceptance` | Failed acceptance waiting to retry |
| `app_update_reminder_state` | `AppUpdateReminderState` | Soft/force update reminder tracking |

---

## Error Handling

### Config Fetch Failures

| Scenario | Behavior |
|----------|----------|
| Cache valid (< 24h) | Use cache — no network call at all |
| Cache expired + fetch succeeds | Update cache, use fresh |
| Cache expired + fetch fails | **Use expired cache anyway** |
| No cache + fetch fails | Proceed without checking |

No special retry logic needed — caching handles most scenarios.

### Terms Acceptance Failures

| Scenario | Behavior |
|----------|----------|
| User taps Accept | Store `PendingAcceptance` immediately, dismiss modal |
| **User taps Sign Out** | **Clear auth session and return to login screen** |
| Background retry | Exponential backoff: **5 retries over 15 minutes** |
| All retries fail | `PendingAcceptance` stays in UserDefaults |
| Next launch | Check for pending, submit before fetching config |

**Exponential Backoff Timing (5 retries over ~15 min):**

| Retry | Delay After Previous | Total Time Elapsed |
|-------|---------------------|-------------------|
| 1 | 30s | 0:30 |
| 2 | 60s | 1:30 |
| 3 | 120s | 3:30 |
| 4 | 240s | 7:30 |
| 5 | 480s | 15:30 |

**Pending Acceptance Structure:**
```swift
struct PendingAcceptance: Codable {
    let acceptTosVersion: String?
    let acceptPrivacyVersion: String?
    let attemptedAt: Date
}
```


### App Store Link Failures

| Scenario | Behavior |
|----------|----------|
| `UIApplication.open` fails | Show alert with copyable App Store URL |
| Alert message | "Unable to open App Store. Copy this link to update: [URL]" |

### Version Mismatch (Race Condition)

| Scenario | Behavior |
|----------|----------|
| `accept_terms` throws "Version mismatch" | Indicates new version deployed while user was viewing |
| Action | Catch error -> Fetch new config -> Show new modal |
| User Experience | "The Terms have been updated again. Please review the latest version." |

---

## Forced Error States for Testing

> [!IMPORTANT]
> Development builds must include debug controls to force these error states:

- [ ] Force `get_app_config` to fail
- [ ] Force `get_app_config` to timeout
- [ ] Force `accept_terms` to fail  
- [ ] Force `accept_terms` to timeout
- [ ] Force App Store URL to fail to open
- [ ] Force cache to be expired/missing
- [ ] Force network offline state

These should be toggleable via a debug menu or environment flags.

---

## iOS Application Changes

### Non-Blocking Load Flow

```
┌─────────────────────────────────────────────────────────┐
│ App Launch                                              │
│     ↓                                                   │
│ Check for PendingAcceptance → Submit if exists          │
│     ↓                                                   │
│ Load main app normally (non-blocking)                   │
│     ↓                                                   │
│ In background: Check cache or fetch config              │
│     ↓                                                   │
│ Check user_status.needs_tos/privacy_acceptance          │
│     ↓                                                   │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ If needs acceptance:                                │ │
│ │   → Show modal with checkbox                        │ │
│ │   → User MUST accept to continue                    │ │
│ │   → Store PendingAcceptance immediately             │ │
│ │   → Dismiss modal immediately                       │ │
│ │   → Background: Call accept_terms with retries      │ │
│ └─────────────────────────────────────────────────────┘ │
│     ↓                                                   │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ If App update available:                            │ │
│ │   → Check local storage for reminder state          │ │
│ │   → Show prompt at 1 day, 3 days, 7 days           │ │
│ │   → After 7 days: stop reminding (soft)            │ │
│ │   → Force update: block after 7-day grace          │ │
│ └─────────────────────────────────────────────────────┘ │
│     ↓                                                   │
│ Continue using app                                      │
└─────────────────────────────────────────────────────────┘
```

---

### Local Storage for App Update Reminders

```swift
struct AppUpdateReminderState: Codable {
    let version: String           // Which version we're reminding about
    let firstShownAt: Date        // When we first showed reminder
    let lastShownAt: Date         // When we last showed reminder
    let reminderCount: Int        // How many times shown (1, 3, 7 days)
}
```

**Logic:**
1. New app version detected → Check local storage for this version
2. If not stored → First reminder, save state with reminderCount = 1, firstShownAt = now
3. If stored → Check days since firstShownAt:
   - Day 1: Show if reminderCount < 1
   - Day 3: Show if reminderCount < 2  
   - Day 7: Show if reminderCount < 3
   - After day 7: Don't show anymore (soft update)
4. New version released → Overwrite stored state, reset everything

**Force Update Grace Period:**
- Grace period is **7 days from when the user first sees the update** (stored in `firstShownAt`)
- NOT from the server's `released_at` timestamp
- This ensures users who don't open the app frequently get a fair grace period
- After 7 days from first detection → blocking screen

---

### New Domain Models

```swift
// WhatsThatDomain/Requirements/AppConfigResponse.swift

public struct MaintenanceStatus: Sendable, Equatable, Codable {
    public let enabled: Bool
    public let message: String?  // Custom message from admin, if any
}

public struct VersionInfo: Sendable, Equatable, Codable {
    public let version: String
    public let message: String?
    public let releasedAt: Date
}

public struct AppVersionInfo: Sendable, Equatable, Codable {
    public let version: String
    public let message: String?
    public let releasedAt: Date
    public let appUpdateType: UpdateType?
    public let minSupportedVersion: String
    public let appStoreUrl: String
}

public struct UserStatus: Sendable, Equatable, Codable {
    public let needsTosAcceptance: Bool
    public let needsPrivacyAcceptance: Bool
    public let acceptedTosVersion: String?
    public let acceptedPrivacyVersion: String?
}

public struct AppConfigResponse: Sendable, Equatable, Codable {
    public let maintenance: MaintenanceStatus
    public let tos: VersionInfo
    public let privacy: VersionInfo
    public let app: AppVersionInfo
    public let userStatus: UserStatus?  // nil if not authenticated
}

public enum UpdateType: String, Sendable, Codable {
    case soft
    case force
}
```

---

### File Structure

```
WhatsThatDomain/
  Requirements/
    AppConfigResponse.swift
    AppRequirementsUseCase.swift
    AppUpdateReminderState.swift
    PendingAcceptance.swift

WhatsThatData/
  Repositories/
    Requirements/
      SupabaseRequirementsRepository.swift
      UserDefaultsConfigCacheRepository.swift

WhatsThatPresentation/
  Features/
    Requirements/
      LegalAcceptanceView.swift       # Checkbox + Continue
      AppUpdatePromptView.swift       # Soft reminder
      ForceUpdateView.swift           # Blocking screen

supabase/
  migrations/
    YYYYMMDD_version_control_tables.sql
    YYYYMMDD_version_control_functions.sql
```

---

## Verification Checklist

### Automated Tests
- [ ] Version comparison logic (`"1.0" < "1.1" < "2.0"`, `"1.10" > "1.9"`)
- [ ] Semantic version parsing (split on `.`, compare as integers)
- [ ] Cache validity check (< 24 hours = valid)
- [ ] Reminder schedule logic (1/3/7 days from first detection)
- [ ] Grace period calculation for force updates (7 days from first detection)
- [ ] Exponential backoff timing (30s → 60s → 120s → 240s → 480s)

### Manual Tests (Development)
- [ ] ToS update → checkbox modal appears → must accept to continue
- [ ] Accept → PendingAcceptance stored → modal dismisses → background submission
- [ ] Decline → taps "Sign Out" → logged out immediately
- [ ] Soft app update → reminders at 1/3/7 days → stops after 7 days
- [ ] Force app update (Grace Phase) → blocks after 7-day grace from first detection
- [ ] Force app update (Hard Block / Deprecated) → blocks IMMEDIATELY if version < min_supported_version
- [ ] Offline + valid cache → uses cache, app works normally
- [ ] Offline + no cache → app loads normally, no checks
- [ ] New user signup → acceptance recorded automatically
- [ ] Existing user (backfilled) → no modal for v1.0
- [ ] Cache valid → no network call made
- [ ] Cache expired → network call made, cache updated

### Error State Tests (Using Debug Controls)
- [ ] Config fetch fails + valid cache → uses cache
- [ ] Config fetch fails + expired cache → uses expired cache
- [ ] Config fetch fails + no cache → proceeds without checking
- [ ] Terms acceptance fails → modal dismisses, silent retry with backoff
- [ ] All 5 retries fail → pending acceptance stored, retried on next launch
- [ ] App Store link fails → alert with copyable URL shown
- [ ] User force-quits during acceptance retry → pending stays, retried on next launch
- [ ] User backgrounds app during acceptance → continues in background

### Edge Case Tests
- [ ] User who has never accepted anything (new account after feature launch)
- [ ] User with previous acceptances viewing newer ToS
- [ ] Modal appearance during active discovery creation
- [ ] Modal appearance while audio is playing
- [ ] Both ToS and Privacy updated simultaneously
- [ ] User opens app after 25 hours (cache expired)

### Deployment Guide Verification
- [ ] Test deployment guide steps in development environment
- [ ] Verify SQL commands work correctly
- [ ] After verification, migrate deployment guide to main documentation

---

## Why No App Version in user_agreements?

You asked if we need `acknowledged_app_version` in the database. **We don't need it because:**

1. **App updates are informational** — users don't "accept" app updates legally
2. **Reminder state is per-device** — if user has multiple devices, each tracks its own reminders
3. **No audit requirement** — unlike legal acceptance, we don't need to prove when a user was told about an app update
4. **Simpler architecture** — local UserDefaults is faster and doesn't require network

If you ever need to track "user acknowledged app version X" for analytics, we could add it, but for the core feature it's not necessary.

---

## Decision on Triggers vs. Direct Queries

We chose **Direct Queries** (joining `version_log` and `app_config`) over a Database Trigger logic because:

1.  **Atomicity:** Time is the single source of truth for "latest version". Relational queries (`ORDER BY released_at`) are robust.
2.  **Simplicity:** Writing a trigger to copy `version_log` data into `app_config` introduces complexity (sync bugs, race conditions) for negligible performance gain on 3 rows.
3.  **Separation of Concerns:** 
    -   `version_log` = Immutable History (managed by deployment scripts)
    -   `app_config` = Mutable Global State (managed by admin dashboard/SQL)

