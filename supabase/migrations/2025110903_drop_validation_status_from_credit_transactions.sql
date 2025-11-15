BEGIN;

ALTER TABLE IF EXISTS public.credit_transactions
  DROP COLUMN IF EXISTS validation_status;

COMMIT;
