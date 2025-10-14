# Test Accounts & Auth Configuration

Use this checklist whenever we need to exercise live Supabase authentication or discovery data from the native client.

Test user: cagkanacarbay@gmail.com
Test user password: Hello12345

---

## 1. Prerequisites
- [ ] Supabase project credentials are available (URL + anon key).
- [ ] Google OAuth is optional; only email/password auth is required for the current milestone.
- [ ] `USE_REMOTE_DEPS=1` is set in the environment or Xcode scheme so the Supabase SDK compiles.

## 2. Configure Runtime Secrets
1. Copy `native/Config/Shared.xcconfig` → `native/Config/Shared.local.xcconfig` (ignored by git).
2. Add the following and populate them from 1Password / team vault:
   ```
   SUPABASE_URL = https://<project>.supabase.co
   SUPABASE_ANON_KEY = <anon-key>
   GOOGLE_CLIENT_ID = <optional>
   ```
3. In Xcode, edit the `WhatsThatIOS` scheme → *Run* → *Arguments* → add environment variable `USE_REMOTE_DEPS` with value `1`.
4. Point the scheme to consume `Shared.local.xcconfig` (Xcode will overlay it automatically once the file exists).

## 3. Test Account Directory
Record disposable QA credentials here so the team can swap between accounts quickly:

| Label | Email | Password | Notes |
| ----- | ----- | -------- | ----- |
| `qa-discovery-smoke` | `TODO` | `TODO` | Primary smoke-test account shared with React Native app. |

> ⚠️ **Never** commit plain text credentials. Keep the table filled with placeholders if the repo is public; store the real values in the secrets manager and paste locally when running the app.

## 4. Launch & Login
1. Run `SWIFT_MODULECACHE_PATH=.build/modulecache CLANG_MODULE_CACHE_PATH=.build/modulecache USE_REMOTE_DEPS=1 swift test` to validate the Supabase-enabled build.
2. Install/launch the app via Xcode or the MCP command:
   ```
   USE_REMOTE_DEPS=1 SUPABASE_URL=... SUPABASE_ANON_KEY=... \
   XcodeBuildMCP__build_run_sim({ ... })
   ```
3. From the authentication screen, enter the test account email/password.
4. After successful login, verify the discoveries grid loads real data (images + highlights) and matches the React Native layout.

## 5. Troubleshooting
- **Auth fails immediately** – confirm the Supabase URL/key are spelled correctly and the anon key has not been rotated.
- **Images don’t load** – ensure the Supabase bucket `discovery_images` contains assets for the signed URL requested and the account has access; clearing the simulator cache may help.
- **Build fails with Supabase symbols missing** – double-check `USE_REMOTE_DEPS` is set for both build *and* test actions.

Update this document whenever credentials rotate or additional QA personas are added.
