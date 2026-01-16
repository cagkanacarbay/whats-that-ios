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

- Config cached in UserDefaults for **24 hours**
- Reduces unnecessary network calls
- Falls back to expired cache if network fails

### App Flow

```
App Launch
    ↓
Check for pending acceptance → Submit if exists
    ↓
Load app content normally (non-blocking)
    ↓
Background: Check cache (24h) or fetch config
    ↓
Check user_status.needs_tos/privacy_acceptance
    ↓
┌─────────────────────────────────────────┐
│ If ToS/Privacy updated:                  │
│   → Show modal with checkbox             │
│   → User MUST tick + accept              │
│   → Store pending immediately            │
│   → Dismiss modal immediately            │
│   → Background: Retry 5x over 15 min     │
├─────────────────────────────────────────┤
│ If App version updated:                  │
│   → Soft: Remind at 1/3/7 days (local)  │
│   → Force: 7-day grace from first seen   │
└─────────────────────────────────────────┘
    ↓
Continue to main app
```

## Status

- [ ] Database schema created
- [ ] Database functions deployed
- [ ] iOS implementation complete
- [ ] Testing verified
- [ ] Deployment guide verified and migrated to main docs
