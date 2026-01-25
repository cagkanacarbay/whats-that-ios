# Build & Deploy Guide

Operational notes for the current native iOS migration. This captures the environment wiring and build switches we already rely on today—no future assumptions.

---

## 1. Runtime Environment Configuration

Our Supabase + Google credentials flow from XCConfig files into `Config/AppInfo.plist`, which `AppConfiguration.fromBundle()` reads at runtime.

1. **Select the active environment**
   - `native/Config/Environment.xcconfig` includes exactly one environment profile.
   - By default it points at `native/Config/Environments/Development.xcconfig`.
   - To run against another profile, change the `#include` line to the desired file (e.g., `Production.xcconfig` or a local override).

2. **Provide environment-specific values**
   - `native/Config/Environments/Development.xcconfig` holds the current dev Supabase URL, anon key, and Google client ID.
   - Create a copy for secrets you do not wish to commit:
     ```bash
     cp native/Config/Environments/Development.xcconfig \
        native/Config/Environments/Development.local.xcconfig
     ```
   - Update `Environment.xcconfig` to include the `.local` file. It is gitignored (`native/Config/Environments/*.local.xcconfig`), so local credentials stay private.
   - **Google Sign-In requirement:** ensure the environment file also defines `GOOGLE_REVERSED_CLIENT_ID` (the reversed client ID used for the URL scheme). Without it, Google Sign-In will crash at launch.

3. **What happens under the hood**
   - Build settings set in the environment XCConfig feed into `Config/AppInfo.plist`.
   - The plist ships inside the app bundle, so no additional runtime injection is required.

## 2. Remote Dependencies Toggle (`USE_REMOTE_DEPS`)

SwiftPM packages (Supabase, Google Sign-In, Nuke, etc.) are enabled by default. The manifest treats anything other than `USE_REMOTE_DEPS=0` as "remote deps on".

| Scenario | Action |
| --- | --- |
| Full app with live services (required) | Do nothing. The default includes all remote packages and defines the `USE_REMOTE_DEPS` compile flag. |
| Stubbed/offline build | **Not supported.** Remote dependencies and live Supabase/Google configuration are required; setting `USE_REMOTE_DEPS=0` will cause the app to terminate at launch. |

When Google Sign-In is enabled (default), confirm both `GOOGLE_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID` are populated in the active environment; missing values will cause the sign-in sheet to throw an exception.

**Example (force live deps in Xcode scheme):**
Add an environment variable `USE_REMOTE_DEPS` with value `1` under *Scheme → Run → Environment Variables* if you need to override a shell default.

## 3. Building & Running Today

- **Xcode Workspace:** Open `native/WhatsThatIOS.xcworkspace`. The `WhatsThatIOS` scheme already sets `USE_REMOTE_DEPS=1`.
- **Simulator Run:** Select an iOS 18 simulator (e.g., iPhone 16 Pro) and build/run. On first launch you'll see onboarding → auth → post-onboarding → feed.
- **Command-line Run (MCP tooling or xcodebuild):**
  ```bash
  xcodebuild \
    -workspace native/WhatsThatIOS.xcworkspace \
    -scheme WhatsThatIOS \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
  ```

## 4. Known Credentials Handling

- Test accounts live in `docs/port/test-accounts.md`. Paste locally when exercising auth; do not embed the email/password in XCConfig or plist files.
- Secrets for staging/production should live in their own environment files (`Production.xcconfig`, `Staging.xcconfig`, or private `.local` variants) and be kept out of source control.

## 5. Deployment Notes (Current State)

- We ship one app target (`WhatsThatIOS`). No build automation beyond the standard Xcode scheme is in place yet.
- Any TestFlight or App Store submissions should use a production environment XCConfig with live Supabase/Google credentials and `USE_REMOTE_DEPS` left at its default (enabled).
- Keep `Config/AppInfo.plist` in sync with environment values; if a build ships without Supabase keys the app will now terminate at launch so the misconfiguration is obvious.

## 6. Supabase Database Migrations

Migration files live in `supabase/migrations/`. Follow these conventions:

### Naming Format

Use the **timestamp format** `YYYYMMDDHHMMSS_description.sql`:

```
20260120143000_version_control.sql
20251230002500_create_initial_credit_grants_table.sql
```

- **Timestamp** = date + time in 24-hour format (ensures global uniqueness and correct ordering)
- **Description** = lowercase with underscores, describing the change

> [!IMPORTANT]
> This is Supabase's recommended format. Avoid custom formats like `YYYYMMDD##` which can cause ordering issues with multiple same-day migrations.

### Creating New Migrations

```bash
supabase migration new my_migration_name
```

This auto-generates the timestamp prefix based on current UTC time.

### Applying Migrations

```bash
# Push pending migrations to remote database
supabase db push

# Check migration status
supabase migration list
```

### Already-Applied Migrations

Once a migration is pushed to a remote database, its filename is stored in `supabase_migrations.schema_migrations`. **Do not rename** applied migrations—the new name won't match the recorded history and will cause the migration to re-run or fail.

---

That's the full setup we're running today. Update this document whenever environment includes or build steps change.
