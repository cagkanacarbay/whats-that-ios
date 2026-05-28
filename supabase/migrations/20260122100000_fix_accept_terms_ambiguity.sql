-- Migration: Fix accept_terms column ambiguity
-- Description: Renames function parameters to avoid ambiguity with table column names
-- Date: 2026-01-22
-- Issue: PostgreSQL error "column reference 'tos_version' is ambiguous" when calling accept_terms()

-- ============================================
-- 1. DROP EXISTING FUNCTION
-- ============================================
-- Drop the old function to replace it with fixed version
DROP FUNCTION IF EXISTS public.accept_terms(TEXT, TEXT);

-- ============================================
-- 2. CREATE FIXED accept_terms() FUNCTION
-- ============================================
-- Parameters renamed from tos_version/privacy_version to p_tos_version/p_privacy_version
-- to avoid ambiguity with user_agreements table columns in ON CONFLICT clause

CREATE OR REPLACE FUNCTION public.accept_terms(
  p_tos_version TEXT DEFAULT NULL,
  p_privacy_version TEXT DEFAULT NULL
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
  IF p_tos_version IS NULL AND p_privacy_version IS NULL THEN
    RAISE EXCEPTION 'Must accept at least one version';
  END IF;

  -- Validate and prepare ToS version
  IF p_tos_version IS NOT NULL THEN
    SELECT version INTO latest_tos_version
    FROM public.version_log
    WHERE type = 'tos'
    ORDER BY released_at DESC LIMIT 1;

    IF latest_tos_version IS NULL THEN
      RAISE EXCEPTION 'No ToS version found in version_log';
    END IF;

    -- VALIDATION: Ensure user is accepting the LATEST version
    IF p_tos_version != latest_tos_version THEN
      RAISE EXCEPTION 'Version mismatch: You are trying to accept ToS % but latest is %', p_tos_version, latest_tos_version;
    END IF;

    tos_to_insert := latest_tos_version;
  END IF;

  -- Validate and prepare Privacy version
  IF p_privacy_version IS NOT NULL THEN
    SELECT version INTO latest_privacy_version
    FROM public.version_log
    WHERE type = 'privacy'
    ORDER BY released_at DESC LIMIT 1;

    IF latest_privacy_version IS NULL THEN
      RAISE EXCEPTION 'No Privacy Policy version found in version_log';
    END IF;

    -- VALIDATION: Ensure user is accepting the LATEST version
    IF p_privacy_version != latest_privacy_version THEN
      RAISE EXCEPTION 'Version mismatch: You are trying to accept Privacy % but latest is %', p_privacy_version, latest_privacy_version;
    END IF;

    privacy_to_insert := latest_privacy_version;
  END IF;

  -- Insert acceptance record (idempotent - ignores duplicates)
  -- Note: tos_version and privacy_version here refer to table columns (no longer ambiguous)
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

-- ============================================
-- 3. GRANT PERMISSIONS
-- ============================================
GRANT EXECUTE ON FUNCTION public.accept_terms(TEXT, TEXT) TO authenticated;
