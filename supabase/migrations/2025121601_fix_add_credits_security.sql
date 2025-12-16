-- Fix critical security vulnerability: restrict add_credits_after_validation to service_role only
-- 
-- Context: This function was previously granted to `authenticated` role, allowing any
-- logged-in user to grant themselves unlimited credits by calling the RPC directly,
-- bypassing Apple receipt validation in the validate-receipt Edge Function.
--
-- Fix: Revoke from authenticated, grant only to service_role. The Edge Function must
-- use supabaseAdmin (service_role) to call this RPC after validating the Apple receipt.

-- Revoke from authenticated role
REVOKE EXECUTE ON FUNCTION public.add_credits_after_validation(uuid, integer, text, text, text) FROM authenticated;

-- Ensure service_role has access (may already be granted, but explicit for clarity)
GRANT EXECUTE ON FUNCTION public.add_credits_after_validation(uuid, integer, text, text, text) TO service_role;
