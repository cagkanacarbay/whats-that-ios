-- Migration: Add last_force_message to get_app_config response
-- Description: Fixes Force→Soft scenario where force grace screen showed soft message
-- Date: 2026-02-03

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
        ),
        -- Last force message: message from the most recent force version
        -- Used to show WHY the force update is required (even if a soft version was released after)
        'last_force_message', (
          SELECT message FROM public.version_log
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
