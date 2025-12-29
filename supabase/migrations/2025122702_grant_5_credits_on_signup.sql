-- Update initial credits from 3 to 5 to cover 3 discoveries + 2 free voiceovers
-- This replaces the trigger function to grant 5 credits instead of 3

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Grant 5 starter credits: 3 for discoveries + 2 for intro voiceovers
  PERFORM public.grant_initial_credits(NEW.id, 5);
  RETURN NEW;
END;
$$;

-- Note: The trigger on_auth_user_created already exists and references this function.
-- We only need to update the function body, not recreate the trigger.
