# Version Control & Compliance System

This feature implements two core systems:
1. **Legal Compliance Tracking** - ToS and Privacy Policy version acceptance (explicit checkbox required)
2. **App Version Control** - Soft reminders and force update blocking

## Documentation

| Document | Purpose |
|----------|---------|
| [Implementation Plan](./implementation-plan.md) | Technical architecture and database schema |
| [UI Requirements](./ui-requirements.md) | Screen designs and user flows |
| [Deployment Guide](./deployment-guide.md) | How to release new versions (DRAFT - verify then migrate to main docs) |

## Quick Reference

### Database Tables

- **`version_log`** - Log of all ToS, Privacy, and App version releases (each release = new row)
- **`user_agreements`** - Audit log of user acceptances (each acceptance = new row)

### Database Functions

- **`get_app_config()`** - Returns latest versions + user's compliance status (called via `supabase.rpc()`)
- **`accept_terms(accept_tos, accept_privacy)`** - Records acceptance of LATEST versions (validates server-side)

### Client-Side Caching

- Config cached in memory with **1-hour staleness check**
- Fresh fetch on every app launch
- On foreground resume: refresh if config > 1 hour old
- Maintenance mode cached for 3 hours to survive fetch failures
- No repeated network calls during active use

### App Flow

```
App Launch
    ↓
Load app content normally (non-blocking)
    ↓
Background: Fetch config (fresh on every launch)
    ↓
Check blocking conditions (maintenance, min_supported_version)
    ↓
If blocking → Show blocking screen immediately
    ↓
Check user_status.needs_tos/privacy_acceptance
    ↓
┌─────────────────────────────────────────┐
│ If ToS/Privacy updated:                  │
│   → Wait for safe screen (Home/Settings)│
│   → Wait for onboarding to complete     │
│   → Show modal with checkbox             │
│   → User MUST tick + accept              │
│   → Retry up to 3x automatically        │
│   → On failure: Show error, user retries│
│   → Modal stays open until confirmed    │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ If App version updated:                  │
│   → Soft: Remind at 1/3/7 days (local)  │
│   → Force: 7-day grace from first seen   │
│   → Force (Expired/Min Supported): Block │
└─────────────────────────────────────────┘
```

## Status

- [ ] Database schema created
- [ ] Database functions deployed
- [ ] iOS implementation complete
- [ ] Testing verified
- [ ] Deployment guide verified and migrated to main docs
