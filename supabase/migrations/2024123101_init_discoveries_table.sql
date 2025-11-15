-- Baseline: create discoveries table so shadow DB can replay later migrations
-- Rationale: earlier versions added columns to discoveries without a tracked
--            migration that created the table, causing `supabase db pull` to fail.

BEGIN;

-- Ensure PostGIS types are available for the geometry column
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS public.discoveries (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID DEFAULT auth.uid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  image_url TEXT,
  description TEXT,
  title VARCHAR,
  short_description VARCHAR,
  location geometry,
  country VARCHAR,
  locality VARCHAR,
  street_name VARCHAR,
  closest_place VARCHAR
);

COMMIT;

