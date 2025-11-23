-- Recreate get_discovery_voiceovers with explicit aliases to avoid ambiguous columns
DROP FUNCTION IF EXISTS public.get_discovery_voiceovers(bigint[]);
CREATE OR REPLACE FUNCTION public.get_discovery_voiceovers(p_discovery_ids bigint[])
RETURNS TABLE (
  id bigint,
  discovery_id bigint,
  user_id uuid,
  provider text,
  tts_model text,
  voice_model_id text,
  file_name text,
  file_extension text,
  status text,
  error_reason text,
  requested_at timestamptz,
  updated_at timestamptz,
  audio_url text,
  audio_url_expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_ttl_seconds integer := 604800; -- 7d
  v_bucket_id uuid;
BEGIN
  SELECT b.id INTO v_bucket_id FROM storage.buckets AS b WHERE b.name = 'voiceovers' LIMIT 1;
  IF v_bucket_id IS NULL THEN
    RAISE EXCEPTION 'voiceovers bucket not found';
  END IF;

  RETURN QUERY
  SELECT
    dv.id AS id,
    dv.discovery_id,
    dv.user_id,
    dv.provider,
    dv.tts_model,
    dv.voice_model_id,
    dv.file_name,
    dv.file_extension,
    dv.status,
    dv.error_reason,
    dv.requested_at,
    dv.updated_at,
    CASE WHEN dv.status = 'ready' THEN su.signed_url ELSE NULL END AS audio_url,
    CASE WHEN dv.status = 'ready' THEN su.expires_at ELSE NULL END AS audio_url_expires_at
  FROM public.discovery_voiceovers AS dv
  LEFT JOIN LATERAL storage.create_signed_url(
    v_bucket_id,
    format('%s/%s', dv.discovery_id, dv.file_name),
    v_ttl_seconds
  ) AS su(signed_url text, expires_at timestamptz) ON dv.status = 'ready'
  WHERE dv.user_id = auth.uid()
    AND dv.discovery_id = ANY(p_discovery_ids);
END;
$$;
REVOKE ALL ON FUNCTION public.get_discovery_voiceovers(bigint[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_discovery_voiceovers(bigint[]) TO authenticated;
