-- Fix grant_initial_credits to use 'INITIAL' instead of 'INITIAL_GRANT' as transaction_type
-- Also update the trigger function to use the correct value

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
       AND ct.transaction_type = 'INITIAL'
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
    VALUES (p_user_id, 'INITIAL', p_amount, 'Initial free credits');
END; $$;
