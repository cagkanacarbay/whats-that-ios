-- Create table to track identifiers that have received initial free credits
-- This prevents users from deleting their account and re-signing up for more credits

CREATE TABLE IF NOT EXISTS public.initial_credit_grants (
    id SERIAL PRIMARY KEY,
    identifier_type TEXT NOT NULL,  -- 'email', 'apple_sub', 'google_sub', 'device_id'
    identifier_hash TEXT NOT NULL,  -- SHA-256 hash for privacy
    granted_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    user_id UUID,  -- The user who received the grant (for auditing, nullable after deletion)
    UNIQUE (identifier_type, identifier_hash)
);

-- Index for fast lookups during signup check
CREATE INDEX IF NOT EXISTS idx_initial_credit_grants_lookup 
    ON public.initial_credit_grants(identifier_type, identifier_hash);

-- RLS: No public access, only service_role can read/write
ALTER TABLE public.initial_credit_grants ENABLE ROW LEVEL SECURITY;

-- No policies = denied to all except service_role
COMMENT ON TABLE public.initial_credit_grants IS 
    'Tracks identifiers that have received initial free credits to prevent abuse via account deletion and re-signup';
