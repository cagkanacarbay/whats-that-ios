// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, SupabaseClient } from 'npm:@supabase/supabase-js@2';
import Anthropic from 'npm:@anthropic-ai/sdk';
import OpenAI from 'npm:openai';
import { SignJWT, importPKCS8 } from 'npm:jose';
import { assemblePrompt } from './promptLoader.ts';
import { extractLocationInfo, HandleNearbyPlacesLocation, Place } from './places.ts';
import { systemPromptMetadata } from './prompts/system-prompt.ts';
import { userPromptMetadata } from './prompts/user-prompt.ts';
import { createSSEStream } from './stream.ts';
import { buildCorsHeaders } from '../_shared/cors.ts';
import { createLogger } from '../_shared/logger.ts';
import type { Logger } from '../_shared/logger.ts';

// --- Constants ---
const CREDITS_PER_DISCOVERY = 1;
const GEMINI_MODEL = "gemini-3-flash-preview";
const OPENAI_MODEL = "gpt-5-mini";
const CLAUDE_MODEL = "claude-3-5-sonnet-20241022";
const STREAM_RETRY_LIMIT = 3;

// Rate limiting configuration
const RATE_LIMIT_WINDOW_SECONDS = 60;
const RATE_LIMIT_MAX_REQUESTS = 10;

// Utility: mask an identifier by showing beginning and end
function maskId(value: string): string {
  if (!value) return value;
  if (value.length <= 8) {
    return `${value.slice(0, Math.max(1, value.length - 1))}…`;
  }
  return `${value.slice(0, 4)}…${value.slice(-4)}`;
}

// --- Helper: Retry API calls with backoff ---
async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  logger: Logger,
  maxRetries = 3,
  modelName = 'API'
) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error: any) {
      if ((error?.status === 429 || error?.status === 529) && i < maxRetries - 1) {
        const waitMs = Math.pow(2, i) * 1000;
        logger.warn('Upstream API overloaded, retrying', {
          modelName,
          status: error?.status,
          retryInMs: waitMs,
          attempt: i + 1,
          maxRetries,
        });
        await new Promise((resolve) => setTimeout(resolve, waitMs));
        continue;
      }
      throw error;
    }
  }
  throw new Error(`${modelName} call failed after ${maxRetries} retries.`);
}

// --- Helper: Create Supabase Admin Client ---
function createAdminClient(): SupabaseClient {
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error('Missing Supabase environment variables.');
  }

  return createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
}

// --- Helper: Create APNs JWT using jose ---
async function createApnsJwt(logger: Logger): Promise<string> {
  const teamId = Deno.env.get('APNS_TEAM_ID');
  const keyId = Deno.env.get('APNS_KEY_ID');
  const privateKey = Deno.env.get('APNS_PRIVATE_KEY');

  if (!teamId || !keyId || !privateKey) {
    logger.error('APNs credentials not configured', {
      hasTeamId: Boolean(teamId),
      hasKeyId: Boolean(keyId),
      hasPrivateKey: Boolean(privateKey),
    });
    throw new Error('APNs credentials not configured.');
  }

  const algorithm = 'ES256';
  const pkcs8 = privateKey.trim();
  const key = await importPKCS8(pkcs8, algorithm);

  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({})
    .setProtectedHeader({ alg: algorithm, kid: keyId })
    .setIssuedAt(now)
    .setIssuer(teamId)
    .sign(key);
}

// --- Helper: Send Push Notification via APNs ---
async function sendApnsPushNotification(
  deviceToken: string,
  title: string,
  body: string,
  discoveryId: string,
  logger: Logger,
  requestBundleId?: string // Optional: if provided and valid, use it; otherwise use default
): Promise<boolean> {
  // Support comma-separated list of bundle IDs for multi-app support
  const allowedBundleIds = (Deno.env.get('APNS_BUNDLE_ID') || '')
    .split(',')
    .map(id => id.trim())
    .filter(id => id.length > 0);
  const environment = (Deno.env.get('APNS_ENVIRONMENT') || 'sandbox').toLowerCase();

  if (allowedBundleIds.length === 0) {
    logger.error('APNs bundle ID not configured');
    return false;
  }

  // Use the requested bundle ID if provided and valid; otherwise use the first (default/old app)
  let bundleId: string;
  if (requestBundleId && allowedBundleIds.includes(requestBundleId)) {
    bundleId = requestBundleId;
  } else {
    bundleId = allowedBundleIds[0]; // Default to first (old app)
    if (requestBundleId) {
      logger.warn('Requested bundle ID not in allowed list, using default', {
        requestBundleId,
        defaultBundleId: bundleId
      });
    }
  }

  const host =
    environment === 'production'
      ? 'https://api.push.apple.com'
      : 'https://api.sandbox.push.apple.com';

  const url = `${host}/3/device/${deviceToken}`;

  let jwt: string;
  try {
    jwt = await createApnsJwt(logger);
  } catch (error) {
    logger.error('Failed to create APNs JWT', {
      errorMessage: error instanceof Error ? error.message : String(error),
    });
    return false;
  }

  const payload = {
    aps: {
      alert: {
        title,
        body,
      },
      sound: 'default',
    },
    discoveryId,
    type: 'discovery_complete',
  };

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        authorization: `bearer ${jwt}`,
        'apns-topic': bundleId,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'content-type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    const responseText = await response.text();
    let responseJson: any = undefined;
    try {
      responseJson = responseText ? JSON.parse(responseText) : undefined;
    } catch {
      // non-JSON response; keep raw text for logs
    }

    if (response.ok) {
      logger.info('APNs push notification sent successfully', {
        deviceTokenSuffix: deviceToken.slice(-6),
        discoveryId,
      });
      return true;
    }

    logger.error('APNs push API error', {
      deviceTokenSuffix: deviceToken.slice(-6),
      discoveryId,
      httpStatus: response.status,
      reason: (responseJson?.reason ?? responseText) || 'Unknown',
    });
    return false;
  } catch (error) {
    logger.error('Failed to send APNs push notification', {
      deviceTokenSuffix: deviceToken.slice(-6),
      discoveryId,
      errorMessage: error instanceof Error ? error.message : String(error),
    });
    return false;
  }
}

// --- Helper: Dispatch Push Notification (APNs only) ---
async function sendPushNotification(
  pushToken: string,
  title: string,
  body: string,
  discoveryId: string,
  logger: Logger,
  bundleId?: string
): Promise<boolean> {
  if (!pushToken) return false;

  return sendApnsPushNotification(pushToken, title, body, discoveryId, logger, bundleId);
}

// --- Helper: Format GPS coordinates ---
function formatCoordinates(latitude: number, longitude: number): string {
  const latDirection = latitude >= 0 ? 'N' : 'S';
  const lonDirection = longitude >= 0 ? 'E' : 'W';
  return `${Math.abs(latitude).toFixed(4)}°${latDirection}, ${Math.abs(longitude).toFixed(4)}°${lonDirection}`;
}

// --- Helper: Calculate distance between two points (Haversine formula) ---
function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371e3; // Earth's radius in meters
  const φ1 = lat1 * Math.PI / 180;
  const φ2 = lat2 * Math.PI / 180;
  const Δφ = (lat2 - lat1) * Math.PI / 180;
  const Δλ = (lon2 - lon1) * Math.PI / 180;

  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
    Math.cos(φ1) * Math.cos(φ2) *
    Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c; // Distance in meters
}

interface RequestBody {
  base64Image: string;
  location?: HandleNearbyPlacesLocation;
  pushToken?: string;
  customContext?: string;
  bundleId?: string; // Optional: for multi-app support, defaults to first ID in APNS_BUNDLE_ID
}

type CustomContextPayload = {
  recentFullDiscoveries?: string;
  aggregatedHistory?: string;
  ipopPreferences?: { ordered?: string[] };
};

const formatIpopPreferences = (ordered: string[]): string => {
  if (!Array.isArray(ordered) || ordered.length === 0) {
    return "";
  }
  const sequence = ordered.join(" -> ");
  return `IPoP preference order: ${sequence}. Primary lens bias: aim ~60/30/10/rare with ranges 45-70% / 20-40% / 5-20% / <=5%. Flip lens selection is independent of this order and may use any IPoP dimension.`;
};

serve(async (req: Request) => {
  const correlationId = crypto.randomUUID();
  const corsHeaders = buildCorsHeaders(req.headers.get('Origin'));
  const baseHeaders = { ...corsHeaders, 'X-Correlation-Id': correlationId } as HeadersInit;
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: baseHeaders });
  }
  const logger = createLogger({ fn: 'ask-ai-v7', correlationId });
  logger.info('Request received', {
    method: req.method,
    hasAuthorizationHeader: Boolean(req.headers.get('Authorization')),
  });

  const authHeader = req.headers.get('Authorization');

  let requestBody: RequestBody;
  try {
    requestBody = await req.json();
  } catch (bodyError) {
    logger.error('Failed to parse request body', {
      errorMessage: bodyError instanceof Error ? bodyError.message : String(bodyError),
    });
    return new Response(
      JSON.stringify({ error: 'Invalid request body' }),
      {
        status: 400,
        headers: {
          ...baseHeaders,
          'Content-Type': 'application/json',
        },
      },
    );
  }

  const { stream, sendEvent, sendComment, close, abort } = createSSEStream(
    logger.child({ scope: 'sse' })
  );
  const headers = new Headers({
    ...corsHeaders,
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });
  headers.set('X-Correlation-Id', correlationId);
  logger.info('SSE stream initialized');

  const response = new Response(stream, {
    status: 200,
    headers,
  });

  const t0 = performance.now();
  (async () => {
    const handlerLogger = logger.child({ scope: 'handler' });
    const supabaseAdmin = createAdminClient();
    let userId: string | null = null;
    let creditsConsumed = false;
    let discoveryId: string | null = null;

    try {
      sendComment(`correlation-id: ${correlationId}`);
      sendEvent('status', { stage: 'init', message: 'Authenticating request…' });

      if (!authHeader) {
        throw new Error('No authorization header');
      }

      const { base64Image, location, pushToken, customContext, bundleId } = requestBody;
      if (!base64Image) {
        throw new Error('Missing base64Image.');
      }

      sendEvent('status', { stage: 'auth', message: 'Verifying session…' });

      const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''));
      if (userError || !user) {
        throw new Error('User authentication failed');
      }
      userId = user.id;
      handlerLogger.info('User authenticated', { userIdMasked: maskId(user.id) });

      // Rate limit check - before consuming credits
      sendEvent('status', { stage: 'rate_limit', message: 'Checking rate limit…' });
      const { data: rateLimitAllowed, error: rateLimitError } = await supabaseAdmin.rpc(
        'enforce_edge_function_rate_limit',
        {
          p_user_id: userId,
          p_function_name: 'ask-ai-v7',
          p_window_seconds: RATE_LIMIT_WINDOW_SECONDS,
          p_max_requests: RATE_LIMIT_MAX_REQUESTS,
        }
      );

      if (rateLimitError) {
        handlerLogger.error('Rate limit check failed', { errorMessage: rateLimitError.message });
        throw new Error('Rate limit check failed');
      }

      if (!rateLimitAllowed) {
        handlerLogger.warn('Rate limit exceeded', { userIdMasked: maskId(user.id) });
        const err = new Error(`Too many requests. Please wait a moment and try again.`);
        (err as any).status = 429;
        throw err;
      }

      sendEvent('status', { stage: 'credits', message: 'Consuming credits…' });

      const { data: consumeResult, error: consumeError } = await supabaseAdmin.rpc('consume_credit_for_discovery', {
        p_user_id: userId,
        p_credits_to_consume: CREDITS_PER_DISCOVERY,
      });

      if (consumeError) {
        if (consumeError.message.includes('insufficient_credits')) {
          const err = new Error('Insufficient credits');
          (err as any).status = 402;
          throw err;
        }
        throw new Error(`Failed to consume credits: ${consumeError.message}`);
      }
      creditsConsumed = true;
      handlerLogger.info('Credit consumed for discovery', { userIdMasked: maskId(user.id) });

      // Use the balance returned directly from the RPC (no extra fetch needed)
      const creditBalance: number | null = typeof consumeResult === 'number' ? consumeResult : null;

      sendEvent('status', { stage: 'preprocess', message: 'Preparing image…' });
      const uint8Array = new Uint8Array(atob(base64Image).split('').map((char) => char.charCodeAt(0)));

      sendEvent('status', { stage: 'context', message: 'Building context…' });
      const locationCoords = location?.location?.coords ?? null;
      const nearbyPlacesData = location?.nearbyPlaces ?? null;
      const nearbyPlacesContext = location?.nearbyPlacesContext ?? null;

      let promptVariables: Record<string, string> = {
        locationContext: "",
        recentFullDiscoveries: "",
        userDiscoveryContext: "",
        customContext: "None provided.",
      };

      let locationInfo: any | null = null;
      let placesData: Place[] | null = null;

      let locationContextParts: string[] = [];

      if (nearbyPlacesContext?.summary) {
        locationContextParts.push(nearbyPlacesContext.summary);
      } else if (nearbyPlacesContext) {
        const distanceParts: string[] = [];
        if (typeof nearbyPlacesContext.distanceMeters === 'number') {
          distanceParts.push(`~${Math.round(nearbyPlacesContext.distanceMeters)}m from cached POIs`);
        }
        if (typeof nearbyPlacesContext.horizontalAccuracyMeters === 'number') {
          distanceParts.push(`accuracy ±${Math.round(nearbyPlacesContext.horizontalAccuracyMeters)}m`);
        }
        if (typeof nearbyPlacesContext.distanceUncertaintyMeters === 'number' &&
          nearbyPlacesContext.distanceUncertaintyMeters !== nearbyPlacesContext.horizontalAccuracyMeters) {
          distanceParts.push(`uncertainty ±${Math.round(nearbyPlacesContext.distanceUncertaintyMeters)}m`);
        }
        if (distanceParts.length > 0) {
          locationContextParts.push(`Nearby places cache: ${distanceParts.join(', ')}`);
        }
      }

      if (locationCoords) {
        const formattedGPS = formatCoordinates(locationCoords.latitude, locationCoords.longitude);

        if (nearbyPlacesData && nearbyPlacesData.length > 0) {
          placesData = nearbyPlacesData as Place[];

          try {
            locationInfo = extractLocationInfo(placesData);

            const placesWithDistance = placesData.map((place) => {
              const distance = calculateDistance(locationCoords.latitude, locationCoords.longitude, place.location.latitude, place.location.longitude);
              return { ...place, distance };
            }).sort((a, b) => a.distance - b.distance);

            let locationDescription = "";
            if (locationInfo) {
              const { city, district, country } = locationInfo;
              if (city && country) {
                locationDescription = district ? `${district} district of ${city}, ${country}` : `${city}, ${country}`;
              } else if (country) {
                locationDescription = country;
              }
            }

            if (locationDescription) {
              locationContextParts.push(`Location: ${locationDescription}`);
            }

            locationContextParts.push(`GPS: ${formattedGPS}`);

            const formattedPlaces = placesWithDistance.map((place) =>
              `- ${place.displayName?.text || 'Unknown'}, ${place.primaryTypeDisplayName?.text?.toLowerCase() || 'type unknown'}, ${Math.round(place.distance)}m`
            ).join('\n');
            locationContextParts.push(`Nearby places (sorted by distance, 40-50m indicates likely inside):\n${formattedPlaces}`);

            const popularPlaceData = placesData[0];
            const popularPlaceDistance = placesWithDistance.find(p => p.id === popularPlaceData.id)?.distance || 0;
            locationContextParts.push(`Most popular nearby place (per Google ranking): ${popularPlaceData.displayName?.text || 'Unknown'}, ${popularPlaceData.primaryTypeDisplayName?.text?.toLowerCase() || 'type unknown'}, ${Math.round(popularPlaceDistance)}m`);
          } catch (processingError) {
            handlerLogger.warn('Nearby places processing failed', {
              errorMessage: processingError instanceof Error ? processingError.message : String(processingError),
            });
            locationContextParts.push(`GPS: ${formattedGPS}`);
            locationContextParts.push("(Nearby places data processing failed)");
          }
        } else {
          locationContextParts.push(`GPS: ${formattedGPS}`);
        }
      } else {
        locationContextParts.push("No location data available for this image.");
      }

      handlerLogger.debug('Location context prepared', {
        hasCoordinates: Boolean(locationCoords),
        cachedPlaces: Boolean(nearbyPlacesData?.length),
        derivedPlaces: placesData?.length ?? 0,
        hasCachedSummary: Boolean(nearbyPlacesContext?.summary),
      });

      promptVariables.locationContext = locationContextParts.join('\n');

      let recentFullDiscoveries = "";
      let aggregatedHistory = "";
      let customContextDisplay = "None provided.";
      let ipopPreferencesText = "";

      if (customContext && customContext.trim()) {
        customContextDisplay = customContext.trim();
        try {
          const contexts = JSON.parse(customContext) as CustomContextPayload;
          if (contexts.recentFullDiscoveries) {
            recentFullDiscoveries = contexts.recentFullDiscoveries;
          }
          if (contexts.aggregatedHistory) {
            aggregatedHistory = contexts.aggregatedHistory;
          }
          if (Array.isArray(contexts.ipopPreferences?.ordered)) {
            const normalizedOrder = (contexts.ipopPreferences?.ordered ?? []).filter(
              (item): item is string => typeof item === "string"
            );
            if (normalizedOrder.length === 4) {
              ipopPreferencesText = formatIpopPreferences(normalizedOrder);
            }
          }
          customContextDisplay = JSON.stringify(contexts, null, 2);
        } catch {
          aggregatedHistory = customContext.trim();
        }
      }

      promptVariables.recentFullDiscoveries = recentFullDiscoveries;
      promptVariables.userDiscoveryContext = aggregatedHistory;
      const customContextParts = [
        customContextDisplay !== "None provided." ? customContextDisplay : "",
        ipopPreferencesText,
      ].filter((part) => part && part.trim().length > 0);
      promptVariables.customContext = customContextParts.length > 0 ? customContextParts.join("\n\n") : "None provided.";

      sendEvent('status', { stage: 'prompt', message: 'Assembling prompt…' });
      const promptLogger = handlerLogger.child({ scope: 'prompt' });
      const { system: systemPrompt, user: userPrompt } = await assemblePrompt('singular', promptVariables, promptLogger);

      type ModelResult = { rawResponse: string; modelUsed: string };
      const TOKEN_BATCH_TARGET = 160;

      const runGemini = async (emitToken: (text: string) => void): Promise<ModelResult> => {
        sendEvent('status', { stage: 'model', message: 'Contacting Gemini…' });
        const apiKey = Deno.env.get('GEMINI_API_KEY');
        if (!apiKey) {
          throw new Error('Missing GEMINI_API_KEY');
        }

        const streamLogger = logger.child({ scope: 'gemini-stream' });
        const requestStart = performance.now();
        const requestStartIso = new Date().toISOString();
        streamLogger.info('Gemini request dispatched', { at: requestStartIso });
        const payload = {
          systemInstruction: {
            role: 'system',
            parts: [{ text: systemPrompt }],
          },
          contents: [
            {
              role: 'user',
              parts: [
                { text: userPrompt },
                {
                  inlineData: {
                    mimeType: 'image/jpeg',
                    data: base64Image,
                  },
                  mediaResolution: {
                    level: 'media_resolution_high',
                  },
                },
              ],
            },
          ],
          generationConfig: {
            temperature: 1,
            maxOutputTokens: 5000,
          },
        };

        const reader = await retryWithBackoff(async () => {
          const response = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:streamGenerateContent?alt=sse`,
            {
              method: 'POST',
              headers: {
                'content-type': 'application/json',
                'x-goog-api-key': apiKey,
              },
              body: JSON.stringify(payload),
            },
          );

          if (!response.ok) {
            const errorText = await response.text();
            streamLogger.error('Gemini HTTP error', {
              status: response.status,
              bodySnippet: errorText?.slice(0, 300),
            });
            const err = new Error(`Gemini request failed with status ${response.status}`);
            (err as any).status = response.status;
            throw err;
          }

          if (!response.body) {
            throw new Error('Gemini response body missing');
          }

          return response.body.getReader();
        }, streamLogger, STREAM_RETRY_LIMIT, 'Gemini');

        const now = performance.now();
        const streamReadyLatencySeconds = (now - requestStart) / 1000;
        const totalSinceInitialRequestSeconds = (now - t0) / 1000;
        streamLogger.info('Gemini stream ready', {
          latencySeconds: Number(streamReadyLatencySeconds.toFixed(2)),
          totalSinceInitialRequestSeconds: Number(totalSinceInitialRequestSeconds.toFixed(2)),
          t0Iso: new Date(Date.now() - (performance.now() - t0)).toISOString(),
        });

        sendEvent('status', { stage: 'stream', message: 'Streaming analysis…' });
        const decoder = new TextDecoder();

        let buffer = '';
        let rawResponse = '';
        let pendingTokenBatch = '';
        let chunkCounter = 0;
        let streamingCompleteLogged = false;
        let initialChunkSent = false;
        let modelUsed = GEMINI_MODEL;

        const logStreamingDone = () => {
          if (streamingCompleteLogged) return;
          streamingCompleteLogged = true;
          streamLogger.info('Streaming completed', {
            totalChars: rawResponse.length,
            chunkCount: chunkCounter,
          });
        };

        const logChunk = (label: string, chunk: string) => {
          chunkCounter += 1;
          streamLogger.debug('Streaming chunk emitted', {
            chunkIndex: chunkCounter,
            chunkLength: chunk.length,
            label,
          });
        };

        const flushPendingTokens = (label: string) => {
          const batch = pendingTokenBatch;
          if (batch.trim().length === 0) {
            pendingTokenBatch = '';
            return;
          }

          logChunk(label, batch);
          emitToken(batch);
          pendingTokenBatch = '';
          if (!initialChunkSent) {
            initialChunkSent = true;
          }
        };

        const processPayload = (payloadText: string) => {
          const normalized = payloadText.startsWith('data:')
            ? payloadText.replace(/^data:\s*/, '')
            : payloadText;
          const trimmed = normalized.trim();
          if (!trimmed) return;
          let parsed: any = null;
          try {
            parsed = JSON.parse(trimmed);
          } catch (parseError) {
            streamLogger.debug('Gemini chunk parse failed', {
              errorMessage: parseError instanceof Error ? parseError.message : String(parseError),
              snippet: trimmed.slice(0, 240),
            });
            return;
          }

          const parts = parsed?.candidates?.[0]?.content?.parts ?? [];
          if (parsed?.candidates?.[0]?.model) {
            modelUsed = parsed.candidates[0].model;
          }

          for (const part of parts) {
            if (typeof part.text !== 'string') continue;
            const delta = part.text;
            rawResponse += delta;
            pendingTokenBatch += delta;

            const hasSentenceBreak = /[.!?]\s$/.test(pendingTokenBatch);
            const trimmedPending = pendingTokenBatch.trim();
            const shouldFlushInitial = !initialChunkSent && trimmedPending.length > 0;
            if (
              pendingTokenBatch.length >= TOKEN_BATCH_TARGET ||
              hasSentenceBreak ||
              shouldFlushInitial
            ) {
              const label = shouldFlushInitial ? 'initial' : 'batch';
              flushPendingTokens(label);
            }
          }
        };

        streamLogger.info('Streaming begun');

        let eventLines: string[] = [];

        const flushEvent = () => {
          if (eventLines.length === 0) return;
          const payloadText = eventLines.join('\n').trim();
          eventLines = [];
          if (!payloadText || payloadText === '[DONE]') return;
          processPayload(payloadText);
        };

        while (true) {
          const { done, value } = await reader.read();
          if (done) {
            flushEvent();
            flushPendingTokens('final');
            break;
          }

          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split('\n');
          buffer = lines.pop() ?? '';

          for (const line of lines) {
            const trimmedLine = line.trimEnd();
            if (trimmedLine.startsWith('data:')) {
              const dataPart = trimmedLine.replace(/^data:\s*/, '');
              eventLines.push(dataPart);
              continue;
            }

            if (trimmedLine === '') {
              flushEvent();
              continue;
            }

            // Fallback: if the stream is not SSE-prefixed, accumulate as-is.
            eventLines.push(trimmedLine);
          }
        }

        const leftover = buffer.trim();
        if (leftover) {
          eventLines.push(leftover);
          flushEvent();
          flushPendingTokens('leftover');
        }

        logStreamingDone();

        if (!rawResponse.trim()) {
          throw new Error(`${GEMINI_MODEL} returned empty response`);
        }

        return { rawResponse, modelUsed };
      };

      const runOpenAI = async (emitToken: (text: string) => void): Promise<ModelResult> => {
        sendEvent('status', { stage: 'model', message: 'Contacting ChatGPT…' });

        const openai = new OpenAI({ apiKey: Deno.env.get('OPENAI_API_KEY') });
        if (!openai.apiKey) {
          throw new Error('Missing OPENAI_API_KEY');
        }

        let rawResponse = '';
        let modelUsed = OPENAI_MODEL;

        const requestStart = performance.now();
        const requestStartIso = new Date().toISOString();
        const streamLogger = logger.child({ scope: 'openai-stream' });
        streamLogger.info('ChatGPT request dispatched', { at: requestStartIso });

        const openaiStream = await retryWithBackoff(async () => {
          const responseStream = await openai.responses.stream({
            model: OPENAI_MODEL,
            reasoning: { effort: "low" },
            instructions: systemPrompt,
            max_output_tokens: 5000,
            temperature: 1,
            input: [
              {
                role: 'user',
                content: [
                  { type: 'input_text', text: userPrompt },
                  {
                    type: 'input_image',
                    image_url: `data:image/jpeg;base64,${base64Image}`,
                  },
                ],
              },
            ],
          });
          return responseStream;
        }, streamLogger, STREAM_RETRY_LIMIT, 'OpenAI');

        const now = performance.now();
        const streamReadyLatencySeconds = (now - requestStart) / 1000;
        const totalSinceInitialRequestSeconds = (now - t0) / 1000;
        streamLogger.info('ChatGPT stream ready', {
          latencySeconds: Number(streamReadyLatencySeconds.toFixed(2)),
          totalSinceInitialRequestSeconds: Number(totalSinceInitialRequestSeconds.toFixed(2)),
          t0Iso: new Date(Date.now() - (performance.now() - t0)).toISOString(),
        });

        sendEvent('status', { stage: 'stream', message: 'Streaming analysis…' });

        try {
          const startTime = performance.now();
          let pendingTokenBatch = '';
          let chunkCounter = 0;
          let streamingCompleteLogged = false;
          let initialChunkSent = false;

          const logStreamingDone = () => {
            if (streamingCompleteLogged) return;
            streamingCompleteLogged = true;
            streamLogger.info('Streaming completed', {
              totalChars: rawResponse.length,
              chunkCount: chunkCounter,
            });
          };

          const logChunk = (label: string, chunk: string) => {
            chunkCounter += 1;
            streamLogger.debug('Streaming chunk emitted', {
              chunkIndex: chunkCounter,
              chunkLength: chunk.length,
              label,
            });
          };

          const flushPendingTokens = (label: string) => {
            const batch = pendingTokenBatch;
            if (batch.trim().length === 0) {
              pendingTokenBatch = '';
              return;
            }

            logChunk(label, batch);
            emitToken(batch);
            pendingTokenBatch = '';
            if (!initialChunkSent) {
              initialChunkSent = true;
            }
          };

          streamLogger.info('Streaming begun');

          for await (const event of openaiStream) {
            if (event.type === 'response.output_text.delta') {
              const delta = event.delta;
              rawResponse += delta;
              pendingTokenBatch += delta;

              const hasSentenceBreak = /[.!?]\s$/.test(pendingTokenBatch);
              const trimmedPending = pendingTokenBatch.trim();
              const shouldFlushInitial = !initialChunkSent && trimmedPending.length > 0;
              if (
                pendingTokenBatch.length >= TOKEN_BATCH_TARGET ||
                hasSentenceBreak ||
                shouldFlushInitial
              ) {
                const label = shouldFlushInitial ? 'initial' : 'batch';
                flushPendingTokens(label);
              }
            } else if (event.type === 'response.output_text.done') {
              flushPendingTokens('finalize');
              sendEvent('status', { stage: 'stream', message: 'Model output received.' });
            } else if (event.type === 'response.completed') {
              logStreamingDone();
            } else if (event.type === 'response.error') {
              streamLogger.error('OpenAI stream error event', {
                errorMessage: event.error?.message,
                errorCode: event.error?.code,
              });
              throw new Error(event.error?.message || 'OpenAI streaming error');
            }
          }

          flushPendingTokens('final');
          logStreamingDone();
        } catch (streamError) {
          streamLogger.error('OpenAI stream iteration failed', {
            errorMessage: streamError instanceof Error ? streamError.message : String(streamError),
          });
          throw streamError;
        }

        const finalResponse = await openaiStream.finalResponse();
        if (finalResponse?.model) {
          modelUsed = finalResponse.model;
        }
        // Streaming duration already logged inside try block; no additional timing needed.
        if (!rawResponse.trim()) {
          throw new Error(`${OPENAI_MODEL} returned empty response`);
        }

        return { rawResponse, modelUsed };
      };

      const runClaude = async (emitToken: (text: string) => void): Promise<ModelResult> => {
        sendEvent('status', { stage: 'model', message: 'Contacting Claude…' });

        const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
        if (!apiKey) {
          throw new Error('Missing ANTHROPIC_API_KEY');
        }

        const anthropic = new Anthropic({ apiKey });
        const streamLogger = logger.child({ scope: 'claude-stream' });
        const requestStart = performance.now();
        const requestStartIso = new Date().toISOString();
        streamLogger.info('Claude request dispatched', { at: requestStartIso });

        const claudeStream = await retryWithBackoff(async () => {
          return await anthropic.messages.stream({
            model: CLAUDE_MODEL,
            max_tokens: 5000,
            temperature: 1,
            system: systemPrompt,
            messages: [
              {
                role: 'user',
                content: [
                  { type: 'text', text: userPrompt },
                  {
                    type: 'image',
                    source: {
                      type: 'base64',
                      media_type: 'image/jpeg',
                      data: base64Image,
                    },
                  },
                ],
              },
            ],
          });
        }, streamLogger, STREAM_RETRY_LIMIT, 'Claude');

        const now = performance.now();
        const streamReadyLatencySeconds = (now - requestStart) / 1000;
        const totalSinceInitialRequestSeconds = (now - t0) / 1000;
        streamLogger.info('Claude stream ready', {
          latencySeconds: Number(streamReadyLatencySeconds.toFixed(2)),
          totalSinceInitialRequestSeconds: Number(totalSinceInitialRequestSeconds.toFixed(2)),
          t0Iso: new Date(Date.now() - (performance.now() - t0)).toISOString(),
        });

        sendEvent('status', { stage: 'stream', message: 'Streaming analysis…' });

        let rawResponse = '';
        let pendingTokenBatch = '';
        let chunkCounter = 0;
        let streamingCompleteLogged = false;
        let initialChunkSent = false;
        let modelUsed = CLAUDE_MODEL;

        const logStreamingDone = () => {
          if (streamingCompleteLogged) return;
          streamingCompleteLogged = true;
          streamLogger.info('Streaming completed', {
            totalChars: rawResponse.length,
            chunkCount: chunkCounter,
          });
        };

        const logChunk = (label: string, chunk: string) => {
          chunkCounter += 1;
          streamLogger.debug('Streaming chunk emitted', {
            chunkIndex: chunkCounter,
            chunkLength: chunk.length,
            label,
          });
        };

        const flushPendingTokens = (label: string) => {
          const batch = pendingTokenBatch;
          if (batch.trim().length === 0) {
            pendingTokenBatch = '';
            return;
          }

          logChunk(label, batch);
          emitToken(batch);
          pendingTokenBatch = '';
          if (!initialChunkSent) {
            initialChunkSent = true;
          }
        };

        streamLogger.info('Streaming begun');

        for await (const event of claudeStream) {
          if (event.type === 'content_block_delta' && event.delta?.type === 'text_delta') {
            const delta = event.delta.text ?? '';
            rawResponse += delta;
            pendingTokenBatch += delta;

            const hasSentenceBreak = /[.!?]\s$/.test(pendingTokenBatch);
            const trimmedPending = pendingTokenBatch.trim();
            const shouldFlushInitial = !initialChunkSent && trimmedPending.length > 0;
            if (
              pendingTokenBatch.length >= TOKEN_BATCH_TARGET ||
              hasSentenceBreak ||
              shouldFlushInitial
            ) {
              const label = shouldFlushInitial ? 'initial' : 'batch';
              flushPendingTokens(label);
            }
          } else if (event.type === 'message_delta') {
            if (event.delta?.stop_reason) {
              streamLogger.debug('Claude stop reason observed', { stopReason: event.delta.stop_reason });
            }
          } else if (event.type === 'error') {
            streamLogger.error('Claude stream error event', {
              errorMessage: (event as any).error?.message,
            });
            throw new Error((event as any).error?.message || 'Claude streaming error');
          }
        }

        flushPendingTokens('final');
        logStreamingDone();

        const finalMessage = await claudeStream.finalMessage();
        if (finalMessage?.model) {
          modelUsed = finalMessage.model;
        }

        if (!rawResponse.trim()) {
          throw new Error(`${CLAUDE_MODEL} returned empty response`);
        }

        return { rawResponse, modelUsed };
      };

      const providers = [
        { name: 'Gemini', runner: runGemini },
        { name: 'ChatGPT', runner: runOpenAI },
        { name: 'Claude', runner: runClaude },
      ];

      let modelResult: ModelResult | null = null;
      let lastError: any = null;

      for (const provider of providers) {
        const currentIndex = providers.findIndex((p) => p.name === provider.name);
        const nextProvider = currentIndex >= 0 && currentIndex + 1 < providers.length
          ? providers[currentIndex + 1].name
          : null;
        let emittedTokens = false;
        const emitToken = (text: string) => {
          emittedTokens = true;
          sendEvent('token', { text });
        };

        try {
          handlerLogger.info('Model attempt started', { provider: provider.name });
          modelResult = await provider.runner(emitToken);
          handlerLogger.info('Model attempt succeeded', { provider: provider.name });
          break;
        } catch (providerError: any) {
          lastError = providerError;
          handlerLogger.error(`${provider.name} provider failed`, {
            errorMessage: providerError?.message ?? String(providerError),
          });
          if (emittedTokens) {
            throw providerError;
          }
          handlerLogger.warn('Falling back to next provider', {
            failedProvider: provider.name,
            nextProvider: nextProvider ?? 'none',
          });
          sendEvent('status', { stage: 'model', message: `${provider.name} unavailable, trying next provider…` });
        }
      }

      if (!modelResult) {
        throw lastError ?? new Error('All model providers failed');
      }

      const { rawResponse, modelUsed } = modelResult;
      handlerLogger.info('Model used for response', { modelUsed });

      sendEvent('status', { stage: 'parse', message: 'Parsing AI response…' });

      let structuredMetadata: any = null;
      let shortDescription = '';
      let titleForStorage = '';
      let fullDescription = '';
      let analysisSection = '';

      const outputBody = rawResponse.trim();
      const metadataHeadingRegex = /###\s*metadata_json/i;
      const metadataMatch = metadataHeadingRegex.exec(outputBody);
      if (!metadataMatch) {
        throw new Error('Response missing metadata_json section');
      }

      const beforeMetadata = outputBody.slice(0, metadataMatch.index).trim();
      if (beforeMetadata.length > 0) {
        handlerLogger.warn('AI response contained preface before metadata_json heading', {
          prefaceLength: beforeMetadata.length,
        });
      }

      const afterHeadingRaw = outputBody.slice(metadataMatch.index + metadataMatch[0].length);
      const afterHeading = afterHeadingRaw.trimStart();

      let jsonPart = '';
      let narrativeBody = '';

      const codeBlockMatch = afterHeading.match(/^```(?:json)?\s*([\s\S]*?)```/i);
      if (codeBlockMatch) {
        jsonPart = codeBlockMatch[1].trim();
        narrativeBody = afterHeading.slice(codeBlockMatch[0].length).trim();
      } else {
        const braceStart = afterHeading.indexOf('{');
        if (braceStart === -1) {
          throw new Error('Metadata JSON missing opening brace');
        }
        let braceCount = 0;
        let endIndex = -1;
        for (let i = braceStart; i < afterHeading.length; i++) {
          const ch = afterHeading[i];
          if (ch === '{') {
            braceCount += 1;
          } else if (ch === '}') {
            braceCount -= 1;
            if (braceCount === 0) {
              endIndex = i;
              break;
            }
          }
        }
        if (endIndex === -1) {
          throw new Error('Metadata JSON missing closing brace');
        }
        jsonPart = afterHeading.slice(braceStart, endIndex + 1).trim();
        narrativeBody = afterHeading.slice(endIndex + 1).trim();
      }

      analysisSection = outputBody;
      fullDescription = narrativeBody;

      try {
        structuredMetadata = JSON.parse(jsonPart);
      } catch {
        const firstBrace = jsonPart.indexOf('{');
        const lastBrace = jsonPart.lastIndexOf('}');
        if (firstBrace === -1 || lastBrace === -1 || lastBrace <= firstBrace) {
          throw new Error('Failed to parse metadata JSON');
        }
        const candidate = jsonPart.slice(firstBrace, lastBrace + 1);
        structuredMetadata = JSON.parse(candidate);
      }

      if (!structuredMetadata || typeof structuredMetadata !== 'object') {
        throw new Error('Parsed metadata is not an object');
      }

      const metadataTitle = typeof structuredMetadata.title === 'string'
        ? structuredMetadata.title.trim()
        : '';
      const metadataShortDesc = typeof structuredMetadata.shortDescription === 'string'
        ? structuredMetadata.shortDescription.trim()
        : '';

      titleForStorage = metadataTitle;
      shortDescription = metadataShortDesc;

      if (!titleForStorage) throw new Error('Missing title in metadata');
      if (!shortDescription) throw new Error('Missing short description in metadata');

      sendEvent('metadata', { title: titleForStorage, shortDescription });
      handlerLogger.info('Metadata parsed', {
        titleLength: titleForStorage.length,
        shortDescriptionLength: shortDescription.length,
      });

      sendEvent('status', { stage: 'upload', message: 'Uploading image…' });
      const fileName = `${userId}/${Date.now()}.jpg`;

      const uploadResult = await supabaseAdmin.storage
        .from('discovery_images')
        .upload(fileName, uint8Array, {
          contentType: 'image/jpeg',
          upsert: false,
        });

      if (uploadResult.error) {
        throw new Error(`Image upload failed: ${uploadResult.error.message}`);
      }

      sendEvent('status', { stage: 'database', message: 'Saving discovery…' });

      let dbLocationData = null;
      if (locationCoords) {
        dbLocationData = {
          type: "Point",
          coordinates: [locationCoords.longitude, locationCoords.latitude],
        };
      }

      let closestPlaceName: string | null = null;
      if (placesData && placesData.length > 0) {
        closestPlaceName = placesData[0].displayName?.text || null;
      }

      const discoveryData = {
        user_id: userId,
        image_url: uploadResult.data.path,
        title: titleForStorage,
        description: fullDescription.trim(),
        short_description: shortDescription,
        analysis: analysisSection,
        model: modelUsed,
        location: dbLocationData,
        country: (locationInfo as any)?.country || null,
        locality: (locationInfo as any)?.city || null,
        street_name: (locationInfo as any)?.streetName || null,
        closest_place: closestPlaceName,
        system_prompt_version: systemPromptMetadata.version,
        user_prompt_version: userPromptMetadata.version,
      };

      const { data: discovery, error: discoveryError } = await supabaseAdmin
        .from('discoveries')
        .insert(discoveryData)
        .select('id')
        .single();

      if (discoveryError) {
        throw new Error(`Database insert failed: ${discoveryError.message}`);
      }

      discoveryId = discovery.id;

      if (pushToken) {
        sendEvent('status', { stage: 'notify', message: 'Sending notification…' });
        const pushLogger = logger.child({ scope: 'push' });
        await sendPushNotification(
          pushToken,
          "Discovery Complete! 🎉",
          `Your discovery "${titleForStorage}" is ready to view.`,
          String(discoveryId),
          pushLogger,
          bundleId
        );
      }

      sendEvent('complete', {
        discoveryId,
        systemPromptVersion: systemPromptMetadata.version,
        userPromptVersion: userPromptMetadata.version,
        creditBalance,
      });
      handlerLogger.info('Completion event sent', {
        discoveryId,
        systemPromptVersion: systemPromptMetadata.version,
        userPromptVersion: userPromptMetadata.version,
        creditBalance,
      });
      close();
    } catch (error: any) {
      handlerLogger.error('Fatal error while handling ask-ai-v7 request', {
        errorMessage: error?.message || String(error),
        statusHint: error?.status,
      });
      if (error?.stack) {
        handlerLogger.debug('Fatal error stack trace', { stack: error.stack });
      }

      const status = error?.status || (
        error?.message?.includes('authentication failed') ? 401 :
          error?.message?.includes('Insufficient credits') ? 402 :
            error?.message?.includes('Missing') ? 400 :
              error?.message?.includes('content_policy_violation') ? 451 : 500
      );

      sendEvent('error', {
        message: error?.message || 'Internal Server Error',
        status,
        discoveryId,
      });
      handlerLogger.warn('Emitted error event to client', {
        status,
        message: error?.message || 'Internal Server Error',
        discoveryId,
        creditsConsumed,
      });

      if (creditsConsumed && userId && !error?.message?.includes('content_policy_violation')) {
        try {
          handlerLogger.info('Attempting credit refund after failure', {
            userIdMasked: userId ? maskId(userId) : undefined,
            creditsToRefund: CREDITS_PER_DISCOVERY,
          });
          const { error: refundError } = await supabaseAdmin.rpc('refund_credit', {
            p_user_id: userId,
            p_credits_to_refund: CREDITS_PER_DISCOVERY,
          });
          if (refundError) {
            handlerLogger.error('Credit refund failed', {
              userIdMasked: userId ? maskId(userId) : undefined,
              errorMessage: refundError.message,
            });
          }
        } catch (refundRpcError: any) {
          handlerLogger.error('Credit refund RPC threw exception', {
            userIdMasked: userId ? maskId(userId) : undefined,
            errorMessage: refundRpcError?.message ?? String(refundRpcError),
          });
        }
      }

      close();
    }
  })();

  return response;
});
