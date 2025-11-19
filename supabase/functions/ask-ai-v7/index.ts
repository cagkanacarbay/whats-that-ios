// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, SupabaseClient } from 'npm:@supabase/supabase-js@2';
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
// const OPENAI_MODEL = "gpt-4o-mini"; // Temporary test model for streaming work
const OPENAI_MODEL = "gpt-5-mini"; 
const STREAM_RETRY_LIMIT = 3;

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
  logger: Logger
): Promise<boolean> {
  const bundleId = Deno.env.get('APNS_BUNDLE_ID');
  const environment = (Deno.env.get('APNS_ENVIRONMENT') || 'sandbox').toLowerCase();

  if (!bundleId) {
    logger.error('APNs bundle ID not configured');
    return false;
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
  logger: Logger
): Promise<boolean> {
  if (!pushToken) return false;

  return sendApnsPushNotification(pushToken, title, body, discoveryId, logger);
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
}

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

      const { base64Image, location, pushToken, customContext } = requestBody;
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

      sendEvent('status', { stage: 'credits', message: 'Consuming credits…' });

      const { error: consumeError } = await supabaseAdmin.rpc('consume_credit_for_discovery', {
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

      if (customContext && customContext.trim()) {
        customContextDisplay = customContext.trim();
        try {
          const contexts = JSON.parse(customContext);
          if (contexts.recentFullDiscoveries) {
            recentFullDiscoveries = contexts.recentFullDiscoveries;
          }
          if (contexts.aggregatedHistory) {
            aggregatedHistory = contexts.aggregatedHistory;
          }
          customContextDisplay = JSON.stringify(contexts, null, 2);
        } catch {
          aggregatedHistory = customContext.trim();
        }
      }

      promptVariables.recentFullDiscoveries = recentFullDiscoveries;
      promptVariables.userDiscoveryContext = aggregatedHistory;
      promptVariables.customContext = customContextDisplay;

      sendEvent('status', { stage: 'prompt', message: 'Assembling prompt…' });
      const promptLogger = handlerLogger.child({ scope: 'prompt' });
      const { system: systemPrompt, user: userPrompt } = await assemblePrompt('singular', promptVariables, promptLogger);

      sendEvent('status', { stage: 'model', message: 'Contacting OpenAI…' });

      const openai = new OpenAI({ apiKey: Deno.env.get('OPENAI_API_KEY') });
      if (!openai.apiKey) {
        throw new Error('Missing OPENAI_API_KEY');
      }

      let rawResponse = '';
      let modelUsed = OPENAI_MODEL;

      const startTime = performance.now();

      const streamLogger = logger.child({ scope: 'openai-stream' });
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

      sendEvent('status', { stage: 'stream', message: 'Streaming analysis…' });

      try {
        const TOKEN_BATCH_TARGET = 160;
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
          sendEvent('token', { text: batch });
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
      const durationSeconds = (performance.now() - startTime) / 1000;
      streamLogger.info('OpenAI streaming latency recorded', {
        model: OPENAI_MODEL,
        durationSeconds: Number(durationSeconds.toFixed(2)),
      });

      if (!rawResponse.trim()) {
        throw new Error(`${OPENAI_MODEL} returned empty response`);
      }

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
          pushLogger
        );
      }

      sendEvent('complete', {
        discoveryId,
        systemPromptVersion: systemPromptMetadata.version,
        userPromptVersion: userPromptMetadata.version,
      });
      handlerLogger.info('Completion event sent', {
        discoveryId,
        systemPromptVersion: systemPromptMetadata.version,
        userPromptVersion: userPromptMetadata.version,
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
