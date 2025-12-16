-- Consolidate rate limiting to use unified edge_function_rate_limits table
-- The nearby-places function will now use enforce_edge_function_rate_limit
-- instead of the legacy enforce_nearby_places_rate_limit function.

-- Add composite index on (user_id, function_name) for fast lookups
-- The primary key already creates an index, but this explicit index ensures
-- optimal query performance for the common lookup pattern.
CREATE INDEX IF NOT EXISTS idx_edge_rate_limits_user_function
  ON public.edge_function_rate_limits (user_id, function_name);

-- Drop the legacy nearby_places rate limiting (pre-launch, no need for rollback support)
DROP FUNCTION IF EXISTS public.enforce_nearby_places_rate_limit(uuid, integer, integer);
DROP TABLE IF EXISTS public.nearby_places_rate_limits;
