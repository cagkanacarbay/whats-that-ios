-- Migration: Version Control & Compliance System
-- Description: Implements ToS/Privacy tracking and app version control
-- Date: 2026-01-20

-- ============================================
-- 1. CREATE ENUMS
-- ============================================

CREATE TYPE version_type AS ENUM ('tos', 'privacy', 'app');
CREATE TYPE update_type AS ENUM ('soft', 'force');

-- ============================================
-- 2. CREATE version_log TABLE
-- ============================================
-- A log of all version releases (ToS, Privacy, App). Each release creates a new row.

CREATE TABLE public.version_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- What type of version is this?
  type version_type NOT NULL,

  -- Version identifier (e.g., "1.0", "1.1", "2.0.3")
  version TEXT NOT NULL,

  -- Optional message to show users about what changed
  message TEXT,

  -- For app versions only: update behavior
  -- 'soft' = reminder prompts at 1/3/7 days
  -- 'force' = 7-day grace period, then blocking
  app_update_type update_type DEFAULT 'soft',

  -- When this version was released
  released_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for efficient latest-version queries
CREATE INDEX idx_version_log_type_released
  ON public.version_log(type, released_at DESC);

-- RLS: Public read, admin-only write via service_role
ALTER TABLE public.version_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read version log" ON public.version_log
  FOR SELECT USING (true);

-- ============================================
-- 3. CREATE user_agreements TABLE (Audit Log)
-- ============================================
-- A log of all user acceptances. Each acceptance creates a new row for audit trail.

CREATE TABLE public.user_agreements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Which version was accepted
  tos_version TEXT,      -- Non-null if accepting ToS
  privacy_version TEXT,  -- Non-null if accepting Privacy

  -- When this acceptance was recorded
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for efficient lookup of user's latest acceptances
CREATE INDEX idx_user_agreements_user_accepted
  ON public.user_agreements(user_id, accepted_at DESC);

-- Idempotency: Prevent duplicate acceptances for the same user + version combination
-- Uses COALESCE to handle NULL values (treats NULL as empty string for uniqueness)
CREATE UNIQUE INDEX idx_user_agreements_unique_acceptance
  ON public.user_agreements(user_id, COALESCE(tos_version, ''), COALESCE(privacy_version, ''));

ALTER TABLE public.user_agreements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own agreements" ON public.user_agreements
  FOR SELECT USING (auth.uid() = user_id);

-- Note: No direct INSERT policy - we use a database function instead

-- ============================================
-- 4. CREATE app_config TABLE (Global Settings)
-- ============================================
-- A singleton table (one row only) for global configuration.

CREATE TABLE public.app_config (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1), -- Enforce singleton

  -- Minimum app version supported (e.g. "1.2.0")
  -- Clients below this are FORCE BLOCKED immediately
  min_supported_version TEXT NOT NULL DEFAULT '0.0.0',

  -- Maintenance mode: blocks all app usage when TRUE
  maintenance_mode BOOLEAN DEFAULT FALSE,

  -- Optional message to display during maintenance
  maintenance_message TEXT,

  -- Dynamic links
  app_store_url TEXT NOT NULL DEFAULT 'https://apps.apple.com/app/id...',

  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS: Public read-only
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read app_config" ON public.app_config FOR SELECT USING (true);

-- ============================================
-- 5. INITIAL DATA SEED
-- ============================================

-- Insert singleton app_config row
INSERT INTO public.app_config (min_supported_version, app_store_url)
VALUES ('1.0.0', 'https://apps.apple.com/app/id...');

-- Insert initial version log entries
INSERT INTO public.version_log (type, version, message) VALUES
  ('tos', '1.0', 'Initial Terms of Service'),
  ('privacy', '1.0', 'Initial Privacy Policy'),
  ('app', '1.0.0', 'Initial release');

-- ============================================
-- 6. CREATE get_app_config() FUNCTION
-- ============================================
-- Returns the latest versions + user's compliance status.

CREATE OR REPLACE FUNCTION public.get_app_config()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
  current_user_id UUID := auth.uid();

  -- Latest versions from version_log
  latest_tos_version TEXT;
  latest_privacy_version TEXT;

  -- User's accepted versions
  user_tos_version TEXT;
  user_privacy_version TEXT;

  -- App config fields
  config_record RECORD;
BEGIN
  -- Get app config (fail fast if missing)
  SELECT * INTO config_record FROM public.app_config LIMIT 1;
  IF config_record IS NULL THEN
    RAISE EXCEPTION 'App config missing';
  END IF;

  -- Get latest ToS version
  SELECT version INTO latest_tos_version
  FROM public.version_log
  WHERE type = 'tos'
  ORDER BY released_at DESC LIMIT 1;

  -- Get latest Privacy version
  SELECT version INTO latest_privacy_version
  FROM public.version_log
  WHERE type = 'privacy'
  ORDER BY released_at DESC LIMIT 1;

  -- If authenticated, get user's accepted versions
  IF current_user_id IS NOT NULL THEN
    SELECT tos_version INTO user_tos_version
    FROM public.user_agreements
    WHERE user_id = current_user_id AND tos_version IS NOT NULL
    ORDER BY accepted_at DESC LIMIT 1;

    SELECT privacy_version INTO user_privacy_version
    FROM public.user_agreements
    WHERE user_id = current_user_id AND privacy_version IS NOT NULL
    ORDER BY accepted_at DESC LIMIT 1;
  END IF;

  -- Build response
  SELECT json_build_object(
    'maintenance', json_build_object(
      'enabled', config_record.maintenance_mode,
      'message', config_record.maintenance_message
    ),
    'tos', (
      SELECT json_build_object(
        'version', version,
        'message', message,
        'released_at', released_at
      ) FROM public.version_log WHERE type = 'tos' ORDER BY released_at DESC LIMIT 1
    ),
    'privacy', (
      SELECT json_build_object(
        'version', version,
        'message', message,
        'released_at', released_at
      ) FROM public.version_log WHERE type = 'privacy' ORDER BY released_at DESC LIMIT 1
    ),
    'app', (
      SELECT json_build_object(
        'version', v.version,
        'message', v.message,
        'released_at', v.released_at,
        'app_update_type', v.app_update_type,
        'min_supported_version', config_record.min_supported_version,
        'app_store_url', config_record.app_store_url,
        -- Last force version: most recent app version with app_update_type = 'force'
        -- Client compares: if user_version < last_force_version -> force update required
        'last_force_version', (
          SELECT version FROM public.version_log
          WHERE type = 'app' AND app_update_type = 'force'
          ORDER BY released_at DESC LIMIT 1
        )
      )
      FROM public.version_log v
      WHERE v.type = 'app'
      ORDER BY v.released_at DESC LIMIT 1
    ),
    'user_status', CASE
      WHEN current_user_id IS NOT NULL THEN json_build_object(
        -- Strict inequality check. If versions differ, require acceptance.
        'needs_tos_acceptance', (user_tos_version IS NULL OR user_tos_version <> latest_tos_version),
        'needs_privacy_acceptance', (user_privacy_version IS NULL OR user_privacy_version <> latest_privacy_version),
        'accepted_tos_version', user_tos_version,
        'accepted_privacy_version', user_privacy_version
      )
      ELSE NULL
    END
  ) INTO result;

  RETURN result;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.get_app_config() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_config() TO anon;

-- ============================================
-- 7. CREATE accept_terms() FUNCTION
-- ============================================
-- Records user acceptance. Validates that user is applying the LATEST version.

CREATE OR REPLACE FUNCTION public.accept_terms(
  tos_version TEXT DEFAULT NULL,
  privacy_version TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  latest_tos_version TEXT;
  latest_privacy_version TEXT;
  tos_to_insert TEXT := NULL;
  privacy_to_insert TEXT := NULL;
BEGIN
  -- Must be authenticated
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Must accept at least one
  IF tos_version IS NULL AND privacy_version IS NULL THEN
    RAISE EXCEPTION 'Must accept at least one version';
  END IF;

  -- Validate and prepare ToS version
  IF tos_version IS NOT NULL THEN
    SELECT version INTO latest_tos_version
    FROM public.version_log
    WHERE type = 'tos'
    ORDER BY released_at DESC LIMIT 1;

    IF latest_tos_version IS NULL THEN
      RAISE EXCEPTION 'No ToS version found in version_log';
    END IF;

    -- VALIDATION: Ensure user is accepting the LATEST version
    IF tos_version != latest_tos_version THEN
      RAISE EXCEPTION 'Version mismatch: You are trying to accept ToS % but latest is %', tos_version, latest_tos_version;
    END IF;

    tos_to_insert := latest_tos_version;
  END IF;

  -- Validate and prepare Privacy version
  IF privacy_version IS NOT NULL THEN
    SELECT version INTO latest_privacy_version
    FROM public.version_log
    WHERE type = 'privacy'
    ORDER BY released_at DESC LIMIT 1;

    IF latest_privacy_version IS NULL THEN
      RAISE EXCEPTION 'No Privacy Policy version found in version_log';
    END IF;

    -- VALIDATION: Ensure user is accepting the LATEST version
    IF privacy_version != latest_privacy_version THEN
      RAISE EXCEPTION 'Version mismatch: You are trying to accept Privacy % but latest is %', privacy_version, latest_privacy_version;
    END IF;

    privacy_to_insert := latest_privacy_version;
  END IF;

  -- Insert acceptance record (idempotent - ignores duplicates)
  INSERT INTO public.user_agreements (user_id, tos_version, privacy_version)
  VALUES (current_user_id, tos_to_insert, privacy_to_insert)
  ON CONFLICT (user_id, COALESCE(tos_version, ''), COALESCE(privacy_version, '')) DO NOTHING;

  RETURN json_build_object(
    'success', true,
    'accepted_tos_version', tos_to_insert,
    'accepted_privacy_version', privacy_to_insert
  );
END;
$$;

-- Grant execute permissions (authenticated users only)
GRANT EXECUTE ON FUNCTION public.accept_terms(TEXT, TEXT) TO authenticated;

-- ============================================
-- 8. BACKFILL EXISTING USERS (One-Time)
-- ============================================
-- At feature deployment, all existing users need acceptance records for v1.0
-- (they agreed at signup before this feature existed)
--
-- NOTE: Run this AFTER tables are created but BEFORE the iOS app update goes live.
-- This is included here but should be run manually or as a separate step.

-- INSERT INTO public.user_agreements (user_id, tos_version, privacy_version, accepted_at)
-- SELECT id, '1.0', '1.0', NOW()
-- FROM auth.users
-- WHERE id NOT IN (SELECT DISTINCT user_id FROM public.user_agreements);
