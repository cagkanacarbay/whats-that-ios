-- Update credit consumption functions to return balance directly
-- This eliminates extra fetch queries in edge functions

-- 1) consume_credit_for_discovery: change from RETURNS void to RETURNS integer
DROP FUNCTION IF EXISTS public.consume_credit_for_discovery(uuid, integer);
CREATE OR REPLACE FUNCTION public.consume_credit_for_discovery(
  p_user_id uuid,
  p_credits_to_consume integer DEFAULT 1
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_current_balance INTEGER; BEGIN
  UPDATE public.user_credits
    SET credit_balance = credit_balance - p_credits_to_consume,
        updated_at = now()
    WHERE user_id = p_user_id AND credit_balance >= p_credits_to_consume
    RETURNING credit_balance INTO v_current_balance;

  IF v_current_balance IS NULL THEN
    SELECT uc.credit_balance INTO v_current_balance FROM public.user_credits uc WHERE uc.user_id = p_user_id;
    IF v_current_balance IS NULL THEN
      RAISE EXCEPTION 'User not found: %', p_user_id;
    ELSE
      RAISE EXCEPTION 'insufficient_credits';
    END IF;
  END IF;

  INSERT INTO public.credit_transactions (user_id, transaction_type, amount, description)
    VALUES (p_user_id, 'USAGE', -p_credits_to_consume, 'Credit used for discovery analysis');
  
  RETURN v_current_balance;
END; $$;
REVOKE ALL ON FUNCTION public.consume_credit_for_discovery(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_credit_for_discovery(uuid, integer) TO service_role;


-- 2) Create composite type for start_voiceover_request to return both row and balance
DROP TYPE IF EXISTS public.voiceover_request_result CASCADE;
CREATE TYPE public.voiceover_request_result AS (
  voiceover public.discovery_voiceovers,
  credit_balance integer,
  was_existing boolean
);


-- 3) Update start_voiceover_request to return the composite type with credit balance
DROP FUNCTION IF EXISTS public.start_voiceover_request(uuid, bigint, text, text);
CREATE OR REPLACE FUNCTION public.start_voiceover_request(
  p_user_id uuid,
  p_discovery_id bigint,
  p_tts_model text,
  p_voice_model_id text
) RETURNS public.voiceover_request_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_existing public.discovery_voiceovers;
  v_now timestamptz := now();
  v_credit_balance integer := NULL;
  v_result public.voiceover_request_result;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.discoveries d
    WHERE d.id = p_discovery_id AND d.user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'discovery_not_found_or_unauthorized';
  END IF;

  SELECT * INTO v_existing
  FROM public.discovery_voiceovers
  WHERE discovery_id = p_discovery_id
  FOR UPDATE;

  IF FOUND THEN
    -- Return existing row without consuming credits
    -- Fetch current balance for client sync
    SELECT uc.credit_balance INTO v_credit_balance 
    FROM public.user_credits uc WHERE uc.user_id = p_user_id;
    
    v_result.voiceover := v_existing;
    v_result.credit_balance := v_credit_balance;
    v_result.was_existing := true;
    RETURN v_result;
  END IF;

  INSERT INTO public.discovery_voiceovers (
    discovery_id, user_id, provider, tts_model, voice_model_id,
    file_name, file_extension,
    status, error_reason, requested_at
  )
  VALUES (
    p_discovery_id, p_user_id, 'fish', p_tts_model, p_voice_model_id,
    format('fish-%s-%s.mp3', p_tts_model, p_voice_model_id),
    'mp3', 'processing', NULL, v_now
  )
  RETURNING * INTO v_existing;

  -- Consume credit and capture the returned balance
  v_credit_balance := public.consume_credit_for_voiceover(p_user_id);

  v_result.voiceover := v_existing;
  v_result.credit_balance := v_credit_balance;
  v_result.was_existing := false;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.start_voiceover_request(uuid, bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_voiceover_request(uuid, bigint, text, text) TO service_role;
