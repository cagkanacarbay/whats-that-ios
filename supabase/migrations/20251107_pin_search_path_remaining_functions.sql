-- Pin search_path and fully-qualify remaining SECURITY DEFINER functions

-- 1) get_discovery_analysis (owner-or-admin)
DROP FUNCTION IF EXISTS public.get_discovery_analysis(bigint);
CREATE OR REPLACE FUNCTION public.get_discovery_analysis(p_discovery_id bigint)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_analysis TEXT;
  v_user_id UUID;
BEGIN
  SELECT d.user_id INTO v_user_id
  FROM public.discoveries d
  WHERE d.id = p_discovery_id;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Discovery not found: %', p_discovery_id;
  END IF;

  IF v_user_id != auth.uid() AND NOT EXISTS (
    SELECT 1 FROM auth.users u
    WHERE u.id = auth.uid()
      AND (u.raw_user_meta_data->>'role') = 'admin'
  ) THEN
    RAISE EXCEPTION 'Unauthorized access to discovery analysis';
  END IF;

  SELECT d.analysis INTO v_analysis
  FROM public.discoveries d
  WHERE d.id = p_discovery_id;

  RETURN v_analysis;
END;
$$;
REVOKE ALL ON FUNCTION public.get_discovery_analysis(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_discovery_analysis(bigint) TO authenticated;

-- 2) consume_credit_for_discovery
DROP FUNCTION IF EXISTS public.consume_credit_for_discovery(uuid, integer);
CREATE OR REPLACE FUNCTION public.consume_credit_for_discovery(
  p_user_id uuid,
  p_credits_to_consume integer DEFAULT 1
)
RETURNS void
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
END; $$;
REVOKE ALL ON FUNCTION public.consume_credit_for_discovery(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_credit_for_discovery(uuid, integer) TO service_role;

-- 3) refund_credit
DROP FUNCTION IF EXISTS public.refund_credit(uuid, integer);
CREATE OR REPLACE FUNCTION public.refund_credit(
  p_user_id uuid,
  p_credits_to_refund integer DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.user_credits
    SET credit_balance = credit_balance + p_credits_to_refund,
        updated_at = now()
    WHERE user_id = p_user_id;

  INSERT INTO public.credit_transactions (user_id, transaction_type, amount, description)
    VALUES (p_user_id, 'REFUND', p_credits_to_refund, 'Refund after failed discovery analysis');
END; $$;
REVOKE ALL ON FUNCTION public.refund_credit(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refund_credit(uuid, integer) TO service_role;

-- 4) grant_initial_credits (idempotent via transaction log)
DROP FUNCTION IF EXISTS public.grant_initial_credits(uuid, integer);
CREATE OR REPLACE FUNCTION public.grant_initial_credits(
  p_user_id uuid,
  p_amount integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_exists BOOLEAN; BEGIN
  -- If an initial grant already exists, skip (idempotent behavior)
  SELECT EXISTS (
    SELECT 1 FROM public.credit_transactions ct
     WHERE ct.user_id = p_user_id
       AND ct.transaction_type = 'INITIAL_GRANT'
  ) INTO v_exists;

  IF v_exists THEN
    RETURN;
  END IF;

  -- Ensure a user_credits row exists
  PERFORM 1 FROM public.user_credits uc WHERE uc.user_id = p_user_id;
  IF NOT FOUND THEN
    INSERT INTO public.user_credits (user_id, credit_balance, created_at, updated_at)
    VALUES (p_user_id, 0, now(), now());
  END IF;

  -- Apply the grant
  UPDATE public.user_credits
    SET credit_balance = credit_balance + p_amount,
        updated_at = now()
    WHERE user_id = p_user_id;

  INSERT INTO public.credit_transactions (user_id, transaction_type, amount, description)
    VALUES (p_user_id, 'INITIAL_GRANT', p_amount, 'Starter credits');
END; $$;
REVOKE ALL ON FUNCTION public.grant_initial_credits(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.grant_initial_credits(uuid, integer) TO service_role;

-- 5) add_credits_after_validation (idempotent by store_transaction_id + platform)
DROP FUNCTION IF EXISTS public.add_credits_after_validation(uuid, integer, text, text, text, text);
CREATE OR REPLACE FUNCTION public.add_credits_after_validation(
  p_user_id uuid,
  p_amount integer,
  p_platform text,
  p_product_id text,
  p_store_transaction_id text,
  p_raw_receipt_data text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_exists BOOLEAN; BEGIN
  -- Idempotency: if we already logged this store transaction for this user and platform, skip
  SELECT EXISTS (
    SELECT 1 FROM public.credit_transactions ct
     WHERE ct.user_id = p_user_id
       AND ct.store_transaction_id = p_store_transaction_id
       AND ct.platform = p_platform
  ) INTO v_exists;

  IF v_exists THEN
    RETURN;
  END IF;

  -- Ensure a user_credits row exists
  PERFORM 1 FROM public.user_credits uc WHERE uc.user_id = p_user_id;
  IF NOT FOUND THEN
    INSERT INTO public.user_credits (user_id, credit_balance, created_at, updated_at)
    VALUES (p_user_id, 0, now(), now());
  END IF;

  -- Apply credit
  UPDATE public.user_credits
    SET credit_balance = credit_balance + p_amount,
        updated_at = now()
    WHERE user_id = p_user_id;

  -- Log transaction for idempotency and audit
  INSERT INTO public.credit_transactions (
    user_id, transaction_type, amount, description, platform, store_transaction_id, product_id, raw_receipt_data
  ) VALUES (
    p_user_id, 'PURCHASE', p_amount, 'Credits purchased via receipt validation', p_platform, p_store_transaction_id, p_product_id, p_raw_receipt_data
  );
END; $$;
REVOKE ALL ON FUNCTION public.add_credits_after_validation(uuid, integer, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_credits_after_validation(uuid, integer, text, text, text, text) TO authenticated;

