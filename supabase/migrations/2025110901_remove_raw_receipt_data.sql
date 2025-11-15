BEGIN;

-- 1) Drop the raw_receipt_data column (no longer needed)
ALTER TABLE IF EXISTS public.credit_transactions
  DROP COLUMN IF EXISTS raw_receipt_data;

-- 2) Replace the add_credits_after_validation function without raw receipt param
--    Drop old signature first to avoid signature mismatch
DROP FUNCTION IF EXISTS public.add_credits_after_validation(uuid, integer, text, text, text, text);

CREATE OR REPLACE FUNCTION public.add_credits_after_validation(
  p_user_id uuid,
  p_amount integer,
  p_platform text,
  p_product_id text,
  p_store_transaction_id text
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

  -- Log transaction for idempotency and audit (no raw receipt stored)
  INSERT INTO public.credit_transactions (
    user_id, transaction_type, amount, description, platform, store_transaction_id, product_id
  ) VALUES (
    p_user_id, 'PURCHASE', p_amount, 'Credits purchased via receipt validation', p_platform, p_store_transaction_id, p_product_id
  );
END; $$;

REVOKE ALL ON FUNCTION public.add_credits_after_validation(uuid, integer, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_credits_after_validation(uuid, integer, text, text, text) TO authenticated;
COMMIT;
