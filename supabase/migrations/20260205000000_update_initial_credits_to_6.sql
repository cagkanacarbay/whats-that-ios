-- Update initial credits from 5 to 6 (3 discoveries + 3 audio guides)
-- This gives intro users enough credits for 3 complete discovery+audio experiences

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_email text;
  v_provider_id text;
  v_provider_type text;
  v_device_id text;
BEGIN
  v_email := NEW.email;
  v_provider_type := NEW.raw_app_meta_data->>'provider';

  IF v_provider_type IN ('apple', 'google') THEN
    v_provider_id := NEW.raw_app_meta_data->>'provider_id';
  END IF;

  v_device_id := NEW.raw_user_meta_data->>'device_id';

  -- Changed from 5 to 6: 3 discoveries + 3 audio guides
  PERFORM public.grant_initial_credits(
    NEW.id,
    6,
    v_email,
    v_provider_id,
    v_provider_type,
    v_device_id
  );
  RETURN NEW;
END;
$$;
