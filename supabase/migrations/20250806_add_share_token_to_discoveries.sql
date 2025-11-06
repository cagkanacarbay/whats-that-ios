-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Add share_token column to discoveries table
ALTER TABLE public.discoveries 
ADD COLUMN share_token UUID DEFAULT uuid_generate_v4() UNIQUE NOT NULL;

-- Create index for performance
CREATE INDEX idx_discoveries_share_token ON public.discoveries(share_token);

-- Update any existing discoveries that might have NULL share_token
-- (This is a safety measure, shouldn't be needed with DEFAULT)
UPDATE public.discoveries 
SET share_token = uuid_generate_v4() 
WHERE share_token IS NULL;

-- Add comment for documentation
COMMENT ON COLUMN public.discoveries.share_token IS 'Unique token for sharing discoveries via URL';

-- Drop existing function if exists (be careful in production!)
DROP FUNCTION IF EXISTS get_discoveries_with_location(integer, bigint);
DROP FUNCTION IF EXISTS get_discoveries_with_location(integer, integer);

-- Create updated function that includes share_token with correct column types
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
    ST_AsText(d.location) as location,
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