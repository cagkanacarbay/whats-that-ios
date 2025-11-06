# Updating Database Functions Securely

This guide documents the maximum‑safety pattern for Postgres functions used by the app and Edge Functions, why we
apply it, what it impacts, and exactly how to update functions going forward. It includes a ready‑to‑run migration for
`get_discoveries_with_location` so we can validate the approach end‑to‑end.

## Why This Matters

- Problem: `SECURITY DEFINER` functions run with the owner’s privileges. If their `search_path` is mutable and function
  bodies reference objects without schema qualification (e.g., `FROM discoveries`), name resolution can be redirected to
  unintended objects. This is a known risk flagged by Supabase’s Database Advisors.
- Goal: Eliminate search_path hijacking risks and privilege confusion while keeping the current API contract unchanged
  for our iOS app and Edge Functions.

## Maximum‑Safety Pattern

Use all of these together for every `SECURITY DEFINER` function:
- Pin search path: define the function with `SECURITY DEFINER SET search_path = ''`.
- Fully‑qualify everything in the function body:
  - Tables/views/sequences: `public.discoveries`, `public.user_credits`, `public.credit_transactions`.
  - Auth helpers: `auth.uid()`.
  - Extensions: `extensions.ST_AsText(...)`, `extensions.uuid_generate_v4()`.
- Tight EXECUTE grants and revoke from `PUBLIC`:
  - Read/user‑scoped RPCs (called with a user JWT): `GRANT EXECUTE ... TO authenticated`.
  - Mutating/admin RPCs invoked by backend only: `GRANT EXECUTE ... TO service_role`.
  - Always: `REVOKE ALL ... FROM PUBLIC`.

This keeps behavior identical for callers while hardening name resolution. If function names, argument names/types, and
return columns remain the same, app and Edge callers continue to work without changes.

## What This Impacts

- iOS app (user session token)
  - Calls `get_discoveries_with_location`. It needs EXECUTE privileges for role `authenticated`.
  - No app code changes when function signature and return shape stay the same.
- Edge function `validate-receipt` (user token)
  - Calls `add_credits_after_validation`. Grant to `authenticated`.
- Edge function `ask-ai-v7` (service role)
  - Calls `consume_credit_for_discovery`, `refund_credit`. Grant to `service_role`.
- Nearby places RPC
  - Already handled in a prior migration with pinned `search_path` and minimal grants.

## Update Rules (Repeat Every Time)

When editing or recreating a `SECURITY DEFINER` function:
- Include `SET search_path = ''` in the `CREATE OR REPLACE FUNCTION` statement.
- Fully‑qualify all object references inside the body (tables, functions, types, sequences, extensions, auth helpers).
- Revoke and re‑grant EXECUTE as needed (minimal roles only). If you change the function signature (parameter list or
  types), Postgres treats it as a different object; you’ll need to re‑apply the GRANTs after a DROP/CREATE.
- Keep parameter names stable for RPC callers (Supabase maps JSON argument names to parameters). Prefer adding optional
  parameters with defaults over renaming/removing existing ones.
- Keep return column names/types stable for client decoders unless you concurrently update clients.

## Function Template (Copy/Paste)

```sql
-- Template for a maximum‑safety SECURITY DEFINER function
CREATE OR REPLACE FUNCTION public.function_name(
  p_example uuid,
  p_optional integer DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_example integer;
BEGIN
  -- Fully qualify every object below
  UPDATE public.some_table
  SET updated_at = now()
  WHERE user_id = p_example;

  PERFORM auth.uid(); -- also fully qualified (auth schema)
END;
$$;

-- Minimal, explicit privileges (adjust as needed)
REVOKE ALL ON FUNCTION public.function_name(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.function_name(uuid, integer) TO authenticated; -- or service_role
```

## Migration: Pin search_path for get_discoveries_with_location

This migration recreates `get_discoveries_with_location` with `SET search_path = ''`, fully‑qualified references, and
minimal EXECUTE privileges. It preserves the existing function signature and return shape used by the iOS app.

- Effects on callers: None (same parameters and returned columns). The iOS app uses an authenticated session and will
  continue to call this RPC as before.

```sql
-- Recreate get_discoveries_with_location with pinned search_path and fully‑qualified references
CREATE OR REPLACE FUNCTION public.get_discoveries_with_location(
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
SET search_path = ''
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
    extensions.ST_AsText(d.location) AS location,
    d.country,
    d.locality,
    d.street_name,
    d.closest_place,
    d.share_token
  FROM public.discoveries d
  WHERE d.user_id = auth.uid()
    AND (p_last_id IS NULL OR d.id < p_last_id)
  ORDER BY d.id DESC
  LIMIT p_limit;
END;
$$;

-- Restrict RPC execution to the minimal role needed by the iOS app
REVOKE ALL ON FUNCTION public.get_discoveries_with_location(integer, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_discoveries_with_location(integer, bigint) TO authenticated;
```

## How to Test

1) Apply the migration locally (or in staging):
- `supabase db reset` (local) or `supabase db push` (targeted) as appropriate.

2) Smoke test:
- Launch the iOS app with a valid user session.
- Verify discovery feed loads (calls `get_discoveries_with_location`).
- Check server logs for any function errors. If something breaks, it will be obvious here.

3) Roll out to production after validation.

---

If desired, we can follow this with similar migrations for the remaining definer functions (`add_credits_after_validation`,
`consume_credit_for_discovery`, `refund_credit`, `grant_initial_credits`, `get_discovery_analysis`).

