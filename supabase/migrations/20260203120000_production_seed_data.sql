-- Production Seed Data for Version Control System
-- Date: 2026-02-03
--
-- This migration prepares the database for production deployment:
-- 1. Fixes version formats to proper semver (1.0 -> 1.0.0)
-- 2. Sets correct app versions (1.0.4 initial, 1.0.5 current)
-- 3. Backfills existing users with acceptance records dated at signup
-- 4. Configures minimum supported version

-- ============================================
-- 1. FIX VERSION FORMATS (semver compliance)
-- ============================================

-- Update ToS version from '1.0' to '1.0.0'
UPDATE public.version_log
SET version = '1.0.0'
WHERE type = 'tos' AND version = '1.0';

-- Update Privacy version from '1.0' to '1.0.0'
UPDATE public.version_log
SET version = '1.0.0'
WHERE type = 'privacy' AND version = '1.0';

-- ============================================
-- 2. SET CORRECT APP VERSIONS
-- ============================================

-- Update initial app version from '1.0.0' to '1.0.4' (actual first production release)
UPDATE public.version_log
SET version = '1.0.4', message = 'Initial production release'
WHERE type = 'app' AND version = '1.0.0';

-- Insert app version 1.0.5 (the version with version control system)
INSERT INTO public.version_log (type, version, message, app_update_type)
VALUES ('app', '1.0.5', 'Version control system and improvements', 'force');

-- ============================================
-- 3. BACKFILL EXISTING USERS
-- ============================================
-- All existing users agreed to ToS/Privacy 1.0.0 at signup.
-- Set their accepted_at to their account creation date.

INSERT INTO public.user_agreements (user_id, tos_version, privacy_version, accepted_at)
SELECT id, '1.0.0', '1.0.0', created_at
FROM auth.users
WHERE id NOT IN (SELECT DISTINCT user_id FROM public.user_agreements);

-- ============================================
-- 4. CONFIGURE MINIMUM SUPPORTED VERSION
-- ============================================
-- Set min_supported_version to 1.0.5
-- Note: 1.0.4 users don't have version control, so this only affects 1.0.5+ clients

UPDATE public.app_config
SET min_supported_version = '1.0.5';
