-- Migration: Refactor get_app_config to use RETURNS TABLE
-- Description: Changes from RETURNS JSON to RETURNS TABLE so PostgREST properly serializes
--              timestamps as ISO8601. This fixes date parsing errors on iOS.
-- Date: 2026-02-03
--
-- Background: When using RETURNS JSON with json_build_object, PostgreSQL uses its default
-- timestamp text format (e.g., "2026-02-03 12:00:00+00") instead of ISO8601.
-- With RETURNS TABLE and timestamptz columns, PostgREST automatically serializes to ISO8601.

DROP FUNCTION IF EXISTS public.get_app_config();

CREATE OR REPLACE FUNCTION public.get_app_config()
RETURNS TABLE (
  -- Maintenance
  maintenance_enabled boolean,
  maintenance_message text,
  -- ToS
  tos_version text,
  tos_message text,
  tos_released_at timestamptz,
  -- Privacy
  privacy_version text,
  privacy_message text,
  privacy_released_at timestamptz,
  -- App
  app_version text,
  app_message text,
  app_released_at timestamptz,
  app_update_type text,
  min_supported_version text,
  app_store_url text,
  last_force_version text,
  last_force_message text,
  -- User status (null values when not authenticated)
  needs_tos_acceptance boolean,
  needs_privacy_acceptance boolean,
  accepted_tos_version text,
  accepted_privacy_version text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  current_user_id UUID := auth.uid();

  -- Latest versions from version_log
  v_latest_tos_version TEXT;
  v_latest_privacy_version TEXT;

  -- User's accepted versions
  v_user_tos_version TEXT;
  v_user_privacy_version TEXT;

  -- App config record
  v_config RECORD;

  -- Version records
  v_tos RECORD;
  v_privacy RECORD;
  v_app RECORD;
  v_last_force RECORD;
BEGIN
  -- Get app config (fail fast if missing)
  SELECT * INTO v_config FROM public.app_config LIMIT 1;
  IF v_config IS NULL THEN
    RAISE EXCEPTION 'App config missing';
  END IF;

  -- Get latest ToS version info
  SELECT vl.version, vl.message, vl.released_at INTO v_tos
  FROM public.version_log vl
  WHERE vl.type = 'tos'
  ORDER BY vl.released_at DESC LIMIT 1;

  v_latest_tos_version := v_tos.version;

  -- Get latest Privacy version info
  SELECT vl.version, vl.message, vl.released_at INTO v_privacy
  FROM public.version_log vl
  WHERE vl.type = 'privacy'
  ORDER BY vl.released_at DESC LIMIT 1;

  v_latest_privacy_version := v_privacy.version;

  -- Get latest App version info
  SELECT vl.version, vl.message, vl.released_at, vl.app_update_type INTO v_app
  FROM public.version_log vl
  WHERE vl.type = 'app'
  ORDER BY vl.released_at DESC LIMIT 1;

  -- Get last force version info
  SELECT vl.version, vl.message INTO v_last_force
  FROM public.version_log vl
  WHERE vl.type = 'app' AND vl.app_update_type = 'force'
  ORDER BY vl.released_at DESC LIMIT 1;

  -- If authenticated, get user's accepted versions
  IF current_user_id IS NOT NULL THEN
    SELECT ua.tos_version INTO v_user_tos_version
    FROM public.user_agreements ua
    WHERE ua.user_id = current_user_id AND ua.tos_version IS NOT NULL
    ORDER BY ua.accepted_at DESC LIMIT 1;

    SELECT ua.privacy_version INTO v_user_privacy_version
    FROM public.user_agreements ua
    WHERE ua.user_id = current_user_id AND ua.privacy_version IS NOT NULL
    ORDER BY ua.accepted_at DESC LIMIT 1;
  END IF;

  -- Return single row with all config data
  -- Note: Column names must match RETURNS TABLE definition exactly
  maintenance_enabled := v_config.maintenance_mode;
  maintenance_message := v_config.maintenance_message;
  tos_version := v_tos.version;
  tos_message := v_tos.message;
  tos_released_at := v_tos.released_at;
  privacy_version := v_privacy.version;
  privacy_message := v_privacy.message;
  privacy_released_at := v_privacy.released_at;
  app_version := v_app.version;
  app_message := v_app.message;
  app_released_at := v_app.released_at;
  app_update_type := v_app.app_update_type::text;
  min_supported_version := v_config.min_supported_version;
  app_store_url := v_config.app_store_url;
  last_force_version := v_last_force.version;
  last_force_message := v_last_force.message;
  needs_tos_acceptance := CASE WHEN current_user_id IS NOT NULL
    THEN (v_user_tos_version IS NULL OR v_user_tos_version <> v_latest_tos_version)
    ELSE NULL
  END;
  needs_privacy_acceptance := CASE WHEN current_user_id IS NOT NULL
    THEN (v_user_privacy_version IS NULL OR v_user_privacy_version <> v_latest_privacy_version)
    ELSE NULL
  END;
  accepted_tos_version := v_user_tos_version;
  accepted_privacy_version := v_user_privacy_version;

  RETURN NEXT;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.get_app_config() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_config() TO anon;
