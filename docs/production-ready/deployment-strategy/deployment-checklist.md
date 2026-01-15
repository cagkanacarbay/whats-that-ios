# Safe Deployment Process

This checklist ensures you deploy changes safely without breaking existing users.

## The Golden Rule

> **Backend changes go first, app changes go second.**

Never deploy an app that requires a backend change that hasn't happened yet.

```
┌──────────────────────────────────────────────────────────────────────┐
│                        DEPLOYMENT ORDER                               │
│                                                                       │
│   1. Database migrations  ──►  2. Edge functions  ──►  3. App update │
│                                                                       │
│   (Each step must be backwards compatible with current app versions) │
└──────────────────────────────────────────────────────────────────────┘
```

## Full Deployment Checklist

### Phase 1: Development & Testing

- [ ] **Feature complete** on development branch
- [ ] **Unit tests** pass locally
- [ ] **Build succeeds** for both Debug and Release schemes

#### Database Changes (if any)
- [ ] Migration written and tested on dev database
- [ ] Verified backwards compatibility (old app still works)
- [ ] Verified new functionality works with new app

#### Edge Function Changes (if any)
- [ ] Function tested locally with `supabase functions serve`
- [ ] Deployed to development Supabase project
- [ ] Tested with Debug TestFlight build

#### iOS App Changes
- [ ] Debug build uploaded to TestFlight
- [ ] Tested on real devices (iPhone + iPad)
- [ ] No crashes or critical bugs

---

### Phase 2: Production Backend Deployment

> [!IMPORTANT]
> Deploy backend changes BEFORE submitting app update!

#### Database Migration
- [ ] **Backup verified** - Check Supabase PITR is enabled
- [ ] **Low-traffic window** chosen for migration
- [ ] Run migration on production:
  ```bash
  supabase db push --project-ref vipghlhvnrdheoydynty
  ```
- [ ] **Verify migration** - Check schema in Supabase dashboard
- [ ] **Test old app** - Confirm current App Store version still works
- [ ] **Monitor** for 15+ minutes for any errors

#### Edge Functions
- [ ] Deploy to production:
  ```bash
  supabase functions deploy [function-name] --project-ref vipghlhvnrdheoydynty
  ```
- [ ] **Test old app** - Confirm current App Store version still works
- [ ] **Check logs** for errors:
  ```bash
  supabase functions logs [function-name] --project-ref vipghlhvnrdheoydynty
  ```

---

### Phase 3: App Submission

- [ ] **Merge** to main branch
- [ ] **Build Release** scheme in Xcode
- [ ] **Archive** and upload to App Store Connect
- [ ] **TestFlight** - Test Release build one final time
- [ ] **Submit for Review**
- [ ] **Release** when approved

---

### Phase 4: Post-Release Monitoring

- [ ] **Monitor crash reports** in App Store Connect / Xcode
- [ ] **Monitor edge function logs** for new error patterns
- [ ] **Monitor user feedback** in App Store reviews
- [ ] **Check analytics** for unexpected drops in engagement

---

## Quick Reference: Common Scenarios

### Scenario A: UI-only change (no backend)
Skip Phase 2 entirely. Just build, test, and submit.

### Scenario B: New feature with database + edge function
Full checklist. Deploy database first, then edge function, then app.

### Scenario C: Bug fix in edge function only
Deploy edge function to production. No app update needed.

### Scenario D: Hotfix for critical iOS bug
Fast-track Phase 1 testing, skip Phase 2 (no backend changes), expedite submission.

---

## Rollback Procedures

### If Edge Function Breaks
```bash
# Find previous version in git
git log --oneline supabase/functions/[function-name]

# Checkout and redeploy
git checkout [commit] -- supabase/functions/[function-name]
supabase functions deploy [function-name] --project-ref vipghlhvnrdheoydynty
```

### If Database Migration Breaks
- Enable Supabase PITR (Point-in-Time Recovery) BEFORE you need it
- Contact Supabase support for restoration if needed
- Write a reverse migration if possible

### If App Update Breaks
- You cannot force users to downgrade
- Submit a hotfix ASAP
- Use App Store Connect to pause availability while fixing

---

## Emergency Contacts

| Issue | Action |
|-------|--------|
| Supabase down | Check [status.supabase.com](https://status.supabase.com) |
| Database corruption | Supabase support + PITR restoration |
| Edge function failing | Roll back via git + redeploy |
| App crashing | Hotfix + expedited review request |
| StoreKit/IAP issues | [Apple Developer Support](https://developer.apple.com/support/) |
