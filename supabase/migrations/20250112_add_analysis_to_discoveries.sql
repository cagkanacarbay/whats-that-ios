-- Add analysis column to discoveries table
-- This column will store the internal AI analysis for debugging and future use
ALTER TABLE public.discoveries 
ADD COLUMN analysis TEXT;

-- Add comment for documentation
COMMENT ON COLUMN public.discoveries.analysis IS 'Internal AI analysis data for debugging and potential future features. Not returned to clients by default.';

-- Update the get_discoveries_with_location function to EXCLUDE the analysis column
-- This ensures the analysis is not returned to the client app
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
  share_token uuid
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
    d.share_token
  FROM discoveries d
  WHERE d.user_id = auth.uid()
    AND (p_last_id IS NULL OR d.id < p_last_id)
  ORDER BY d.id DESC
  LIMIT p_limit;
END;
$$;

-- Note: The analysis column is intentionally NOT included in the function above
-- This prevents it from being sent to the client while keeping it available
-- for internal use and debugging

-- Optional: Create a separate admin function if you need to access analysis data
CREATE OR REPLACE FUNCTION get_discovery_analysis(p_discovery_id bigint)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_analysis TEXT;
  v_user_id UUID;
BEGIN
  -- Get the user_id of the discovery
  SELECT user_id INTO v_user_id
  FROM discoveries
  WHERE id = p_discovery_id;
  
  -- Check if the current user owns this discovery or is an admin
  IF v_user_id != auth.uid() AND NOT EXISTS (
    SELECT 1 FROM auth.users 
    WHERE id = auth.uid() 
    AND raw_user_meta_data->>'role' = 'admin'
  ) THEN
    RAISE EXCEPTION 'Unauthorized access to discovery analysis';
  END IF;
  
  -- Return the analysis
  SELECT analysis INTO v_analysis
  FROM discoveries
  WHERE id = p_discovery_id;
  
  RETURN v_analysis;
END;
$$;

-- Add comment for the admin function
COMMENT ON FUNCTION get_discovery_analysis(bigint) IS 'Retrieves analysis data for a specific discovery. Only accessible by the discovery owner or admin users.';