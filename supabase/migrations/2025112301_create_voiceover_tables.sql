-- discovery_voiceovers
CREATE TABLE public.discovery_voiceovers (
  id bigserial PRIMARY KEY,
  discovery_id bigint NOT NULL REFERENCES public.discoveries(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  provider text NOT NULL CHECK (provider IN ('fish')),
  tts_model text NOT NULL DEFAULT 's1',
  voice_model_id text NOT NULL,
  file_name text NOT NULL,
  file_extension text NOT NULL DEFAULT 'mp3',
  status text NOT NULL CHECK (status IN ('processing','ready','failed')),
  error_reason text NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX discovery_voiceovers_dedup_idx
  ON public.discovery_voiceovers (discovery_id);
CREATE INDEX discovery_voiceovers_user_discovery_idx
  ON public.discovery_voiceovers (user_id, discovery_id);
CREATE INDEX discovery_voiceovers_status_updated_idx
  ON public.discovery_voiceovers (status, updated_at);

-- voice_inventory
CREATE TABLE public.voice_inventory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL CHECK (provider IN ('fish')),
  tts_model text NOT NULL DEFAULT 's1',
  voice_model_id text NOT NULL,
  display_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX voice_inventory_provider_model_voice_idx
  ON public.voice_inventory (provider, tts_model, voice_model_id);

-- Keep updated_at fresh
CREATE OR REPLACE FUNCTION public.set_discovery_voiceovers_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;
CREATE TRIGGER discovery_voiceovers_set_updated_at
  BEFORE UPDATE ON public.discovery_voiceovers
  FOR EACH ROW EXECUTE FUNCTION public.set_discovery_voiceovers_updated_at();

-- RLS
ALTER TABLE public.discovery_voiceovers ENABLE ROW LEVEL SECURITY;
CREATE POLICY discovery_voiceovers_select_own ON public.discovery_voiceovers
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY discovery_voiceovers_insert_own ON public.discovery_voiceovers
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY discovery_voiceovers_update_own ON public.discovery_voiceovers
  FOR UPDATE USING (auth.uid() = user_id);

ALTER TABLE public.voice_inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY voice_inventory_select_all ON public.voice_inventory
  FOR SELECT USING (true);

-- Credits (mirror consume_credit_for_discovery guard behavior)
DROP FUNCTION IF EXISTS public.consume_credit_for_voiceover(uuid, integer);
CREATE OR REPLACE FUNCTION public.consume_credit_for_voiceover(
  p_user_id uuid,
  p_credits_to_consume integer DEFAULT 1
) RETURNS integer
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
    VALUES (p_user_id, 'USAGE', -p_credits_to_consume, 'Credit used for voiceover');

  RETURN v_current_balance;
END; $$;
REVOKE ALL ON FUNCTION public.consume_credit_for_voiceover(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_credit_for_voiceover(uuid, integer) TO service_role;

DROP FUNCTION IF EXISTS public.refund_credit_for_voiceover(uuid, integer);
CREATE OR REPLACE FUNCTION public.refund_credit_for_voiceover(
  p_user_id uuid,
  p_credits_to_refund integer DEFAULT 1
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_current_balance INTEGER; BEGIN
  UPDATE public.user_credits
    SET credit_balance = credit_balance + p_credits_to_refund,
        updated_at = now()
    WHERE user_id = p_user_id
    RETURNING credit_balance INTO v_current_balance;

  INSERT INTO public.credit_transactions (user_id, transaction_type, amount, description)
    VALUES (p_user_id, 'REFUND', p_credits_to_refund, 'Refund after failed voiceover');

  RETURN v_current_balance;
END; $$;
REVOKE ALL ON FUNCTION public.refund_credit_for_voiceover(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refund_credit_for_voiceover(uuid, integer) TO service_role;

-- Atomic start (insert only if absent; never updates existing rows)
DROP FUNCTION IF EXISTS public.start_voiceover_request(uuid, bigint, text, text);
CREATE OR REPLACE FUNCTION public.start_voiceover_request(
  p_user_id uuid,
  p_discovery_id bigint,
  p_tts_model text,
  p_voice_model_id text
) RETURNS public.discovery_voiceovers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_existing public.discovery_voiceovers;
  v_now timestamptz := now();
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.discoveries d
    WHERE d.id = p_discovery_id AND d.user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'discovery_not_found_or_unauthorized';
  END IF;

  SELECT * INTO v_existing
  FROM public.discovery_voiceovers
  WHERE discovery_id = p_discovery_id
  FOR UPDATE;

  IF FOUND THEN
    RETURN v_existing;
  END IF;

  INSERT INTO public.discovery_voiceovers (
    discovery_id, user_id, provider, tts_model, voice_model_id,
    file_name, file_extension,
    status, error_reason, requested_at
  )
  VALUES (
    p_discovery_id, p_user_id, 'fish', p_tts_model, p_voice_model_id,
    format('fish-%s-%s.mp3', p_tts_model, p_voice_model_id),
    'mp3', 'processing', NULL, v_now
  )
  RETURNING * INTO v_existing;

  -- Credit consumption happens after insert; if it fails, the transaction rolls back and removes the row.
  PERFORM public.consume_credit_for_voiceover(p_user_id);

  RETURN v_existing;
END;
$$;
REVOKE ALL ON FUNCTION public.start_voiceover_request(uuid, bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_voiceover_request(uuid, bigint, text, text) TO service_role;

-- RPC: get_discovery_voiceovers (audio_url only for ready rows)
DROP FUNCTION IF EXISTS public.get_discovery_voiceovers(bigint[]);
CREATE OR REPLACE FUNCTION public.get_discovery_voiceovers(p_discovery_ids bigint[])
RETURNS TABLE (
  id bigint,
  discovery_id bigint,
  user_id uuid,
  provider text,
  tts_model text,
  voice_model_id text,
  file_name text,
  file_extension text,
  status text,
  error_reason text,
  requested_at timestamptz,
  updated_at timestamptz,
  audio_url text,
  audio_url_expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_ttl_seconds integer := 604800; -- 7d
BEGIN
  RETURN QUERY
  SELECT
    dv.id, dv.discovery_id, dv.user_id, dv.provider, dv.tts_model,
    dv.voice_model_id, dv.file_name, dv.file_extension,
    dv.status, dv.error_reason, dv.requested_at, dv.updated_at,
    CASE WHEN dv.status = 'ready' THEN su.signed_url ELSE NULL END AS audio_url,
    CASE WHEN dv.status = 'ready' THEN su.expires_at ELSE NULL END AS audio_url_expires_at
  FROM public.discovery_voiceovers dv
  LEFT JOIN LATERAL storage.create_signed_url(
    'voiceovers',
    format('%s/%s', dv.discovery_id, dv.file_name),
    v_ttl_seconds
  ) AS su(signed_url text, expires_at timestamptz) ON dv.status = 'ready'
  WHERE dv.user_id = auth.uid()
    AND dv.discovery_id = ANY(p_discovery_ids);
END;
$$;
REVOKE ALL ON FUNCTION public.get_discovery_voiceovers(bigint[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_discovery_voiceovers(bigint[]) TO authenticated;

-- RPC: get_voice_options (no fallback)
DROP FUNCTION IF EXISTS public.get_voice_options();
CREATE OR REPLACE FUNCTION public.get_voice_options()
RETURNS SETOF public.voice_inventory
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT * FROM public.voice_inventory;
$$;
REVOKE ALL ON FUNCTION public.get_voice_options() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_voice_options() TO authenticated;
