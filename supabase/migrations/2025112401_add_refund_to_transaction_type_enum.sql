-- Ensure transaction_type_enum includes REFUND for credit transaction logs
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_type t
    WHERE t.typname = 'transaction_type_enum'
  ) AND NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE t.typname = 'transaction_type_enum'
      AND e.enumlabel = 'REFUND'
  ) THEN
    ALTER TYPE public.transaction_type_enum ADD VALUE 'REFUND';
  END IF;
END $$;
