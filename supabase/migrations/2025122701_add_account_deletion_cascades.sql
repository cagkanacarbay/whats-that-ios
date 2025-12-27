-- Add ON DELETE CASCADE to foreign keys referencing auth.users
-- This ensures all user data is deleted when a user is removed from auth.users

-- Add ON DELETE CASCADE to credit_transactions
ALTER TABLE public.credit_transactions 
  DROP CONSTRAINT IF EXISTS credit_transactions_user_id_fkey;
ALTER TABLE public.credit_transactions 
  ADD CONSTRAINT credit_transactions_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Add ON DELETE CASCADE to discovery_voiceovers
ALTER TABLE public.discovery_voiceovers 
  DROP CONSTRAINT IF EXISTS discovery_voiceovers_user_id_fkey;
ALTER TABLE public.discovery_voiceovers 
  ADD CONSTRAINT discovery_voiceovers_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Add ON DELETE CASCADE to user_credits
ALTER TABLE public.user_credits 
  DROP CONSTRAINT IF EXISTS user_credits_user_id_fkey;
ALTER TABLE public.user_credits 
  ADD CONSTRAINT user_credits_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Add FK with ON DELETE CASCADE to edge_function_rate_limits
-- (Use DROP IF EXISTS to make this idempotent in case it was partially applied)
ALTER TABLE public.edge_function_rate_limits 
  DROP CONSTRAINT IF EXISTS edge_function_rate_limits_user_id_fkey;
ALTER TABLE public.edge_function_rate_limits 
  ADD CONSTRAINT edge_function_rate_limits_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
