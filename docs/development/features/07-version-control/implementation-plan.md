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
6. **Force update using Min Supported Version** — simple blocking mechanism for deprecated versions
7. **Graceful offline handling** — if offline, use session cache or skip checks (unless already in blocking state)
8. **Retry with feedback** — automatic retries (3x), then show error for manual retry
9. **Pre-computed compliance status** — server tells client what's needed, not just versions
10. **Session-based caching** — config fetched fresh on app launch, cached in memory for session duration

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
  
  -- Version identifier using semantic versioning (e.g., "1.0.0", "1.1.0", "2.0.3")
  version TEXT NOT NULL,
  
  -- Optional message to show users about what changed
  message TEXT,
  
  -- For app versions only: update behavior
  -- 'soft' = reminder prompts at 1/3/7 days
  -- 'force' = 7-day grace period, then blocking
  app_update_type update_type DEFAULT 'soft',
  
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

-- Idempotency: Prevent duplicate acceptances for the same user + version combination
-- Uses COALESCE to handle NULL values (treats NULL as empty string for uniqueness)
CREATE UNIQUE INDEX idx_user_agreements_unique_acceptance
  ON public.user_agreements(user_id, COALESCE(tos_version, ''), COALESCE(privacy_version, ''));

ALTER TABLE public.user_agreements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own agreements" ON public.user_agreements
  FOR SELECT USING (auth.uid() = user_id);

-- Note: No direct INSERT policy - we use a database function instead
```

> [!NOTE]
> **Data Retention & GDPR:**
> - Acceptance records are valuable for legal audits but are considered personal data under GDPR.
> - **On account deletion:** The `ON DELETE CASCADE` constraint automatically deletes all `user_agreements` rows when the user is deleted from `auth.users`.
> - This is required for GDPR "right to be forgotten" compliance.
> - **Reference:** Ensure your Privacy Policy states that acceptance records are deleted upon account deletion. See `docs/legal/PRIVACY_POLICY.md` - the "Data Retention" or "Your Rights" section should mention this.

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
-- All versions use semantic versioning: Major.Minor.Patch
INSERT INTO public.version_log (type, version, message) VALUES
  ('tos', '1.0.0', 'Initial Terms of Service'),
  ('privacy', '1.0.0', 'Initial Privacy Policy'),
  ('app', '1.0.0', 'Initial release');
```

---

### Existing User Backfill (One-Time Migration)

At feature deployment, all existing users need acceptance records for v1.0.0 (they agreed at signup):

```sql
-- Run once at feature deployment
INSERT INTO public.user_agreements (user_id, tos_version, privacy_version, accepted_at)
SELECT id, '1.0.0', '1.0.0', NOW()  -- Use NOW() to approximate "accepted before feature launch"
FROM auth.users
WHERE id NOT IN (SELECT DISTINCT user_id FROM public.user_agreements);
```

> [!IMPORTANT]
> This must be run after creating the tables but before the iOS app is updated to use this feature.

---

## Database Functions

### `get_app_config()`

Returns the latest versions + user's compliance status.

> [!IMPORTANT]
> **Semantic Versioning Fix:** We perform version comparison using specific SQL logic or strict inequality checking to avoid string comparison bugs (e.g. "1.10" < "1.9"). For ToS/Privacy, we check strict inequality (`latest != accepted`) to trigger acceptance.

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

  -- App config fields
  config_record RECORD;
BEGIN
  -- Get app config (fail fast if missing)
  SELECT * INTO config_record FROM public.app_config LIMIT 1;
  IF config_record IS NULL THEN
    RAISE EXCEPTION 'App config missing';
  END IF;

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
    
    SELECT privacy_version INTO user_privacy_version 
    FROM public.user_agreements 
    WHERE user_id = current_user_id AND privacy_version IS NOT NULL 
    ORDER BY accepted_at DESC LIMIT 1;
  END IF;
  
  -- Build response
  SELECT json_build_object(
    'maintenance', json_build_object(
      'enabled', config_record.maintenance_mode,
      'message', config_record.maintenance_message
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
        'min_supported_version', config_record.min_supported_version,
        'app_store_url', config_record.app_store_url,
        -- Last force version: most recent app version with app_update_type = 'force'
        -- Client compares: if user_version < last_force_version → force update required
        'last_force_version', (
          SELECT version FROM public.version_log
          WHERE type = 'app' AND app_update_type = 'force'
          ORDER BY released_at DESC LIMIT 1
        )
      )
      FROM public.version_log v
      WHERE v.type = 'app'
      ORDER BY v.released_at DESC LIMIT 1
    ),
    'user_status', CASE 
      WHEN current_user_id IS NOT NULL THEN json_build_object(
        -- FIX: Strict inequality check. If versions differ, require acceptance.
        'needs_tos_acceptance', (user_tos_version IS NULL OR user_tos_version <> latest_tos_version),
        'needs_privacy_acceptance', (user_privacy_version IS NULL OR user_privacy_version <> latest_privacy_version),
        'accepted_tos_version', user_tos_version,
        'accepted_privacy_version', user_privacy_version
      )
      ELSE NULL 
    END
  ) INTO result;
  
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_app_config() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_config() TO anon;
```

---

### `accept_terms()`

Records user acceptance. **Validates that user is applying the LATEST version**.

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
  
  -- Insert acceptance record (idempotent - ignores duplicates)
  INSERT INTO public.user_agreements (user_id, tos_version, privacy_version)
  VALUES (current_user_id, tos_to_insert, privacy_to_insert)
  ON CONFLICT (user_id, COALESCE(tos_version, ''), COALESCE(privacy_version, '')) DO NOTHING;

  RETURN json_build_object(
    'success', true,
    'accepted_tos_version', tos_to_insert,
    'accepted_privacy_version', privacy_to_insert
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_terms(TEXT, TEXT) TO authenticated;
```

---

## Version Comparison Algorithm

App versions use semantic versioning (Major.Minor.Patch). String comparison doesn't work correctly (e.g., "1.10.0" < "1.9.0" is true with string comparison but false semantically).

### Swift Implementation

```swift
extension String {
    /// Compares semantic versions. Returns true if self < other.
    /// Examples: "1.2.0".isVersionLessThan("1.10.0") → true
    ///           "2.0.0".isVersionLessThan("1.9.0") → false
    func isVersionLessThan(_ other: String) -> Bool {
        let v1Components = self.split(separator: ".").compactMap { Int($0) }
        let v2Components = other.split(separator: ".").compactMap { Int($0) }

        // Pad shorter array with zeros for comparison
        let maxLength = max(v1Components.count, v2Components.count)
        let v1Padded = v1Components + Array(repeating: 0, count: maxLength - v1Components.count)
        let v2Padded = v2Components + Array(repeating: 0, count: maxLength - v2Components.count)

        for i in 0..<maxLength {
            if v1Padded[i] < v2Padded[i] { return true }
            if v1Padded[i] > v2Padded[i] { return false }
        }
        return false // Equal versions
    }
}
```

### Usage

```swift
let userVersion = Bundle.main.appVersion // e.g., "1.2.0"
let minSupported = config.app.minSupportedVersion // e.g., "1.5.0"

if userVersion.isVersionLessThan(minSupported) {
    // Block user - version too old
}
```

---

## JSON Response Structures

### `get_app_config()` Response

The server returns this JSON structure:

```json
{
  "maintenance": {
    "enabled": false,
    "message": null
  },
  "tos": {
    "version": "1.0.0",
    "message": "Initial Terms of Service",
    "released_at": "2024-01-15T10:00:00Z"
  },
  "privacy": {
    "version": "1.0.0",
    "message": "Initial Privacy Policy",
    "released_at": "2024-01-15T10:00:00Z"
  },
  "app": {
    "version": "1.2.0",
    "message": "New features and bug fixes",
    "released_at": "2024-02-01T10:00:00Z",
    "app_update_type": "soft",
    "min_supported_version": "1.0.0",
    "app_store_url": "https://apps.apple.com/app/id...",
    "last_force_version": null
  },
  "user_status": {
    "needs_tos_acceptance": false,
    "needs_privacy_acceptance": false,
    "accepted_tos_version": "1.0.0",
    "accepted_privacy_version": "1.0.0"
  }
}
```

> [!NOTE]
> `user_status` is `null` for unauthenticated users (anon role).

### Swift Codable Structs

```swift
struct AppConfigResponse: Codable {
    let maintenance: MaintenanceConfig
    let tos: VersionInfo
    let privacy: VersionInfo
    let app: AppVersionInfo
    let userStatus: UserComplianceStatus?

    enum CodingKeys: String, CodingKey {
        case maintenance, tos, privacy, app
        case userStatus = "user_status"
    }
}

struct MaintenanceConfig: Codable {
    let enabled: Bool
    let message: String?
}

struct VersionInfo: Codable {
    let version: String
    let message: String?
    let releasedAt: Date

    enum CodingKeys: String, CodingKey {
        case version, message
        case releasedAt = "released_at"
    }
}

struct AppVersionInfo: Codable {
    let version: String
    let message: String?
    let releasedAt: Date
    let appUpdateType: UpdateType
    let minSupportedVersion: String
    let appStoreUrl: String
    let lastForceVersion: String?

    enum CodingKeys: String, CodingKey {
        case version, message
        case releasedAt = "released_at"
        case appUpdateType = "app_update_type"
        case minSupportedVersion = "min_supported_version"
        case appStoreUrl = "app_store_url"
        case lastForceVersion = "last_force_version"
    }
}

enum UpdateType: String, Codable {
    case soft
    case force
}

struct UserComplianceStatus: Codable {
    let needsTosAcceptance: Bool
    let needsPrivacyAcceptance: Bool
    let acceptedTosVersion: String?
    let acceptedPrivacyVersion: String?

    enum CodingKeys: String, CodingKey {
        case needsTosAcceptance = "needs_tos_acceptance"
        case needsPrivacyAcceptance = "needs_privacy_acceptance"
        case acceptedTosVersion = "accepted_tos_version"
        case acceptedPrivacyVersion = "accepted_privacy_version"
    }
}
```

### `accept_terms()` Response

```json
{
  "success": true,
  "accepted_tos_version": "1.1.0",
  "accepted_privacy_version": "1.1.0"
}
```

```swift
struct AcceptTermsResponse: Codable {
    let success: Bool
    let acceptedTosVersion: String?
    let acceptedPrivacyVersion: String?

    enum CodingKeys: String, CodingKey {
        case success
        case acceptedTosVersion = "accepted_tos_version"
        case acceptedPrivacyVersion = "accepted_privacy_version"
    }
}
```

---

## Client-Side Strategy: Session Caching with Staleness Check

We use **in-memory session caching** with a **staleness check on foreground**.

### Core Principles

1. **Fresh on Launch:** Always fetch config on cold start
2. **Cached During Active Use:** No repeated network calls while user is actively using the app
3. **Staleness Check on Resume:** If app was backgrounded > 1 hour, refresh config on foreground
4. **Maintenance Mode Persistence:** Maintenance state is cached for 3 hours to survive fetch failures

### Config Fetch Timing

| Event | Action |
|-------|--------|
| Cold start (app launch) | Fetch fresh config |
| Foreground resume, config < 1 hour old | Use cached config |
| Foreground resume, config >= 1 hour old | Background refresh config |
| During active session | Use cached config |

### Staleness Check Implementation

```swift
// In AppFlowState or similar
private var lastConfigFetchTime: Date?
private let configStalenessThreshold: TimeInterval = 3600 // 1 hour

func onScenePhaseActive() {
    guard let lastFetch = lastConfigFetchTime else {
        fetchConfig() // No cache, must fetch
        return
    }

    if Date().timeIntervalSince(lastFetch) > configStalenessThreshold {
        // Config is stale, refresh in background
        Task { await fetchConfig() }
    }
}
```

### Cache Keys (UserDefaults)

| Key | Type | Purpose |
|-----|------|---------|
| `app_update_reminder_state` | `AppUpdateReminderState` | Soft/force update grace period tracking (see structure below) |
| `cached_maintenance_state` | `CachedMaintenanceState` | Maintenance mode persistence for fetch failures (see structure below) |

### Data Structures

```swift
/// Tracks the user's interaction with app update prompts
/// Note: Soft and force updates have different tracking semantics
struct AppUpdateReminderState: Codable {
    // SOFT updates - per-version tracking (resets for each new version)
    var softUpdateVersion: String?    // The soft version currently being tracked
    var lastReminderDate: Date?       // Last reminder shown for soft update
    var reminderCount: Int            // 0, 1, 2, or 3 (day 1, day 3, day 7)

    // FORCE updates - first force seen (does NOT reset for new versions)
    var forceGracePeriodStartDate: Date?  // When user first saw ANY force update
}
```

> [!IMPORTANT]
> **Grace period does NOT reset.** Once a user sees their first force update, the 7-day countdown begins and continues regardless of new force versions released. This prevents users from indefinitely delaying updates by waiting for each new version to reset their grace period.

```swift
/// Caches maintenance mode state to survive fetch failures
struct CachedMaintenanceState: Codable {
    let isEnabled: Bool          // Was maintenance mode active?
    let message: String?         // The maintenance message (if any)
    let cachedAt: Date           // When this was cached

    /// Returns true if cache is still valid (within 3 hours)
    var isValid: Bool {
        Date().timeIntervalSince(cachedAt) < 10800 // 3 hours
    }
}
```

**Grace Period Calculation (Force Update):**
```swift
func isForceGracePeriodExpired(state: AppUpdateReminderState) -> Bool {
    guard let startDate = state.forceGracePeriodStartDate else {
        return false // No force update seen yet
    }
    let gracePeriodDays = 7
    let gracePeriodSeconds = TimeInterval(gracePeriodDays * 24 * 60 * 60)
    return Date().timeIntervalSince(startDate) > gracePeriodSeconds
}

/// Call this when user first sees a force update requirement
func markForceUpdateSeen(state: inout AppUpdateReminderState) {
    // Only set if not already set - grace period does NOT reset
    if state.forceGracePeriodStartDate == nil {
        state.forceGracePeriodStartDate = Date()
    }
}
```

**Soft Update Reminder Schedule:**
- Day 1: Show first reminder (`reminderCount = 1`)
- Day 3: Show second reminder (`reminderCount = 2`)
- Day 7: Show final reminder (`reminderCount = 3`)
- After Day 7: Stop showing for this version

---

## Error Handling

### Config Fetch Failures

| Scenario | Behavior |
|----------|----------|
| Fetch fails + Session cache exists | Use session cache (soft fail) |
| Fetch fails + No session cache + Valid maintenance cache | **Show maintenance mode** (cached state) |
| Fetch fails + No session cache + Expired/no maintenance cache | Proceed without checking (assume compliant) |
| Maintenance/Blocking Mode | Retry on foreground or via manual button |

### Maintenance Mode Caching Logic

When config fetch succeeds and `maintenance.enabled = true`:
1. Save `CachedMaintenanceState` to UserDefaults with current timestamp
2. Show maintenance screen

When config fetch fails:
1. Check if `CachedMaintenanceState` exists and `isValid` (< 3 hours old)
2. If valid → Show maintenance screen (user can't bypass by going offline)
3. If expired or missing → Proceed normally (fail-open)

```swift
func handleConfigFetchFailure() {
    // Try session cache first
    if let sessionCache = inMemoryConfigCache {
        useConfig(sessionCache)
        return
    }

    // Check maintenance cache for fetch failures
    if let maintenanceCache = loadCachedMaintenanceState(),
       maintenanceCache.isValid,
       maintenanceCache.isEnabled {
        showMaintenanceScreen(message: maintenanceCache.message)
        return
    }

    // No valid cache, proceed without checking (fail-open)
    proceedWithoutComplianceCheck()
}
```

### Terms Acceptance Flow

When user taps "Accept and Continue":

1. **Disable button, show spinner**
2. **Retry up to 3 times** with 1-second delays between attempts
3. **On success:** Dismiss modal, continue to app
4. **On all failures:** Show inline error, re-enable button for manual retry

```swift
func onAcceptTapped(tosVersion: String?, privacyVersion: String?) async {
    isSubmitting = true
    errorMessage = nil

    for attempt in 1...3 {
        do {
            try await acceptTerms(tos: tosVersion, privacy: privacyVersion)
            // Success - dismiss modal
            await MainActor.run { dismissModal() }
            return
        } catch {
            if attempt < 3 {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // All 3 attempts failed
    await MainActor.run {
        isSubmitting = false
        errorMessage = "Network error. Please check your connection and try again."
    }
}
```

| Scenario | Behavior |
|----------|----------|
| User taps Accept | Show spinner, retry up to 3x |
| All retries succeed | Dismiss modal, continue to app |
| All retries fail | Show inline error: "Network error. Please check your connection and try again." |
| User taps Accept again | Same retry flow (3 attempts) |
| User taps Sign Out | Clear auth session, return to login |
| User force-closes app | On next launch, config shows `needs_acceptance = true`, modal appears again |

> [!NOTE]
> **No persistence needed.** The modal stays open until server confirms acceptance. If user force-closes, they simply see the modal again on next launch. This is acceptable UX for the rare network failure case.

### Sign Out Cleanup

When user signs out (from Legal Modal or anywhere else), clear all user-specific cached state:

```swift
func signOut() {
    // Clear session config cache
    inMemoryConfigCache = nil
    lastConfigFetchTime = nil

    // Note: Keep app_update_reminder_state (not user-specific, tracks app version)
    // Note: Keep cached_maintenance_state (system-wide, not user-specific)

    // Clear auth session
    try? supabase.auth.signOut()

    // Navigate to login
    appFlowState.navigateToLogin()
}
```

### Version Mismatch (Race Condition)

| Scenario | Behavior |
|----------|----------|
| `accept_terms` throws mismatch | Indicates new version deployed while user was viewing |
| Action | Catch error -> Fetch new config -> Show new modal |

---

## iOS Application Changes

### Blocking Condition Priority

When multiple conditions are true, show screens in this priority order:

| Priority | Condition | Screen | Rationale |
|----------|-----------|--------|-----------|
| 1 (Highest) | `maintenance.enabled = true` | Maintenance Mode | Entire system is down, nothing works |
| 2 | Version < `min_supported_version` | Force Update (immediate) | App cannot function on deprecated version |
| 3 | Version < `last_force_version` + grace expired | Force Update (expired) | Critical update required |
| 4 | `needs_tos_acceptance` or `needs_privacy_acceptance` | Legal Acceptance Modal | Legal requirement before using app |
| 5 | Version < `last_force_version` + within grace | Force Update (grace) | Warning, but dismissible |
| 6 (Lowest) | Soft update reminder due | Soft Update Prompt | Informational, fully dismissible |

**Key Distinction:**
- `min_supported_version`: Immediate block, no grace period (for deprecated APIs, breaking changes)
- `last_force_version`: 7-day grace period (for security fixes, critical updates)

```swift
func determineBlockingState(config: AppConfig, userVersion: String) -> BlockingState? {
    // Priority 1: Maintenance mode
    if config.maintenance.enabled {
        return .maintenance(message: config.maintenance.message)
    }

    // Priority 2: Below minimum supported version (immediate block, no grace)
    if userVersion.isVersionLessThan(config.app.minSupportedVersion) {
        return .forceUpdateImmediate(targetVersion: config.app.version)
    }

    // Priority 3 & 5: Check last_force_version (with grace period)
    if let lastForceVersion = config.app.lastForceVersion,
       userVersion.isVersionLessThan(lastForceVersion) {
        // User is below the last force version - check grace period
        var state = loadAppUpdateReminderState() ?? AppUpdateReminderState()

        // Mark that user has seen a force update (only sets date if nil - doesn't reset)
        markForceUpdateSeen(state: &state)
        saveAppUpdateReminderState(state)

        if isForceGracePeriodExpired(state: state) {
            // Priority 3: Grace expired → block
            return .forceUpdateExpired(targetVersion: config.app.version)
        }
        // Priority 5 handled later (non-blocking but prominent)
    }

    // Priority 4: Legal acceptance required
    if config.userStatus?.needsTosAcceptance == true ||
       config.userStatus?.needsPrivacyAcceptance == true {
        return .legalAcceptance(
            needsTos: config.userStatus?.needsTosAcceptance ?? false,
            needsPrivacy: config.userStatus?.needsPrivacyAcceptance ?? false
        )
    }

    // Priorities 5 & 6 are non-blocking, handled separately
    return nil
}

/// For SOFT updates: Check if we need to reset tracking for a new version
func updateSoftUpdateTracking(state: inout AppUpdateReminderState, forVersion version: String) {
    if state.softUpdateVersion != version {
        // New soft version - reset reminder tracking
        state.softUpdateVersion = version
        state.lastReminderDate = nil
        state.reminderCount = 0
    }
}

/// Clear force grace period when user updates their app
func clearForceGracePeriodIfUpdated(state: inout AppUpdateReminderState, userVersion: String, lastForceVersion: String?) {
    guard let forceVersion = lastForceVersion else { return }
    // If user is now at or above the last force version, clear the grace period
    if !userVersion.isVersionLessThan(forceVersion) {
        state.forceGracePeriodStartDate = nil
    }
}
```

### Non-Blocking Load Flow

```
App Launch
    ↓
Load main app normally (non-blocking)
    ↓
Background: Fetch config (fresh on every launch)
    ↓
Check blocking conditions (maintenance, min_supported_version, etc.)
    ↓
If blocking condition → Show blocking screen immediately
    ↓
Check user_status.needs_tos/privacy_acceptance
    ↓
If needs acceptance:
    → Wait for "Safe-to-Present" state (see below)
    → Show modal (stays open until server confirms)
```

### Safe-to-Present Implementation

To avoid interrupting critical flows (recording, playback), we implement a **ZStack overlay** at the absolute root level.

> [!IMPORTANT]
> **Why ZStack instead of .sheet:** SwiftUI's `.sheet` presentation fails silently or crashes when a `.fullScreenCover` is already active (e.g., Camera). A ZStack overlay at the root level guarantees the modal appears above ALL content, including fullScreenCovers.

```swift
// Integration at app root (e.g., ContentView or App scene)
var body: some Scene {
    WindowGroup {
        ZStack {
            MainAppContent()
                .environmentObject(appFlowState)

            // Compliance overlay - appears above EVERYTHING
            if appFlowState.shouldShowComplianceModal {
                ComplianceOverlayView(appFlowState: appFlowState)
                    .transition(.opacity)
                    .zIndex(1000) // Ensure it's above all other content
            }
        }
    }
}
```

**Safe-to-Present Logic:**
- `appFlowState.pendingComplianceModal` stores the modal type when compliance is needed
- `appFlowState.shouldShowComplianceModal` is computed: returns `true` only when:
  - There IS a pending modal, AND
  - **App is in `.main` state** (not onboarding), AND
  - Current screen is "safe" (Home, Settings, Lists)
- **Unsafe Screens** (Camera, Streaming, Playback, Paywall): Set `appFlowState.currentScreen` to unsafe value, which makes `shouldShowComplianceModal` return `false`
- When user navigates back to a safe screen, the overlay automatically appears

### Onboarding Deferral

Compliance modals are **deferred until after onboarding completes**. The app uses `AppFlowState` to track user progress:

```swift
public enum AppFlowState: Equatable, Sendable {
    case loading
    case preOnboarding        // Showing intro carousel
    case authentication       // Sign in / Sign up
    case postOnboarding       // Voice picker, preferences, permissions
    case main(AuthenticatedUser)  // ← Only show compliance modals here
}
```

**Implementation:**

```swift
var shouldShowComplianceModal: Bool {
    guard case .main = appFlowState else {
        // Not in main app yet - defer compliance checks
        return false
    }
    guard let pending = pendingComplianceModal else {
        return false
    }
    return currentScreen.isSafe
}
```

> [!NOTE]
> **Why defer during onboarding?** Interrupting onboarding with legal modals creates a confusing experience. The user just signed up (accepting terms) and immediately sees another acceptance modal. By deferring to the main app state, we ensure a smooth first-run experience. The compliance check still happens - just after onboarding completes.

### Maintenance & Force Update

**Refresh Logic:**
- **Fresh on Every Session:** Config is fetched on every app launch (cold start).
- **App Version Change:** If `Bundle.main.appVersion` changes (user updated via App Store), force immediate re-fetch on foreground.
- **Manual Retry:** "Check Again" button on blocking screens (rate-limited to once per minute).

**Rate-Limited Manual Refresh:**

The "Check Again" button always shows immediate feedback (spinner), but actual network calls are rate-limited to prevent abuse:

```swift
class BlockingScreenViewModel: ObservableObject {
    @Published var isChecking = false
    private var lastCheckTime: Date?
    private let checkCooldown: TimeInterval = 60 // 1 minute

    func onCheckAgainTapped() async {
        // Always show spinner for UX consistency
        await MainActor.run { isChecking = true }

        // Check if we can actually make a network call
        let now = Date()
        let canCheck = lastCheckTime == nil || now.timeIntervalSince(lastCheckTime!) >= checkCooldown

        if canCheck {
            lastCheckTime = now
            await fetchConfigAndUpdateState()
        } else {
            // Rate limited - just wait a moment for UX, then return current state
            try? await Task.sleep(for: .seconds(1))
        }

        await MainActor.run { isChecking = false }
    }
}
```

> [!NOTE]
> **No auto-polling.** Users manually tap "Check Again" when ready. This is simpler than background polling and gives users control. The 1-minute rate limit prevents accidental spam while still feeling responsive.

### New User Signup Flow

1. **User Lands on Signup Screen** → Fetch `get_app_config()` to get current ToS/Privacy versions.
2. **Display Versions** → Show "By signing up, you agree to our Terms of Service (v1.0) and Privacy Policy (v1.0)" with links.
3. **Signup Success** → User authenticated.
4. **Immediate Acceptance** → Client calls `accept_terms(tos_version, privacy_version)` with the versions fetched in step 1.
5. **Failure Handling** → If `accept_terms` fails (network), retry up to 3x. If still fails, the user is signed up but will see the legal modal on their first safe screen (normal compliance flow).

```swift
// Signup flow pseudocode
func onSignupScreenAppear() async {
    // Config should already be cached from app launch
    // If not, fetch it - signup requires knowing current versions
    if signupTosVersion == nil {
        let config = try? await fetchConfig()
        self.signupTosVersion = config?.tos.version
        self.signupPrivacyVersion = config?.privacy.version
    }
}

func onSignupSuccess() async {
    guard let tosVersion = signupTosVersion,
          let privacyVersion = signupPrivacyVersion else {
        // Edge case: Config fetch failed before signup
        // User will see legal modal on first safe screen via normal flow
        return
    }

    // Retry up to 3 times
    for attempt in 1...3 {
        do {
            try await acceptTerms(tos: tosVersion, privacy: privacyVersion)
            return // Success
        } catch {
            if attempt < 3 {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // All retries failed - user will see legal modal via normal compliance flow
    // This is an extremely rare edge case (server worked for signup but not for accept_terms)
}
```

> [!NOTE]
> **No fallback version.** If config fetch fails, we don't hardcode a version. The user signs up successfully, and the normal compliance flow will show them the legal modal on their first safe screen. This is cleaner than risking a version mismatch.

---

## Verification Checklist

### Automated Tests
- [ ] Version comparison logic (semantic, in Swift)
- [ ] Reminder schedule logic (1/3/7 days)
- [ ] Grace period calculation
- [ ] Rate-limited refresh timing (1 minute cooldown)

### Manual Tests
- [ ] **SQL Check:** Verify `latest found` versions in `get_app_config`
- [ ] ToS update → checkbox modal appears on safe screen
- [ ] Accept button → spinner → retries → success → modal dismissed
- [ ] Accept button → all retries fail → error shown → user can retry
- [ ] Onboarding → compliance modal deferred until main app
- [ ] Offline + valid session cache → uses cache
- [ ] Offline + no cache → proceeds (fail open)
- [ ] Force App Update → blocks if version < min_supported
- [ ] Maintenance Mode → blocks entry
- [ ] Check Again button → rate limited to once per minute
- [ ] Duplicate accept_terms call → idempotent (no duplicate rows)
