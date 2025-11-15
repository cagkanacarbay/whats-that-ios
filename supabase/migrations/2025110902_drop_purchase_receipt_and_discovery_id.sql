-- Purpose: Remove legacy, unused purchase_receipt and discovery_id columns
-- Context: We no longer store raw receipts; Edge function and DB schema use idempotency via store_transaction_id.
-- Change: Drop purchase_receipt and discovery_id columns from public.credit_transactions

ALTER TABLE IF EXISTS public.credit_transactions
  DROP COLUMN IF EXISTS purchase_receipt,
  DROP COLUMN IF EXISTS discovery_id;

