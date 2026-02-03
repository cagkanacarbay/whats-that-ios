# Deployment Guide: Releasing New Versions

This guide covers how to release new versions of ToS, Privacy Policy, and the app after the version control system is deployed.

---

## Using Claude Skills

The recommended way to create version releases is using the Claude skills:

| Task | Skill | What It Does |
|------|-------|--------------|
| Update ToS or Privacy Policy | `/legal-update` | Interactive workflow to create a migration for legal document updates |
| Release new app version | `/release-update` | Interactive workflow to create a migration for app releases |

Both skills will:
1. Ask you for the relevant information (version, changes, etc.)
2. Generate well-formatted change notes
3. Create a properly named migration file
4. Remind you to deploy to the appropriate environment

---

## Releasing a New ToS Version

### Option 1: Use the Skill (Recommended)

Run `/legal-update` and follow the prompts.

### Option 2: Manual Process

1. **Update the document** at [TERMS_AND_CONDITIONS.md](../../../legal/TERMS_AND_CONDITIONS.md):
   - Update "Effective date" at the top
   - Update "Version" number (use semantic versioning: Major.Minor.Patch)
   - Make your changes

2. **Deploy to website** - Ensure the updated ToS is live at `https://whats-that.app/legal/terms-and-conditions`

3. **Create migration file** `supabase/migrations/YYYYMMDDHHMMSS_tos_version_X_X_X.sql`:

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

4. **Deploy:**
```bash
# Development
supabase link --project-ref cywshvmspnvimucwqarc && supabase db push

# Production
supabase link --project-ref vipghlhvnrdheoydynty && supabase db push
```

5. **Verify** - Launch app as a test user → should see Legal Acceptance modal

---

## Releasing a New Privacy Policy Version

### Option 1: Use the Skill (Recommended)

Run `/legal-update` and follow the prompts.

### Option 2: Manual Process

1. **Update the document** at [PRIVACY_POLICY.md](../../../legal/PRIVACY_POLICY.md):
   - Update "Effective date"
   - Update "Version" number
   - Make your changes

2. **Deploy to website** - Ensure updated policy is live at `https://whats-that.app/legal/privacy-policy`

3. **Create migration file** `supabase/migrations/YYYYMMDDHHMMSS_privacy_version_X_X_X.sql`:

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

4. **Deploy** and **Verify** as above.

---

## Releasing a New App Version

### Option 1: Use the Skill (Recommended)

Run `/release-update` and follow the prompts.

### Option 2: Manual Process

#### 1. Decide Update Type

| Type | When to Use | User Experience |
|------|-------------|-----------------|
| `soft` | New features, improvements, non-critical fixes | Dismissible reminder, stops after 3 prompts |
| `force` | Security fixes, breaking API changes, critical bugs | 7-day grace period, then blocking |

#### 2. Submit to App Store

Follow normal App Store submission process.

#### 3. Create Migration (after App Store approval)

**For soft updates:**
```sql
-- App Version X.X.X Release
-- Type: soft
-- Date: YYYY-MM-DD

INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES (
    'app',
    'X.X.X',
    $$What's new in this update:

- **Feature 1** - Description
- **Bug fixes** - What was fixed$$,
    'soft'
);
```

**For force updates:**
```sql
-- App Version X.X.X Release
-- Type: force
-- Date: YYYY-MM-DD

INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES (
    'app',
    'X.X.X',
    $$Critical update required:

- **Security** - Important security improvements
- **Compatibility** - Required for continued service$$,
    'force'
);
```

#### 4. Deploy migration

```bash
supabase link --project-ref vipghlhvnrdheoydynty && supabase db push
```

### How Force Updates Work

The server returns `last_force_version` (the most recent force update version) in the config response. The client compares: if `user_version < last_force_version` → force update required with 7-day grace period.

This means even if you later release v1.4.0 (soft), users on v1.0.0 will still see a force update because `1.0.0 < 1.3.0` (the last_force_version).

**Grace Period Behavior:**
- Users on version < `last_force_version`: 7-day grace period, then blocking
- Users on version < `min_supported_version`: Blocked immediately (no grace period)

> **Note:** Grace period does NOT reset with new force versions. Once a user sees their first force update, the 7-day countdown begins and continues regardless of subsequent force releases.

### Set Min Supported Version (Optional - Immediate Block)

If you need to immediately block old versions (e.g., deprecated API):

```sql
UPDATE public.app_config
SET min_supported_version = 'X.X.X';
```

**Effect:** Any user on version < X.X.X will be blocked IMMEDIATELY on next launch (no grace period).

---

## Critical: Release Timing & Sequence

**The order of operations matters.** Database updates must be timed correctly relative to App Store availability.

### App Version Releases

| Step | Action | Why |
|------|--------|-----|
| 1 | Submit app to App Store | Start the review process |
| 2 | Wait for approval and release | App must be downloadable |
| 3 | **THEN** add entry to `version_log` | Users can now see and download the update |

**If you add to `version_log` before the app is in the App Store:**
- Users see "Update Available" prompt
- They tap "Update" and go to App Store
- No update is available → confused users

### Setting `min_supported_version`

| Step | Action | Why |
|------|--------|-----|
| 1 | New app version must be live in App Store | Users need a way to update |
| 2 | **THEN** update `min_supported_version` | Now blocking is safe |

**If you set `min_supported_version` before the app is available:**
- Users on old version are blocked immediately
- They're told to update but can't → locked out of the app

### Force Updates

Same timing applies:
1. App must be in App Store first
2. Then add the `force` entry to `version_log`

### Legal Updates (ToS/Privacy)

Legal updates are **different** - they can be deployed immediately because:
- The updated document should already be live on the website
- Users accept in-app, no App Store dependency
- Deploy to database as soon as the website is updated

### Summary: When to Update Database

| Update Type | When to Update Database |
|-------------|------------------------|
| `version_log` (app, soft) | After app is live in App Store |
| `version_log` (app, force) | After app is live in App Store |
| `min_supported_version` | After app is live in App Store |
| `version_log` (tos/privacy) | Immediately after website is updated |
| `maintenance_mode` | Anytime (emergency use) |

---

## iOS Version Requirements

If a new app version requires a **higher iOS version** than before, include this in the `message` field:

```sql
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES (
    'app',
    '2.0.0',
    $$What's new in this update:

- **New features** - Description here

Note: This update requires iOS 17 or later.$$,
    'force'
);
```

---

## Version Numbering

All version types use **Semantic Versioning (Major.Minor.Patch)**:

| Type | Format | Examples |
|------|--------|----------|
| ToS | Major.Minor.Patch | 1.0.0, 1.1.0, 2.0.0 |
| Privacy | Major.Minor.Patch | 1.0.0, 1.1.0, 2.0.0 |
| App | Major.Minor.Patch | 1.0.0, 1.2.3, 2.0.0 |

### Version Comparison

The system uses **semantic version comparison**:
- `1.0.0 < 1.0.1` (patch update)
- `1.0.1 < 1.1.0` (minor update)
- `1.1.0 < 2.0.0` (major update)
- `1.9.0 < 1.10.0` (semantic, not string comparison)

### When to Increment

| Change Type | Example | When to Use |
|-------------|---------|-------------|
| **Patch** (x.x.1) | 1.0.0 → 1.0.1 | Typo fixes, clarifications, minor wording changes |
| **Minor** (x.1.x) | 1.0.0 → 1.1.0 | New sections, feature-related updates, policy additions |
| **Major** (1.x.x) | 1.0.0 → 2.0.0 | Significant restructuring, major policy changes, legal requirement changes |

---

## Corrections (No Rollback)

> **Note:** Rollbacks are not supported. The version log is append-only for audit trail integrity.

If you made a mistake (e.g., wrong version number, typo in message), publish a corrected version:

```sql
-- Example: You accidentally published ToS 1.2.0 but meant 1.1.0
-- Simply publish the correct version as 1.1.0
INSERT INTO public.version_log (type, version, message)
VALUES (
    'tos',
    '1.1.0',
    $$What's changed in our Terms of Service:

- **Corrected update** - Fixed previous release$$
);
```

The system always uses `ORDER BY released_at DESC LIMIT 1`, so the newest entry wins.

---

## Monitoring

### Check Current Versions

```sql
SELECT DISTINCT ON (type) type, version, message, app_update_type, released_at
FROM public.version_log
ORDER BY type, released_at DESC;
```

### Check User Acceptances

```sql
-- Count users who have accepted latest ToS
SELECT tos_version, COUNT(DISTINCT user_id) as users
FROM public.user_agreements
WHERE tos_version IS NOT NULL
GROUP BY tos_version
ORDER BY tos_version DESC;

-- Users who haven't accepted latest ToS (e.g., 1.1.0)
SELECT DISTINCT ua.user_id
FROM public.user_agreements ua
WHERE NOT EXISTS (
    SELECT 1 FROM public.user_agreements
    WHERE user_id = ua.user_id AND tos_version = '1.1.0'
);
```

### View Full Agreement Audit Log

```sql
SELECT * FROM public.user_agreements
WHERE user_id = '<specific-user-id>'
ORDER BY accepted_at DESC;
```

---

## Environments

| Environment | Project ID | Use For |
|-------------|------------|---------|
| **Development** | `cywshvmspnvimucwqarc` | Testing version releases |
| **Production** | `vipghlhvnrdheoydynty` | Real user releases |

> **Tip:** Always test new version releases in development first before applying to production.

---

## Related Documents

- [Version Control Rollback Guide](./version-control-rollback.md) - Emergency rollback procedures
- [Build & Deploy Guide](./build-and-deploy.md) - Environment configuration and iOS builds

---

*Last updated: 2026-02-03*
