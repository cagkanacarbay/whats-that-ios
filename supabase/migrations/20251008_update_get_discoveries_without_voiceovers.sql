-- Recreate get_discoveries_with_location to align with voiceover column removal
-- The new definition omits legacy voiceover fields while keeping share_token and prompt versions.

BEGIN;

DROP FUNCTION IF EXISTS get_discoveries_with_location(integer, bigint);

CREATE OR REPLACE FUNCTION get_discoveries_with_location(
  p_limit integer DEFAULT 10,
  p_last_id bigint DEFAULT NULL
)
RETURNS TABLE (
  id bigint,
  user_id uuid,
  image_url text,
  description text,
  title character varying,
  short_description character varying,
  created_at timestamp with time zone,
  location text,
  country character varying,
  locality character varying,
  street_name character varying,
  closest_place character varying,
  share_token uuid,
  system_prompt_version character varying,
  user_prompt_version character varying
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    d.id,
    d.user_id,
    d.image_url,
    d.description,
    d.title,
    d.short_description,
    d.created_at,
    extensions.ST_AsText(d.location) as location,
    d.country,
    d.locality,
    d.street_name,
    d.closest_place,
    d.share_token,
    d.system_prompt_version,
    d.user_prompt_version
  FROM discoveries d
  WHERE d.user_id = auth.uid()
    AND (p_last_id IS NULL OR d.id < p_last_id)
  ORDER BY d.id DESC
  LIMIT p_limit;
END;
$$;

COMMIT;
