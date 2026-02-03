# Deployment Guide: Releasing New Versions

> [!NOTE]
> **This is a draft guide.** After implementing and testing this feature, verify these steps work correctly, then migrate this content to the main documentation as a standard operating procedure.

---

## Releasing a New ToS Version

### 1. Update the Document

Edit [TERMS_AND_CONDITIONS.md](file:///Users/cagkanacarbay/Projects/whats-that/whats-that-ios/docs/legal/TERMS_AND_CONDITIONS.md):
- Update "Effective date" at the top
- Update "Version" number (use semantic versioning: Major.Minor.Patch)
- Make your changes

### 2. Deploy to Website

Ensure the updated ToS is live at `https://whats-that.app/legal/terms-and-conditions`

### 3. Add Entry to version_log

**In Supabase SQL Editor (Production):**

```sql
INSERT INTO public.version_log (type, version, message)
VALUES (
  'tos',
  '1.1.0',  -- Use semantic versioning: Major.Minor.Patch
  'Added section on audio guides and data processing.'
);
```

The `message` field is **optional but recommended** — it will be shown to users in the acceptance modal to explain what changed.

> [!NOTE]
> **Semantic Version Comparison:** The system uses semantic version comparison, so `1.0.0 < 1.0.1 < 1.1.0 < 2.0.0`. Users only need to accept if their accepted version is less than the latest version.

### 4. Verify

- Launch app as a test user who has accepted ToS 1.0.0
- Should see Legal Acceptance modal with checkbox (immediately on next launch)
- Accept → verify new row in `user_agreements` table
- Modal dismisses, app continues

---

## Releasing a New Privacy Policy Version

### 1. Update the Document

Edit [PRIVACY_POLICY.md](file:///Users/cagkanacarbay/Projects/whats-that/whats-that-ios/docs/legal/PRIVACY_POLICY.md):
- Update "Effective date"
- Update "Version" number (use semantic versioning: Major.Minor.Patch)
- Make your changes

### 2. Deploy to Website

Ensure updated policy is live at `https://whats-that.app/legal/privacy-policy`

### 3. Add Entry to version_log

```sql
INSERT INTO public.version_log (type, version, message)
VALUES (
  'privacy',
  '1.1.0',  -- Use semantic versioning: Major.Minor.Patch
  'Updated data retention policies and added Fish Audio as TTS provider.'
);
```

---

## Releasing a New App Version

### 1. Decide Update Type

| Type | When to Use | User Experience |
|------|-------------|-----------------|
| `soft` | New features, improvements, non-critical fixes | Reminder at 1/3/7 days, then stops |
| `force` | Security fixes, breaking API changes, critical bugs | 7-day grace, then blocking |

### 2. Submit to App Store

Follow normal App Store submission process.

### 3. Add Entry to version_log (after App Store approval)

**For soft updates:**
```sql
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES (
  'app',
  '1.2.0',
  'New iPad support, improved audio playback, bug fixes.',
  'soft'
);
```

**For force updates:**
```sql
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES (
  'app',
  '1.3.0',
  'Critical security update. Please update immediately.',
  'force'
);
```

> [!NOTE]
> **How force updates work:** The server returns `last_force_version` (the most recent force update version) in the config response. The client compares: if `user_version < last_force_version` → force update required with 7-day grace period.
>
> This means even if you later release v1.4.0 (soft), users on v1.0.0 will still see a force update because `1.0.0 < 1.3.0` (the last_force_version).

**Grace Period Behavior:**
- Users on version < `last_force_version`: 7-day grace period, then blocking
- Users on version < `min_supported_version`: Blocked immediately (no grace period)

> [!IMPORTANT]
> **Grace period does NOT reset with new force versions.** Once a user sees their first force update, the 7-day countdown begins and continues regardless of subsequent force releases. This prevents users from indefinitely delaying updates.

### 4. Set Min Supported Version (Optional - Immediate Block)

If you need to immediately block old versions (e.g., deprecated API), update `app_config`:

```sql
UPDATE public.app_config 
SET min_supported_version = '1.2.0';
```
**Effect:** Any user on version < 1.2.0 will be blocked IMMEDIATELY on next launch (no grace period).

---

## iOS Version Requirements

If a new app version requires a **higher iOS version** than before:

1. **Include this in the `message` field** when inserting into version_log
2. Users on older iOS versions need to know why they can't update

**Example:**
```sql
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES (
  'app',
  '2.0.0',
  'This update requires iOS 17 or later. Please update your device to continue receiving updates.',
  'force'
);
```

> [!NOTE]
> This is an edge case. Most updates don't change iOS requirements. When they do, the message field serves as the communication channel.

---

## Version Numbering

All version types use **Semantic Versioning (Major.Minor.Patch)**:

| Type | Format | Examples |
|------|--------|----------|
| ToS | Major.Minor.Patch | 1.0.0, 1.1.0, 2.0.0 |
| Privacy | Major.Minor.Patch | 1.0.0, 1.1.0, 2.0.0 |
| App | Major.Minor.Patch | 1.0.0, 1.2.3, 2.0.0 |

### Version Comparison

The system uses **semantic version comparison** for all version types:
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

> [!NOTE]
> **Rollbacks are not supported.** The version log is append-only for audit trail integrity.

If you made a mistake (e.g., wrong version number, typo in message):

**Publish a corrected version:**
```sql
-- Example: You accidentally published ToS 1.2.0 but meant 1.1.0
-- Simply publish the correct version as 1.1.0
INSERT INTO public.version_log (type, version, message)
VALUES (
  'tos',
  '1.1.0',  -- Correct version
  'Corrected terms update.'
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
-- Count users who have accepted latest ToS (e.g., 1.1.0)
SELECT COUNT(DISTINCT user_id)
FROM public.user_agreements
WHERE tos_version = '1.1.0';

-- Users who haven't accepted latest ToS
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

> [!TIP]
> Always test new version releases in development first before applying to production.

---

## Post-Implementation: Migrate to Main Docs

After this feature is verified working:

1. [ ] Confirm all deployment steps work in development
2. [ ] Test with real version updates
3. [ ] Move this guide content to main documentation (e.g., `docs/operations/version-management.md`)
4. [ ] Update any CI/CD or release checklists to include version_log steps
