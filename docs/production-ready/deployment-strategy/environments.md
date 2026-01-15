# Environment Strategy: The Hybrid Approach

This document defines our Development and Production environment strategy for the What's That iOS app.

## Overview

We use a **Hybrid Approach** that balances development flexibility with production reliability:

| Build Type | Database | Use Case |
|------------|----------|----------|
| Xcode Debug | Development | Local development and testing |
| TestFlight (Development Builds) | Development | Feature testing with testers |
| TestFlight (Release Builds) | Production | Final pre-release validation |
| App Store | Production | Live users |

## Supabase Projects

| Environment | Project Name | Project ID | Region |
|-------------|--------------|------------|--------|
| Production | `whats-that` | `vipghlhvnrdheoydynty` | eu-central-1 |
| Development | `whats-that-dev` | `vibcgzetgbjgmaigixmh` | ap-south-1 |

> [!NOTE]
> The dev project is in a different region. Consider creating a new dev project in eu-central-1 for consistency if latency becomes noticeable during testing.

## iOS Configuration

Environment is controlled via Xcode configuration files:

```
native/Config/Environments/
├── Development.xcconfig  → Dev Supabase project
├── Production.xcconfig   → Prod Supabase project
└── Example.xcconfig      → Template (checked into git)
```

### How It Works

1. **Debug scheme** reads from `Development.xcconfig`
2. **Release scheme** reads from `Production.xcconfig`
3. When you archive for TestFlight, it uses the scheme you built with

### Switching TestFlight Between Environments

```bash
# For development testing (TestFlight → Dev DB)
1. Select "Debug" scheme in Xcode
2. Archive and upload to TestFlight
3. Testers get builds hitting the dev database

# For final production validation (TestFlight → Prod DB)
1. Select "Release" scheme in Xcode
2. Archive and upload to TestFlight
3. Same build can be promoted to App Store
```

## When to Use Each Environment

### Development Database
- ✅ Building new features
- ✅ Testing database schema changes
- ✅ Testing edge function changes
- ✅ Internal team testing
- ✅ Destructive testing (delete data, stress test)

### Production Database
- ✅ Final validation before App Store release
- ✅ Live users from App Store
- ❌ Never for active development
- ❌ Never for destructive testing

## TestFlight Management

### Expiring Old Builds

When switching from production to development for TestFlight:

1. Go to App Store Connect → TestFlight
2. Find builds pointing to production
3. Click "Expire Build" to prevent new installs
4. Upload new Debug build pointing to dev

### Communicating with Testers

When switching environments, notify testers:
- Their discoveries from the old environment won't appear
- This is a fresh testing environment
- They can create new test discoveries

## Edge Function Secrets Per Environment

Each Supabase project needs its own secrets configured:

```bash
# Development
supabase functions secrets set --project-ref vibcgzetgbjgmaigixmh \
  DENO_ENV=development \
  LOG_LEVEL=debug \
  ALLOWED_ORIGINS="http://localhost:5173,https://whats-that.app"

# Production  
supabase functions secrets set --project-ref vipghlhvnrdheoydynty \
  DENO_ENV=production \
  LOG_LEVEL=info \
  ALLOWED_ORIGINS="https://whats-that.app"
```

## Data Considerations

### Production Data Cutoff Date

All data created before the official App Store launch date can be considered "development data" from TestFlight testers. After launch:
- New users = real production users
- Pre-launch data = beta tester data (keep or archive as desired)

### Never Copy Production → Development

Avoid syncing production data to development:
- Privacy concerns with real user data
- Dev testing should use synthetic data
- Production data volumes may be too large

## Checklist: Setting Up Development Environment

- [ ] Activate `whats-that-dev` Supabase project (or create new one)
- [ ] Apply all migrations to dev database
- [ ] Deploy all edge functions to dev project
- [ ] Set edge function secrets for dev
- [ ] Update `Development.xcconfig` with dev project credentials
- [ ] Verify `Production.xcconfig` has production credentials
- [ ] Test Debug build locally against dev database
- [ ] Upload Debug build to TestFlight
- [ ] Expire old TestFlight builds pointing to production
