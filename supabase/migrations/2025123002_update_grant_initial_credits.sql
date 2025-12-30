-- Update grant_initial_credits to check for existing identifiers in initial_credit_grants
-- and record new identifiers after granting credits

-- Helper function to normalize and hash an email for consistent matching
CREATE OR REPLACE FUNCTION public.normalize_and_hash_email(p_email text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_normalized text;
  v_local_part text;
  v_domain text;
  v_at_pos integer;
BEGIN
  IF p_email IS NULL OR p_email = '' THEN
    RETURN NULL;
  END IF;
  
  -- Lowercase the entire email
  v_normalized := lower(trim(p_email));
  
  -- Split into local and domain parts
  v_at_pos := position('@' in v_normalized);
  IF v_at_pos = 0 THEN
    RETURN NULL;  -- Invalid email
  END IF;
  
  v_local_part := substring(v_normalized from 1 for v_at_pos - 1);
  v_domain := substring(v_normalized from v_at_pos + 1);
  
  -- Remove + suffix from local part (Gmail aliases)
  IF position('+' in v_local_part) > 0 THEN
    v_local_part := substring(v_local_part from 1 for position('+' in v_local_part) - 1);
  END IF;
  
  -- Remove dots from local part for Gmail
  IF v_domain = 'gmail.com' OR v_domain = 'googlemail.com' THEN
    v_local_part := replace(v_local_part, '.', '');
  END IF;
  
  v_normalized := v_local_part || '@' || v_domain;
  
  -- Return SHA-256 hash
  RETURN encode(extensions.digest(v_normalized, 'sha256'), 'hex');
END;
$$;

-- Helper function to hash any identifier
CREATE OR REPLACE FUNCTION public.hash_identifier(p_value text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
BEGIN
  IF p_value IS NULL OR p_value = '' THEN
    RETURN NULL;
  END IF;
  RETURN encode(extensions.digest(p_value, 'sha256'), 'hex');
END;
$$;

-- Helper function to record an identifier grant (idempotent)
CREATE OR REPLACE FUNCTION public.record_credit_grant_identifier(
  p_identifier_type text,
  p_identifier_hash text,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_identifier_hash IS NULL THEN
    RETURN;
  END IF;
  
  INSERT INTO public.initial_credit_grants (identifier_type, identifier_hash, user_id)
  VALUES (p_identifier_type, p_identifier_hash, p_user_id)
  ON CONFLICT (identifier_type, identifier_hash) DO NOTHING;
END;
$$;

-- Updated grant_initial_credits function with identifier checking
CREATE OR REPLACE FUNCTION public.grant_initial_credits(
  p_user_id uuid,
  p_amount integer,
  p_email text DEFAULT NULL,
  p_provider_id text DEFAULT NULL,
  p_provider_type text DEFAULT NULL,
  p_device_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE 
  v_exists BOOLEAN;
  v_email_hash text;
  v_provider_hash text;
  v_device_hash text;
  v_identifier_exists BOOLEAN := FALSE;
BEGIN
  -- Check if an initial grant already exists for this user_id (backward compatibility)
  SELECT EXISTS (
    SELECT 1 FROM public.credit_transactions ct
     WHERE ct.user_id = p_user_id
       AND ct.transaction_type = 'INITIAL'
  ) INTO v_exists;

  IF v_exists THEN
    RETURN;
  END IF;

  -- Compute hashes for identifiers
  v_email_hash := public.normalize_and_hash_email(p_email);
  v_device_hash := public.hash_identifier(p_device_id);
  
  IF p_provider_type IS NOT NULL AND p_provider_id IS NOT NULL THEN
    v_provider_hash := public.hash_identifier(p_provider_id);
  END IF;

  -- Check if ANY identifier already exists in initial_credit_grants
  SELECT EXISTS (
    SELECT 1 FROM public.initial_credit_grants icg
    WHERE (v_email_hash IS NOT NULL AND icg.identifier_type = 'email' AND icg.identifier_hash = v_email_hash)
       OR (v_device_hash IS NOT NULL AND icg.identifier_type = 'device_id' AND icg.identifier_hash = v_device_hash)
       OR (v_provider_hash IS NOT NULL AND icg.identifier_type = p_provider_type || '_sub' AND icg.identifier_hash = v_provider_hash)
  ) INTO v_identifier_exists;

  IF v_identifier_exists THEN
    -- User has received credits before with one of these identifiers
    -- Still create user_credits row but don't grant credits
    PERFORM 1 FROM public.user_credits uc WHERE uc.user_id = p_user_id;
    IF NOT FOUND THEN
      INSERT INTO public.user_credits (user_id, credit_balance, created_at, updated_at)
      VALUES (p_user_id, 0, now(), now());
    END IF;
    RETURN;
  END IF;

  -- Grant credits (existing logic)
  PERFORM 1 FROM public.user_credits uc WHERE uc.user_id = p_user_id;
  IF NOT FOUND THEN
    INSERT INTO public.user_credits (user_id, credit_balance, created_at, updated_at)
    VALUES (p_user_id, 0, now(), now());
  END IF;

  UPDATE public.user_credits
    SET credit_balance = credit_balance + p_amount,
        updated_at = now()
    WHERE user_id = p_user_id;

  INSERT INTO public.credit_transactions (user_id, transaction_type, amount, description)
    VALUES (p_user_id, 'INITIAL', p_amount, 'Initial free credits');

  -- Record ALL identifiers we have
  PERFORM public.record_credit_grant_identifier('email', v_email_hash, p_user_id);
  PERFORM public.record_credit_grant_identifier('device_id', v_device_hash, p_user_id);
  IF v_provider_hash IS NOT NULL THEN
    PERFORM public.record_credit_grant_identifier(p_provider_type || '_sub', v_provider_hash, p_user_id);
  END IF;
END;
$$;

-- Update handle_new_user trigger to extract and pass identifiers
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_email text;
  v_provider_id text;
  v_provider_type text;
  v_device_id text;
BEGIN
  -- Extract email (always available except when Apple hides it)
  v_email := NEW.email;
  
  -- Extract provider info from raw_app_meta_data
  v_provider_type := NEW.raw_app_meta_data->>'provider';
  
  -- For OAuth providers, get the provider_id (sub claim)
  IF v_provider_type IN ('apple', 'google') THEN
    v_provider_id := NEW.raw_app_meta_data->>'provider_id';
  END IF;
  
  -- Extract device_id if it was passed in user metadata
  v_device_id := NEW.raw_user_meta_data->>'device_id';
  
  PERFORM public.grant_initial_credits(
    NEW.id, 
    5,
    v_email,
    v_provider_id,
    v_provider_type,
    v_device_id
  );
  RETURN NEW;
END;
$$;

-- Grant execute permissions
REVOKE ALL ON FUNCTION public.normalize_and_hash_email(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.normalize_and_hash_email(text) TO service_role;

REVOKE ALL ON FUNCTION public.hash_identifier(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hash_identifier(text) TO service_role;

REVOKE ALL ON FUNCTION public.record_credit_grant_identifier(text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_credit_grant_identifier(text, text, uuid) TO service_role;

-- RPC for clients to record device_id after OAuth sign-in
-- This is needed because OAuth flows don't pass user metadata through the trigger
CREATE OR REPLACE FUNCTION public.record_device_for_credit_tracking(
  p_device_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_device_hash text;
BEGIN
  -- Get the current user's ID
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  
  IF p_device_id IS NULL OR p_device_id = '' THEN
    RETURN;
  END IF;
  
  v_device_hash := public.hash_identifier(p_device_id);
  
  -- Record the device_id (idempotent - ON CONFLICT DO NOTHING)
  INSERT INTO public.initial_credit_grants (identifier_type, identifier_hash, user_id)
  VALUES ('device_id', v_device_hash, v_user_id)
  ON CONFLICT (identifier_type, identifier_hash) DO NOTHING;
END;
$$;

-- Allow authenticated users to call this RPC
REVOKE ALL ON FUNCTION public.record_device_for_credit_tracking(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_device_for_credit_tracking(text) TO authenticated;

-- RPC for the delete-account function to record identifiers before deletion
-- This accepts raw values and hashes them
CREATE OR REPLACE FUNCTION public.record_identifier_for_credit_tracking(
  p_identifier_type text,
  p_raw_value text,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_hash text;
BEGIN
  IF p_raw_value IS NULL OR p_raw_value = '' THEN
    RETURN;
  END IF;
  
  -- Hash based on type
  IF p_identifier_type = 'email' THEN
    v_hash := public.normalize_and_hash_email(p_raw_value);
  ELSE
    v_hash := public.hash_identifier(p_raw_value);
  END IF;
  
  IF v_hash IS NULL THEN
    RETURN;
  END IF;
  
  -- Record (idempotent)
  INSERT INTO public.initial_credit_grants (identifier_type, identifier_hash, user_id)
  VALUES (p_identifier_type, v_hash, p_user_id)
  ON CONFLICT (identifier_type, identifier_hash) DO NOTHING;
END;
$$;

-- Grant execute to service_role for delete-account function
REVOKE ALL ON FUNCTION public.record_identifier_for_credit_tracking(text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_identifier_for_credit_tracking(text, text, uuid) TO service_role;


