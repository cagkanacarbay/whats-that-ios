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
// Keep within the 150s idle timeout; leave a small buffer.
const EDGE_BUDGET_MS = 145_000;
const BACKOFF_STEPS_MS = [0, 1000, 2000, 4000, 8000];

// Rate limiting configuration
const RATE_LIMIT_WINDOW_SECONDS = 60;
const RATE_LIMIT_MAX_REQUESTS = 5;

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

    // Rate limit check - before processing request
    const { data: rateLimitAllowed, error: rateLimitError } = await supabaseAdmin.rpc(
      'enforce_edge_function_rate_limit',
      {
        p_user_id: userId,
        p_function_name: 'generate-voiceover',
        p_window_seconds: RATE_LIMIT_WINDOW_SECONDS,
        p_max_requests: RATE_LIMIT_MAX_REQUESTS,
      }
    );

    if (rateLimitError) {
      logger.error('Rate limit check failed', { errorMessage: rateLimitError.message });
      return jsonResponse(baseHeaders, { error: 'rate_limit_error', message: 'Unable to check rate limit.' }, 500);
    }

    if (!rateLimitAllowed) {
      logger.warn('Rate limit exceeded', { userId: maskId(userId) });
      return jsonResponse(
        baseHeaders,
        { error: 'rate_limited', message: `Too many requests. Please wait a moment and try again.` },
        429
      );
    }

    let payload: any;
    try {
      payload = await req.json();
    } catch {
      return jsonResponse(baseHeaders, { error: 'invalid_payload', message: 'Request body must be JSON.' }, 400);
    }

    const discoveryId = Number(payload?.discovery_id);
    const voiceModelId = payload?.voice_model_id ? String(payload.voice_model_id) : '';
    const ttsModel = payload?.tts_model ? String(payload.tts_model) : 's1';

    if (!Number.isFinite(discoveryId) || discoveryId <= 0) {
      return jsonResponse(baseHeaders, { error: 'invalid_payload', message: 'discovery_id is required.' }, 422);
    }
    if (!voiceModelId) {
      return jsonResponse(baseHeaders, { error: 'invalid_payload', message: 'voice_model_id is required.' }, 422);
    }

    const acceptsAudio = req.headers.get('Accept')?.includes('audio/mpeg') ?? false;

    const [voiceOptions, discoveryData] = await Promise.all([
      fetchVoiceOptions(supabaseAdmin, logger),
      fetchDiscoveryData(supabaseAdmin, discoveryId, userId, logger),
    ]);

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

    const { title, description } = discoveryData;
    if (!description) {
      return jsonResponse(baseHeaders, { error: 'not_found', message: 'Discovery not found.' }, 404);
    }

    const sanitizedText = cleanVoiceoverText(title, description, logger);
    logger.debug('Normalized discovery text', {
      normalizedText: sanitizedText,
      length: sanitizedText.length,
    });
    if (!sanitizedText) {
      logger.warn('Empty discovery description', { discoveryId });
      return jsonResponse(
        baseHeaders,
        { error: 'invalid_discovery', message: 'Discovery description is empty.' },
        422
      );
    }

    const startResult = await supabaseAdmin.rpc('start_voiceover_request', {
      p_user_id: userId,
      p_discovery_id: discoveryId,
      p_tts_model: ttsModel,
      p_voice_model_id: voiceModelId,
    });

    if (startResult.error) {
      const message = startResult.error?.message ?? 'start_voiceover_request failed';
      if (message.includes('insufficient_credits')) {
        // For insufficient credits, we still need to fetch balance since the RPC threw an error
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

    // Extract from composite type: { voiceover, credit_balance, was_existing }
    const resultData = startResult.data as { voiceover: VoiceoverRow; credit_balance: number | null; was_existing: boolean } | null;
    if (!resultData || !resultData.voiceover) {
      logger.error('start_voiceover_request returned no row');
      return jsonResponse(baseHeaders, { error: 'server_error', message: 'Unexpected response.' }, 500);
    }

    let row = resultData.voiceover;
    const now = Date.now();
    const updatedAtMs = row.updated_at ? Date.parse(row.updated_at) : 0;
    const isFreshInsert = row.status === 'processing' &&
      Math.abs(now - (row.requested_at ? Date.parse(row.requested_at) : now)) < 5_000;
    let wasExistingResponse = resultData.was_existing;
    // Use credit_balance from RPC result (no extra fetch needed)
    let creditBalance: number | null = resultData.credit_balance;

    logger.info('Voiceover row ready for processing', {
      discoveryId,
      voiceoverId: row.id,
      status: row.status,
      isFreshInsert,
      updatedAt: row.updated_at,
      requestedAt: row.requested_at,
    });

    if (row.status === 'ready') {
      const { audioUrl, expiresAt } = await signAudioUrl(supabaseAdmin, row, logger);
      logger.info('Returning existing ready voiceover', { discoveryId, voiceoverId: row.id, audioUrlPresent: Boolean(audioUrl) });
      // creditBalance already set from RPC result
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

    if (
      row.status === 'processing' &&
      now - updatedAtMs <= PROCESSING_STALE_MS &&
      !isFreshInsert
    ) {
      logger.info('Processing already in-flight (<1m); returning as-is', { discoveryId, voiceoverId: row.id, updatedAt: row.updated_at });
      // creditBalance already set from RPC result
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
      const reason =
        wasFailedStatus ? 'retry_failed' : isFreshInsert ? 'new_row_continues' : 'stale_processing_retry';
      logger.info('Setting status=processing in DB', {
        discoveryId,
        voiceoverId: row.id,
        previousStatus: row.status,
        reason,
        wasFailedStatus,
        wasPreviouslyProcessing: row.status === 'processing',
      });
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
      logger.info('Charging credit for retry of failed row', { discoveryId, voiceoverId: row.id });
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
      logger.info('Credit charged for retry', { discoveryId, voiceoverId: row.id, creditBalance });
      wasExistingResponse = true;
    } else if (isFreshInsert) {
      // creditBalance already set from RPC result (no extra fetch needed)
    }

    if (acceptsAudio) {
      // STREAMING DIRECT AUDIO PATH: Pipe Fish Audio response stream to client
      const streamingResult = await callFishAudioStreaming(
        sanitizedText,
        row.voice_model_id,
        row.tts_model,
        logger
      );

      if (!streamingResult.response) {
        logger.error('Fish Audio streaming returned failure', {
          discoveryId,
          voiceoverId: row.id,
          upstreamStatus: streamingResult.upstreamStatus,
          upstreamError: streamingResult.upstreamError,
        });
        await handleFailure(
          supabaseAdmin,
          row,
          streamingResult.upstreamError || 'fish_audio_failed',
          userId,
          logger
        );
        const status = streamingResult.upstreamStatus && [429, 502, 503].includes(streamingResult.upstreamStatus) ? streamingResult.upstreamStatus : 500;
        return jsonResponse(
          baseHeaders,
          {
            ...row,
            status: 'failed',
            error_reason: streamingResult.upstreamError || 'voiceover_failed',
            audio_url: null,
            audio_url_expires_at: null,
            was_refunded: true,
            was_existing: wasExistingResponse,
            credit_balance: await fetchCreditBalance(supabaseAdmin, userId, logger),
          },
          status
        );
      }

      creditBalance = creditBalance ?? await fetchCreditBalance(supabaseAdmin, userId, logger);

      // Decouple Fish Audio consumption from client connection.
      // Read Fish Audio manually so client disconnect does NOT abort the download.
      const fishBody = streamingResult.response!.body!;
      const reader = fishBody.getReader();
      const accumulatedChunks: Uint8Array[] = [];
      let fishReadError: string | null = null;
      let clientClosed = false;

      // Client-facing stream: pushes chunks opportunistically, survives disconnect
      let clientController: ReadableStreamDefaultController<Uint8Array> | null = null;
      const clientStream = new ReadableStream<Uint8Array>({
        start(controller) {
          clientController = controller;
        },
        cancel() {
          clientClosed = true;
          logger.info('Client disconnected during streaming', { discoveryId, voiceoverId: row.id });
        },
      });

      // Consume ALL Fish Audio chunks regardless of client state
      const consumeFishAudio = async () => {
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            const chunk = new Uint8Array(value);
            accumulatedChunks.push(chunk);

            // Forward to client if still connected
            if (!clientClosed && clientController) {
              try {
                clientController.enqueue(chunk);
              } catch {
                clientClosed = true;
              }
            }
          }
          // Close client stream if still connected
          if (!clientClosed && clientController) {
            try { clientController.close(); } catch { /* already closed */ }
          }
        } catch (err) {
          fishReadError = err instanceof Error ? err.message : String(err);
          logger.error('Fish Audio stream read error', { discoveryId, voiceoverId: row.id, error: fishReadError });
          if (!clientClosed && clientController) {
            try { clientController.error(new Error(fishReadError)); } catch { /* already closed */ }
          }
        }
      };

      // Start consuming immediately (runs as microtask)
      const consumePromise = consumeFishAudio();

      // Background: after Fish Audio is fully consumed, upload to storage and mark ready
      EdgeRuntime.waitUntil(
        consumePromise.then(async () => {
          if (fishReadError) {
            await handleFailure(supabaseAdmin, row, `stream_error: ${fishReadError}`, userId, logger);
            return;
          }

          const totalLength = accumulatedChunks.reduce((sum, c) => sum + c.length, 0);
          if (totalLength === 0) {
            await handleFailure(supabaseAdmin, row, 'empty_audio_stream', userId, logger);
            return;
          }

          const audioBuffer = new Uint8Array(totalLength);
          let offset = 0;
          for (const chunk of accumulatedChunks) {
            audioBuffer.set(chunk, offset);
            offset += chunk.length;
          }

          logger.info('Stream complete, uploading to storage', {
            discoveryId, voiceoverId: row.id, bytes: totalLength, clientDisconnected: clientClosed,
          });

          const uploadResult = await uploadAudio(supabaseAdmin, row.discovery_id, row.file_name, audioBuffer, logger);
          if (!uploadResult.success) {
            logger.error('Background upload failed after stream', { discoveryId, voiceoverId: row.id, error: uploadResult.error });
            // Don't mark failed — DB row stays processing, stale timeout will handle it
            return;
          }

          const { error: updateReadyError } = await supabaseAdmin
            .from('discovery_voiceovers')
            .update({ status: 'ready', error_reason: null, updated_at: new Date().toISOString() })
            .eq('id', row.id);

          if (updateReadyError) {
            logger.error('Failed to mark ready after stream', { errorMessage: updateReadyError.message });
          } else {
            logger.info('Background upload and mark-ready completed', { discoveryId, voiceoverId: row.id });
          }
        }).catch(err => logger.error('Background stream handler error', { error: err instanceof Error ? err.message : String(err) }))
      );

      logger.info('Returning streaming audio response', { discoveryId, voiceoverId: row.id });

      return new Response(clientStream, {
        status: 200,
        headers: {
          ...baseHeaders,
          'Content-Type': 'audio/mpeg',
          'Transfer-Encoding': 'chunked',
          'X-Voiceover-Id': String(row.id),
          'X-Discovery-Id': String(row.discovery_id),
          'X-Voiceover-Status': 'processing',
          'X-Credit-Balance': String(creditBalance ?? ''),
          'X-Was-Refunded': 'false',
          'X-Was-Existing': String(wasExistingResponse),
          'X-File-Name': row.file_name,
          'X-File-Extension': row.file_extension,
          'X-Provider': row.provider,
          'X-TTS-Model': row.tts_model,
          'X-Voice-Model-Id': row.voice_model_id,
        },
      });

    } else {
      // NON-STREAMING PATH: Buffer entire audio, then return
      const { audioBuffer, upstreamStatus, upstreamError } = await callFishAudio(
        sanitizedText,
        row.voice_model_id,
        row.tts_model,
        logger
      );
      if (!audioBuffer) {
        logger.error('Fish Audio returned failure', {
          discoveryId,
          voiceoverId: row.id,
          upstreamStatus,
          upstreamError,
        });
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
      logger.info('Fish Audio returned successfully', { discoveryId, voiceoverId: row.id, bytes: audioBuffer.byteLength });
      // EXISTING JSON PATH: Upload first, then return signed URL
      const uploadResult = await uploadAudio(
        supabaseAdmin,
        row.discovery_id,
        row.file_name,
        audioBuffer,
        logger
      );
      logger.info('Uploaded audio to storage', { discoveryId, voiceoverId: row.id, success: uploadResult.success, error: uploadResult.error, path: `${row.discovery_id}/${row.file_name}` });
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

      logger.info('Voiceover marked ready and signed URL issued', {
        discoveryId,
        voiceoverId: row.id,
        audioUrlPresent: Boolean(audioUrl),
        expiresAt,
      });

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
    }
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

const cleanVoiceoverText = (title: string, description: string, logger: Logger): string => {
  // 1. Clean Title: strip emojis
  const cleanedTitle = stripEmojis(title).trim();

  // 2. Clean Description:
  //    - Strip emojis
  //    - Remove H2 headers (lines starting with ##) and replace with (long-break)
  const descriptionNoEmojis = stripEmojis(description);
  const descriptionLines = descriptionNoEmojis.split(/\r?\n/);

  const cleanedDescriptionLines = descriptionLines.map(line => {
    // Match line starting with ##
    if (line.trim().startsWith('##')) {
      return '(long-break)';
    }
    return line;
  });

  const cleanedDescription = cleanedDescriptionLines.join(' ');

  // 3. Combine: Title + Description (Description starts with H2 -> long-break, so no extra break needed here)
  const combinedText = `${cleanedTitle} ${cleanedDescription}`;

  // 4. Normalize whitespace and breaks
  return combinedText
    .replace(/[\r\n]+/g, ' ')
    .replace(/\*+/g, '')  // Remove asterisks (markdown bold/italic)
    .replace(/\s+/g, ' ')
    // Normalize breaks - ensure we don't have multiple long-breaks in a row
    // and that they have proper spacing
    .replace(/\(long-break\)(\s*\(long-break\))+/g, '(long-break)')
    .trim();
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

async function fetchDiscoveryData(
  client: SupabaseClient,
  discoveryId: number,
  userId: string,
  logger: Logger
): Promise<{ title: string; description: string }> {
  const { data, error } = await client
    .from('discoveries')
    .select('title, description')
    .eq('id', discoveryId)
    .eq('user_id', userId)
    .single();

  if (error || !data) {
    logger.warn('Discovery not found for user', { discoveryId, userId: maskId(userId), errorMessage: error?.message });
    return { title: '', description: '' };
  }
  return { title: data.title as string, description: data.description as string };
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

async function callFishAudioStreaming(
  text: string,
  voiceModelId: string,
  ttsModel: string,
  logger: Logger
): Promise<{ response: Response | null; upstreamStatus?: number; upstreamError?: string }> {
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
    logger.info('Calling Fish Audio (streaming)', {
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

      const fishResponse = await fetch(FISH_TTS_URL, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${FISH_AUDIO_API_KEY}`,
          'Content-Type': 'application/msgpack',
          model: ttsModel,
        },
        body: encode(payload),
        signal,
      });

      if (!fishResponse.ok) {
        lastStatus = fishResponse.status;
        const errorText = await safeReadText(fishResponse);
        lastError = errorText || `fish_audio_${fishResponse.status}`;
        logger.warn('Fish Audio streaming error', { status: fishResponse.status, message: lastError, attempt });
        if ([429, 500, 502, 503].includes(fishResponse.status)) {
          continue;
        }
        return { response: null, upstreamStatus: fishResponse.status, upstreamError: lastError };
      }

      // Return the raw response — caller will pipe body stream
      return { response: fishResponse };
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
      logger.warn('Fish Audio streaming request failed', { errorMessage: lastError, attempt });
      continue;
    }
  }

  return { response: null, upstreamStatus: lastStatus, upstreamError: lastError };
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
