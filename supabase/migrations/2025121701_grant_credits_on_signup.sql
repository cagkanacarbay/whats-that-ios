-- Trigger to grant 3 starter credits when a new user signs up
-- This uses the existing grant_initial_credits function which is idempotent

-- Trigger function to call grant_initial_credits for new users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Grant 3 starter credits to the new user
  PERFORM public.grant_initial_credits(NEW.id, 3);
  RETURN NEW;
END;
$$;

-- Attach trigger to auth.users table
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
