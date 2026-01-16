# Deployment Guide: Releasing New Versions

> [!NOTE]
> **This is a draft guide.** After implementing and testing this feature, verify these steps work correctly, then migrate this content to the main documentation as a standard operating procedure.

---

## Releasing a New ToS Version

### 1. Update the Document

Edit [TERMS_AND_CONDITIONS.md](file:///Users/cagkanacarbay/Projects/whats-that/whats-that-ios/docs/legal/TERMS_AND_CONDITIONS.md):
- Update "Effective date" at the top
- Update "Version" number
- Make your changes

### 2. Deploy to Website

Ensure the updated ToS is live at `https://whats-that.app/legal/terms-and-conditions`

### 3. Add Entry to version_log

**In Supabase SQL Editor (Production):**

```sql
INSERT INTO public.version_log (type, version, message)
VALUES (
  'tos',
  '1.1',  -- Increment from previous version
  'Added section on audio guides and data processing.'
);
```

The `message` field is **optional but recommended** — it will be shown to users in the acceptance modal to explain what changed.

### 4. Verify

- Launch app as a test user who has accepted ToS 1.0
- Should see Legal Acceptance modal with checkbox
- Accept → verify new row in `user_agreements` table
- Modal dismisses, app continues

---

## Releasing a New Privacy Policy Version

### 1. Update the Document

Edit [PRIVACY_POLICY.md](file:///Users/cagkanacarbay/Projects/whats-that/whats-that-ios/docs/legal/PRIVACY_POLICY.md):
- Update "Effective date"
- Update "Version" number
- Make your changes

### 2. Deploy to Website

Ensure updated policy is live at `https://whats-that.app/legal/privacy-policy`

### 3. Add Entry to version_log

```sql
INSERT INTO public.version_log (type, version, message)
VALUES (
  'privacy',
  '1.1',
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

> [!IMPORTANT]
> For force updates, users have 7 days from when they **first see** the update to update before the app blocks them.

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

| Type | Format | Examples |
|------|--------|----------|
| ToS | Major.Minor | 1.0, 1.1, 2.0 |
| Privacy | Major.Minor | 1.0, 1.1, 2.0 |
| App | Semantic (Major.Minor.Patch) | 1.0.0, 1.2.3, 2.0.0 |

---

## Rollback Procedure

If you released a version by mistake:

**Option 1: Delete the entry**
```sql
DELETE FROM public.version_log 
WHERE type = 'app' AND version = '1.3.0';
```

**Option 2: Insert corrected version**
```sql
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES (
  'app',
  '1.2.0',  -- Previous version users have
  'Reverted update requirement.',
  'soft'
);
```

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
-- Count users who have accepted latest ToS (1.1)
SELECT COUNT(DISTINCT user_id) 
FROM public.user_agreements 
WHERE tos_version = '1.1';

-- Users who haven't accepted latest ToS
SELECT DISTINCT ua.user_id
FROM public.user_agreements ua
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_agreements 
  WHERE user_id = ua.user_id AND tos_version = '1.1'
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
