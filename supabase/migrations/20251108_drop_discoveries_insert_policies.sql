-- Purpose: Remove over-broad INSERT RLS policies on public.discoveries
-- Context: Inserts are performed only by the Edge Function ask-ai-v7 using service_role (bypasses RLS).
-- Result: No table-level INSERTs allowed via REST/clients; Edge function inserts unaffected.

-- Safety: Use IF EXISTS so this migration can run idempotently across environments.

DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.discoveries;
DROP POLICY IF EXISTS "Enable insert for users based on user_id" ON public.discoveries;

-- Note: Keeping existing SELECT/DELETE owner policies as-is.
