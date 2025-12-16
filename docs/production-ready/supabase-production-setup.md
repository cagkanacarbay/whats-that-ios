# Production Setup Checklist

Checklist for promoting the current development Supabase project to production for **v1.0 release**.

> [!NOTE]
> This approach promotes your existing dev database to production. A separate dev environment should be created afterward — see [dev-environment-setup.md](file:///Users/cagkanacarbay/Projects/whats-that/whats-that-ios/docs/production-ready/dev-environment-setup.md).

---

## 1. Edge Function Secrets

Update the 4 secrets that need to change for production:

```bash
supabase secrets set \
  DENO_ENV=production \
  LOG_LEVEL=info \
  APNS_ENVIRONMENT=production \
  ALLOWED_ORIGINS=https://whats-that.app
```

- [x] `DENO_ENV` = `production`
- [x] `LOG_LEVEL` = `info`
- [x] `APNS_ENVIRONMENT` = `production`
- [x] `ALLOWED_ORIGINS` = `https://whats-that.app`

---

## 2. Redeploy Edge Functions

```bash
supabase functions deploy ask-ai-v7
supabase functions deploy generate-voiceover
supabase functions deploy validate-receipt
supabase functions deploy nearby-places
supabase functions deploy shared-discovery --no-verify-jwt
```

- [x] `ask-ai-v7` deployed
- [x] `generate-voiceover` deployed
- [x] `validate-receipt` deployed
- [x] `nearby-places` deployed
- [x] `shared-discovery` deployed

---

## 3. Database Cleanup (Optional - Do Later)

Remove test data before go-live:

```sql
TRUNCATE public.discoveries CASCADE;
TRUNCATE public.credit_transactions CASCADE;
TRUNCATE public.user_credits CASCADE;
TRUNCATE public.push_tokens CASCADE;
TRUNCATE public.discovery_voiceovers CASCADE;
DELETE FROM auth.users WHERE email LIKE '%test%';
```

- [ ] Test discoveries deleted
- [ ] Test users deleted

---

## 4. Storage Cleanup (Optional - Do Later)

- [ ] `discovery_images` — delete test uploads
- [ ] `voiceovers` — delete test audio files

---

## 5. Auth Providers

### Email/Password
- [x] Enabled ✓

### Apple Sign-In
- [x] Services ID = `app.whatsthat.ios`
- [x] Key ID = Configured
- [x] Team ID = Configured
- [x] Private Key (.p8) = Configured

### Google Sign-In
- [ ] Bundle ID updated in Google Cloud Console to `app.whatsthat.ios`
- [ ] Test with Release/TestFlight build

---

## 6. iOS App Configuration

### Version Numbers
- [x] `Shared.xcconfig` → `MARKETING_VERSION = 1.0`
- [x] `project.pbxproj` → `MARKETING_VERSION = 1.0` (both Debug and Release)
- [x] `CURRENT_PROJECT_VERSION` = `2` (or increment as needed)

### Production xcconfig
- [x] Supabase URL points to production project
- [x] Supabase anon key is correct
- [x] Google client IDs configured

### APNs Entitlement
- [ ] Verify `aps-environment = production` after archiving

---

## 7. Pre-Submission Testing

Run on physical device with **Release** configuration:

- [ ] App launches successfully
- [ ] Sign up / Sign in works
- [ ] Apple Sign-In works
- [ ] Google Sign-In works
- [ ] Discovery creation works
- [ ] Push notification received
- [ ] Voiceover generation works
- [ ] In-app purchase flow works

---

## 8. Ready for App Store

- [ ] All tests passed
- [ ] Archive and upload to App Store Connect
- [ ] Submit for review
