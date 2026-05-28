-- Migration: Semantic Version Comparison for ToS/Privacy
-- Description: Adds semantic versioning support (Major.Minor.Patch) for ToS and Privacy versions
-- Date: 2026-01-31

-- ============================================
-- 1. CREATE VERSION COMPARISON FUNCTIONS
-- ============================================

-- Helper function: Compare two semantic versions
-- Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2
CREATE OR REPLACE FUNCTION public.compare_versions(v1 TEXT, v2 TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v1_parts INTEGER[];
  v2_parts INTEGER[];
  max_length INTEGER;
  i INTEGER;
BEGIN
  -- Handle nulls
  IF v1 IS NULL AND v2 IS NULL THEN RETURN 0; END IF;
  IF v1 IS NULL THEN RETURN -1; END IF;
  IF v2 IS NULL THEN RETURN 1; END IF;

  -- Split versions into integer arrays
  v1_parts := string_to_array(v1, '.')::INTEGER[];
  v2_parts := string_to_array(v2, '.')::INTEGER[];

  -- Pad shorter array with zeros
  max_length := GREATEST(array_length(v1_parts, 1), array_length(v2_parts, 1));

  WHILE array_length(v1_parts, 1) < max_length LOOP
    v1_parts := array_append(v1_parts, 0);
  END LOOP;

  WHILE array_length(v2_parts, 1) < max_length LOOP
    v2_parts := array_append(v2_parts, 0);
  END LOOP;

  -- Compare component by component
  FOR i IN 1..max_length LOOP
    IF v1_parts[i] < v2_parts[i] THEN RETURN -1; END IF;
    IF v1_parts[i] > v2_parts[i] THEN RETURN 1; END IF;
  END LOOP;

  RETURN 0; -- Equal
END;
$$;

-- Helper function: Check if v1 < v2
CREATE OR REPLACE FUNCTION public.version_less_than(v1 TEXT, v2 TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN public.compare_versions(v1, v2) < 0;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.compare_versions(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compare_versions(TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.version_less_than(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.version_less_than(TEXT, TEXT) TO anon;

-- ============================================
-- 2. UPDATE get_app_config() TO USE SEMANTIC COMPARISON
-- ============================================

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
        -- Semantic version comparison: needs acceptance if user version < latest version
        'needs_tos_acceptance', (user_tos_version IS NULL OR public.version_less_than(user_tos_version, latest_tos_version)),
        'needs_privacy_acceptance', (user_privacy_version IS NULL OR public.version_less_than(user_privacy_version, latest_privacy_version)),
        'accepted_tos_version', user_tos_version,
        'accepted_privacy_version', user_privacy_version
      )
      ELSE NULL
    END
  ) INTO result;

  RETURN result;
END;
$$;

-- ============================================
-- 3. UPDATE SEED DATA TO USE SEMANTIC VERSIONING
-- ============================================

-- Update existing version_log entries to use Major.Minor.Patch format
UPDATE public.version_log SET version = '1.0.0' WHERE type = 'tos' AND version = '1.0';
UPDATE public.version_log SET version = '1.0.0' WHERE type = 'privacy' AND version = '1.0';

-- Update existing user_agreements to use Major.Minor.Patch format
UPDATE public.user_agreements SET tos_version = '1.0.0' WHERE tos_version = '1.0';
UPDATE public.user_agreements SET privacy_version = '1.0.0' WHERE privacy_version = '1.0';
