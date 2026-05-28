-- App Version 1.0.7 Release
-- Type: soft
-- Date: 2026-02-20

INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES (
    'app',
    '1.0.7',
    $$What's new in this update:

- **UI improvements** - Cleaner sign-up flow and credit balance tracking
- **Bug fixes** - Fixed issues with credit syncing and email verification
- **Loading screen personality** - Discovery generation now comes with 85+ quirky messages$$,
    'soft'
);
