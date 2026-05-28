# App Updates Guide

This guide covers how to release app updates and communicate changes to users through the version control system.

## Overview

When releasing a new app version, you can include a message that displays to users in the update prompt. This message supports **Markdown formatting** including:
- Bullet points (unordered lists)
- Numbered lists
- **Bold text**

## Releasing an Update

### 1. Create a Migration File

Create a new SQL migration file in `supabase/migrations/` with a timestamp prefix:

```
supabase/migrations/YYYYMMDDHHMMSS_app_version_X_X_X.sql
```

Example: `supabase/migrations/20260202120000_app_version_1_1_0.sql`

### 2. Write the Migration SQL

Use the following template:

```sql
-- App Version X.X.X Release
-- Description: Brief description of this release

INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES (
    'app',
    'X.X.X',
    $$What's new in this update:

- **Feature 1** - Description of feature
- **Feature 2** - Description of feature
- **Bug fixes** - What was fixed

Why update:

1. First reason
2. Second reason$$,
    'soft'  -- or 'force'
);
```

### 3. Update Types

| Type | Behavior |
|------|----------|
| `soft` | Shows dismissible update prompt. Reminds at 1, 3, 7 days. |
| `force` | 7-day grace period, then blocks app until updated. |

### 4. Message Formatting

The message field supports Markdown. Use:
- `- Item` for bullet points
- `1. Item` for numbered lists
- `**text**` for bold
- Blank lines between sections

**Note:** Use `$$` dollar-quoted strings for multi-line messages in PostgreSQL. This handles apostrophes and special characters automatically.

### 5. Deploy the Migration

```bash
# For development
supabase db push --linked

# For production
supabase db push --linked --db-url <production-url>
```

## Example Migrations

### Soft Update (Optional)

```sql
-- App Version 1.1.0 - Feature Update

INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '1.1.0', $$What's new:

- **Improved performance** - Faster loading times
- **Bug fixes** - Resolved audio playback issues
- **New features** - Enhanced discovery accuracy$$, 'soft');
```

### Force Update (Required)

```sql
-- App Version 2.0.0 - Breaking Changes

INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '2.0.0', $$Important update required:

- **Security patches** - Critical fixes for your protection
- **New architecture** - Improved stability
- **API changes** - Required for continued service

You have 7 days to update before this becomes mandatory.$$, 'force');
```

### Minimal Update (No Message)

```sql
-- App Version 1.0.1 - Patch

INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '1.0.1', NULL, 'soft');
```

## Testing Updates

1. Insert a test version higher than your current app version
2. Restart the app or return from background after 1 hour
3. Verify the update prompt appears with correct formatting

To test markdown formatting, use a message like:

```sql
$$What's new in this update:

- **Improved performance** - Faster loading times and smoother animations
- **Bug fixes** - Resolved issues with image uploads and audio playback
- **New discovery features** - Enhanced object recognition accuracy
- **Better accessibility** - Improved VoiceOver support throughout the app

Why you should update:

1. Security patches for your protection
2. Compatibility with the latest iOS features
3. Reduced battery consumption
4. Smaller app size$$
```

## Related Documentation

- [Version Control System](../features/07-version-control/README.md)
- [Deployment Guide](../features/07-version-control/deployment-guide.md)
