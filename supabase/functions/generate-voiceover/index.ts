import "jsr:@supabase/functions-js/edge-runtime.d.ts"

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { encode } from 'npm:msgpackr';
import { buildCorsHeaders } from '../_shared/cors.ts';
import { createLogger } from '../_shared/logger.ts';
import type { Logger } from '../_shared/logger.ts';

const FISH_TTS_URL = 'https://api.fish.audio/v1/tts';
const STORAGE_BUCKET = 'voiceovers';
const SIGNED_URL_TTL_SECONDS = 60 * 60 * 24 * 7; // 7d
const PROCESSING_STALE_MS = 60_000;
const EDGE_BUDGET_MS = 50_000;
const BACKOFF_STEPS_MS = [0, 1000, 2000, 4000, 8000];

type VoiceoverStatus = 'processing' | 'ready' | 'failed';

interface VoiceoverRow {
  id: number;
  discovery_id: number;
  user_id: string;
  provider: string;
  tts_model: string;
  voice_model_id: string;
  file_name: string;
  file_extension: string;
  status: VoiceoverStatus;
  error_reason: string | null;
  requested_at: string | null;
  updated_at: string | null;
}

interface VoiceOption {
  provider: string;
  tts_model: string;
  voice_model_id: string;
  display_name: string;
}

interface ProsodyInput {
  speed?: number;
  volume?: number;
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const FISH_AUDIO_API_KEY = Deno.env.get('FISH_AUDIO_API_KEY');

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !FISH_AUDIO_API_KEY) {
  console.error('Missing required environment variables for generate-voiceover', {
    hasSupabaseURL: Boolean(SUPABASE_URL),
    hasServiceRole: Boolean(SUPABASE_SERVICE_ROLE_KEY),
    hasFishKey: Boolean(FISH_AUDIO_API_KEY),
  });
}

serve(async req => {
  const correlationId = crypto.randomUUID();
  const logger = createLogger({ fn: 'generate-voiceover', correlationId });
  const corsHeaders = buildCorsHeaders(req.headers.get('Origin'));
  const baseHeaders = {
    ...corsHeaders,
    'X-Correlation-Id': correlationId,
    'Access-Control-Allow-Methods': 'GET, OPTIONS, POST',
  };

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: baseHeaders });
  }

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !FISH_AUDIO_API_KEY) {
    logger.error('Missing configuration');
    return jsonResponse(baseHeaders, { error: 'server_error', message: 'Missing server configuration.' }, 500);
  }

  const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return jsonResponse(baseHeaders, { error: 'not_authenticated', message: 'Missing Authorization header.' }, 401);
    }
    const token = authHeader.replace(/^Bearer\s+/i, '').trim();
    if (!token) {
      return jsonResponse(baseHeaders, { error: 'not_authenticated', message: 'Missing bearer token.' }, 401);
    }

    const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(token);
    if (userError || !userData?.user) {
      logger.warn('User authentication failed', { errorMessage: userError?.message });
      return jsonResponse(baseHeaders, { error: 'not_authenticated', message: 'User is not authenticated.' }, 401);
    }

    const userId = userData.user.id;
    logger.info('Request received', { userId: maskId(userId) });

    let payload: any;
    try {
      payload = await req.json();
    } catch {
      return jsonResponse(baseHeaders, { error: 'invalid_payload', message: 'Request body must be JSON.' }, 400);
    }

    const discoveryId = Number(payload?.discovery_id);
    const voiceModelId = payload?.voice_model_id ? String(payload.voice_model_id) : '';
    const ttsModel = payload?.tts_model ? String(payload.tts_model) : 's1';
    const prosody: ProsodyInput | undefined = payload?.prosody;

    if (!Number.isFinite(discoveryId) || discoveryId <= 0) {
      return jsonResponse(baseHeaders, { error: 'invalid_payload', message: 'discovery_id is required.' }, 422);
    }
    if (!voiceModelId) {
      return jsonResponse(baseHeaders, { error: 'invalid_payload', message: 'voice_model_id is required.' }, 422);
    }

    const voiceOptions = await fetchVoiceOptions(supabaseAdmin, logger);
    logger.debug('Voice options fetched', { count: voiceOptions.length });
    const voice = voiceOptions.find(
      option => option.tts_model === ttsModel && option.voice_model_id === voiceModelId
    );
    if (!voice) {
      logger.warn('Invalid voice selection', { ttsModel, voiceModelId });
      return jsonResponse(
        baseHeaders,
        { error: 'invalid_voice', message: 'Unknown voice selection.' },
        422
      );
    }

    const discoveryText = await fetchDiscoveryText(supabaseAdmin, discoveryId, userId, logger);
    if (!discoveryText) {
      return jsonResponse(baseHeaders, { error: 'not_found', message: 'Discovery not found.' }, 404);
    }

    const sanitizedText = stripEmojis(discoveryText).trim();
    if (!sanitizedText) {
      logger.warn('Empty discovery description', { discoveryId });
      return jsonResponse(
        baseHeaders,
        { error: 'invalid_discovery', message: 'Discovery description is empty.' },
        422
      );
    }

    logger.info('Starting voiceover request', {
      userId: maskId(userId),
      discoveryId,
      voiceModelId,
      ttsModel,
    });

    const startResult = await supabaseAdmin.rpc('start_voiceover_request', {
      p_user_id: userId,
      p_discovery_id: discoveryId,
      p_tts_model: ttsModel,
      p_voice_model_id: voiceModelId,
    });

    if (startResult.error) {
      const message = startResult.error?.message ?? 'start_voiceover_request failed';
      if (message.includes('insufficient_credits')) {
        const balance = await fetchCreditBalance(supabaseAdmin, userId, logger);
        return jsonResponse(
          baseHeaders,
          { error: 'insufficient_credits', message: 'Not enough credits.', credit_balance: balance },
          402
        );
      }
      if (message.includes('discovery_not_found_or_unauthorized')) {
        return jsonResponse(baseHeaders, { error: 'not_found', message: 'Discovery not found.' }, 404);
      }
      logger.error('start_voiceover_request error', { errorMessage: message });
      return jsonResponse(baseHeaders, { error: 'server_error', message: 'Unable to start voiceover.' }, 500);
    }

    let row = (startResult.data as VoiceoverRow) ?? null;
    if (!row) {
      logger.error('start_voiceover_request returned no row');
      return jsonResponse(baseHeaders, { error: 'server_error', message: 'Unexpected response.' }, 500);
    }

    const now = Date.now();
    const updatedAtMs = row.updated_at ? Date.parse(row.updated_at) : 0;
    const isFreshInsert = row.status === 'processing' &&
      Math.abs(now - (row.requested_at ? Date.parse(row.requested_at) : now)) < 5_000;
    let wasExistingResponse = !isFreshInsert;
    let creditBalance: number | null = null;

    if (row.status === 'ready') {
      const { audioUrl, expiresAt } = await signAudioUrl(supabaseAdmin, row, logger);
       logger.info('Returning ready voiceover', { discoveryId, voiceoverId: row.id });
      creditBalance = await fetchCreditBalance(supabaseAdmin, userId, logger);
      return jsonResponse(
        baseHeaders,
        {
          ...row,
          audio_url: audioUrl,
          audio_url_expires_at: expiresAt,
          was_refunded: false,
          was_existing: true,
          credit_balance: creditBalance,
        },
        200
      );
    }

    if (row.status === 'processing' && now - updatedAtMs <= PROCESSING_STALE_MS) {
      logger.info('Returning fresh processing row', { discoveryId, voiceoverId: row.id, updatedAt: row.updated_at });
      creditBalance = await fetchCreditBalance(supabaseAdmin, userId, logger);
      return jsonResponse(
        baseHeaders,
        {
          ...row,
          audio_url: null,
          audio_url_expires_at: null,
          was_refunded: false,
          was_existing: true,
          credit_balance: creditBalance,
        },
        200
      );
    }

    const wasFailedStatus = row.status === 'failed';
    if (row.status === 'failed' || row.status === 'processing') {
      logger.info('Restarting processing', { discoveryId, voiceoverId: row.id, previousStatus: row.status, wasFailedStatus });
      const { data: updatedRow, error: updateError } = await supabaseAdmin
        .from('discovery_voiceovers')
        .update({ status: 'processing', error_reason: null, updated_at: new Date().toISOString() })
        .eq('id', row.id)
        .select()
        .single();

      if (updateError || !updatedRow) {
        logger.error('Failed to bump processing state', { errorMessage: updateError?.message });
        return jsonResponse(baseHeaders, { error: 'server_error', message: 'Unable to update voiceover.' }, 500);
      }
      row = updatedRow as VoiceoverRow;
    }

    if (wasFailedStatus) {
      logger.info('Recharging credit for failed row', { discoveryId, voiceoverId: row.id });
      const balanceResult = await supabaseAdmin.rpc('consume_credit_for_voiceover', {
        p_user_id: userId,
        p_credits_to_consume: 1,
      });
      if (balanceResult.error) {
        if (String(balanceResult.error.message || '').includes('insufficient_credits')) {
          await markFailed(supabaseAdmin, row.id, 'insufficient_credits', logger);
          creditBalance = await fetchCreditBalance(supabaseAdmin, userId, logger);
          return jsonResponse(
            baseHeaders,
            { error: 'insufficient_credits', message: 'Not enough credits.', credit_balance: creditBalance },
            402
          );
        }
        logger.error('consume_credit_for_voiceover failed', { errorMessage: balanceResult.error.message });
        return jsonResponse(baseHeaders, { error: 'server_error', message: 'Unable to consume credit.' }, 500);
      }
      creditBalance = (balanceResult.data as number) ?? null;
      wasExistingResponse = true;
    } else if (isFreshInsert) {
      creditBalance = await fetchCreditBalance(supabaseAdmin, userId, logger);
    }

    const { audioBuffer, upstreamStatus, upstreamError } = await callFishAudio(
      sanitizedText,
      row.voice_model_id,
      row.tts_model,
      prosody,
      logger
    );
    if (!audioBuffer) {
      logger.error('Fish Audio call failed', {
        discoveryId,
        voiceoverId: row.id,
        upstreamStatus,
        upstreamError,
      });
    } else {
      logger.info('Fish Audio call succeeded', { discoveryId, voiceoverId: row.id, bytes: audioBuffer.byteLength });
    }

    if (!audioBuffer) {
      await handleFailure(
        supabaseAdmin,
        row,
        upstreamError || 'fish_audio_failed',
        userId,
        logger
      );
      const status = upstreamStatus && [429, 502, 503].includes(upstreamStatus) ? upstreamStatus : 500;
      return jsonResponse(
        baseHeaders,
        {
          ...row,
          status: 'failed',
          error_reason: upstreamError || 'voiceover_failed',
          audio_url: null,
          audio_url_expires_at: null,
          was_refunded: true,
          was_existing: wasExistingResponse,
          credit_balance: await fetchCreditBalance(supabaseAdmin, userId, logger),
        },
        status
      );
    }

    const uploadResult = await uploadAudio(
      supabaseAdmin,
      row.discovery_id,
      row.file_name,
      audioBuffer,
      logger
    );
    logger.info('Upload result', { discoveryId, voiceoverId: row.id, success: uploadResult.success, error: uploadResult.error });
    if (!uploadResult.success) {
      await handleFailure(
        supabaseAdmin,
        row,
        uploadResult.error ?? 'upload_failed',
        userId,
        logger
      );
      return jsonResponse(
        baseHeaders,
        {
          ...row,
          status: 'failed',
          error_reason: uploadResult.error ?? 'upload_failed',
          audio_url: null,
          audio_url_expires_at: null,
          was_refunded: true,
          was_existing: wasExistingResponse,
          credit_balance: await fetchCreditBalance(supabaseAdmin, userId, logger),
        },
        500
      );
    }

    const { data: readyRow, error: updateReadyError } = await supabaseAdmin
      .from('discovery_voiceovers')
      .update({ status: 'ready', error_reason: null, updated_at: new Date().toISOString() })
      .eq('id', row.id)
      .select()
      .single();

    if (updateReadyError || !readyRow) {
      logger.error('Failed to mark ready', { errorMessage: updateReadyError?.message });
      return jsonResponse(
        baseHeaders,
        { error: 'server_error', message: 'Unable to finalize voiceover.' },
        500
      );
    }

    const { audioUrl, expiresAt } = await signAudioUrl(supabaseAdmin, readyRow as VoiceoverRow, logger);
    creditBalance = creditBalance ?? await fetchCreditBalance(supabaseAdmin, userId, logger);

    logger.info('Voiceover ready', { discoveryId, voiceoverId: row.id, audioUrlPresent: Boolean(audioUrl) });

    return jsonResponse(
      baseHeaders,
      {
        ...(readyRow as VoiceoverRow),
        audio_url: audioUrl,
        audio_url_expires_at: expiresAt,
        was_refunded: false,
        was_existing: wasExistingResponse,
        credit_balance: creditBalance,
      },
      200
    );
  } catch (error) {
    logger.error('Unhandled error', { errorMessage: error instanceof Error ? error.message : String(error) });
    return jsonResponse(baseHeaders, { error: 'server_error', message: 'Unexpected error.' }, 500);
  }
});

const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

const maskId = (value: string) => {
  if (!value) return value;
  if (value.length <= 8) {
    return `${value.slice(0, Math.max(1, value.length - 1))}…`;
  }
  return `${value.slice(0, 4)}…${value.slice(-4)}`;
};

const stripEmojis = (input: string): string => {
  return input.replace(/[\p{Emoji_Presentation}\p{Extended_Pictographic}]/gu, '');
};

const jsonResponse = (headers: HeadersInit, body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json' },
  });

async function fetchVoiceOptions(client: SupabaseClient, logger: Logger): Promise<VoiceOption[]> {
  const { data, error } = await client.rpc('get_voice_options');
  if (error) {
    logger.error('get_voice_options failed', { errorMessage: error.message });
    return [];
  }
  return (data as VoiceOption[]) ?? [];
}

async function fetchDiscoveryText(
  client: SupabaseClient,
  discoveryId: number,
  userId: string,
  logger: Logger
): Promise<string | null> {
  const { data, error } = await client
    .from('discoveries')
    .select('description')
    .eq('id', discoveryId)
    .eq('user_id', userId)
    .single();

  if (error || !data) {
    logger.warn('Discovery not found for user', { discoveryId, userId: maskId(userId), errorMessage: error?.message });
    return null;
  }
  return data.description as string;
}

async function fetchCreditBalance(client: SupabaseClient, userId: string, logger: Logger): Promise<number | null> {
  const { data, error } = await client
    .from('user_credits')
    .select('credit_balance')
    .eq('user_id', userId)
    .single();

  if (error) {
    logger.warn('Failed to fetch credit balance', { errorMessage: error.message });
    return null;
  }
  return (data?.credit_balance as number) ?? null;
}

async function signAudioUrl(
  client: SupabaseClient,
  row: VoiceoverRow,
  logger: Logger
): Promise<{ audioUrl: string | null; expiresAt: string | null }> {
  if (row.status !== 'ready') {
    return { audioUrl: null, expiresAt: null };
  }

  const path = `${row.discovery_id}/${row.file_name}`;
  const { data, error } = await client.storage
    .from(STORAGE_BUCKET)
    .createSignedUrl(path, SIGNED_URL_TTL_SECONDS);

  if (error) {
    logger.error('Failed to create signed URL', { errorMessage: error.message, path });
    return { audioUrl: null, expiresAt: null };
  }

  const expiresAt = new Date(Date.now() + SIGNED_URL_TTL_SECONDS * 1000).toISOString();
  return { audioUrl: data?.signedUrl ?? null, expiresAt };
}

async function callFishAudio(
  text: string,
  voiceModelId: string,
  ttsModel: string,
  prosody: ProsodyInput | undefined,
  logger: Logger
): Promise<{ audioBuffer: Uint8Array | null; upstreamStatus?: number; upstreamError?: string }> {
  const startedAt = Date.now();
  let lastError: string | undefined;
  let lastStatus: number | undefined;

  for (const backoff of BACKOFF_STEPS_MS) {
    const attempt = BACKOFF_STEPS_MS.indexOf(backoff) + 1;
    const elapsed = Date.now() - startedAt;
    if (elapsed + backoff >= EDGE_BUDGET_MS) {
      break;
    }
    if (backoff > 0) {
      await delay(backoff);
    }
    const remainingBudget = EDGE_BUDGET_MS - (Date.now() - startedAt);
    const signal = AbortSignal.timeout(Math.max(1_000, remainingBudget));
    logger.info('Calling Fish Audio', {
      attempt,
      voiceModelId,
      ttsModel,
      remainingBudgetMs: remainingBudget
    });
    try {
      const payload: Record<string, unknown> = {
        text,
        reference_id: voiceModelId,
        format: 'mp3',
        normalize: true,
        chunk_length: 200,
        tts_model: ttsModel,
      };
      if (prosody && (prosody.speed !== undefined || prosody.volume !== undefined)) {
        payload.prosody = prosody;
      }

      const response = await fetch(FISH_TTS_URL, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${FISH_AUDIO_API_KEY}`,
          'Content-Type': 'application/msgpack',
          model: ttsModel,
        },
        body: encode(payload),
        signal,
      });

      if (!response.ok) {
        lastStatus = response.status;
        const errorText = await safeReadText(response);
        lastError = errorText || `fish_audio_${response.status}`;
        logger.warn('Fish Audio error', { status: response.status, message: lastError, attempt });
        if ([429, 500, 502, 503].includes(response.status)) {
          continue;
        }
        return { audioBuffer: null, upstreamStatus: response.status, upstreamError: lastError };
      }

      const arrayBuffer = await response.arrayBuffer();
      return { audioBuffer: new Uint8Array(arrayBuffer) };
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
      logger.warn('Fish Audio request failed', { errorMessage: lastError, attempt });
      continue;
    }
  }

  return { audioBuffer: null, upstreamStatus: lastStatus, upstreamError: lastError };
}

async function safeReadText(response: Response): Promise<string | null> {
  try {
    return await response.text();
  } catch {
    return null;
  }
}

async function uploadAudio(
  client: SupabaseClient,
  discoveryId: number,
  fileName: string,
  audio: Uint8Array,
  logger: Logger
): Promise<{ success: boolean; error?: string }> {
  const path = `${discoveryId}/${fileName}`;
  const blob = new Blob([audio], { type: 'audio/mpeg' });
  const { error } = await client.storage
    .from(STORAGE_BUCKET)
    .upload(path, blob, {
      contentType: 'audio/mpeg',
      upsert: false,
    });

  if (error) {
    // If the file already exists, treat it as success to avoid overwriting.
    if (String(error.message || '').toLowerCase().includes('exists')) {
      logger.info('Audio already exists, reusing', { path });
      return { success: true };
    }
    logger.error('Failed to upload audio', { path, errorMessage: error.message });
    return { success: false, error: error.message };
  }
  return { success: true };
}

async function markFailed(
  client: SupabaseClient,
  rowId: number,
  reason: string,
  logger: Logger
): Promise<void> {
  const { error } = await client
    .from('discovery_voiceovers')
    .update({ status: 'failed', error_reason: reason, updated_at: new Date().toISOString() })
    .eq('id', rowId);
  if (error) {
    logger.error('Failed to mark row failed', { errorMessage: error.message, rowId });
  }
}

async function handleFailure(
  client: SupabaseClient,
  row: VoiceoverRow,
  reason: string,
  userId: string,
  logger: Logger
): Promise<void> {
  await markFailed(client, row.id, reason, logger);
  const { error } = await client.rpc('refund_credit_for_voiceover', {
    p_user_id: userId,
    p_credits_to_refund: 1,
  });
  if (error) {
    logger.error('Refund failed', { errorMessage: error.message });
  } else {
    logger.info('Refund issued after failure', { discoveryId: row.discovery_id, userId: maskId(userId) });
  }
}
