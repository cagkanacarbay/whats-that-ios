import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { buildCorsHeaders } from '../_shared/cors.ts'
import { createClient } from 'npm:@supabase/supabase-js@2'
import { createLogger } from '../_shared/logger.ts'
import type { Logger } from '../_shared/logger.ts'

const GOOGLE_MAPS_API_KEY = Deno.env.get('GOOGLE_MAPS_API_KEY')
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
const RATE_LIMIT_WINDOW_SECONDS = 60
const RATE_LIMIT_MAX_REQUESTS = 5

// Utility: mask an identifier by showing beginning and end
function maskId(value: string): string {
  if (!value) return value as unknown as string
  if (value.length <= 8) {
    return `${value.slice(0, Math.max(1, value.length - 1))}…`
  }
  return `${value.slice(0, 4)}…${value.slice(-4)}`
}

// Sanitize Google error body to remove coordinates while preserving other info
function sanitizeErrorTextCoordinates(text: string): string {
  const scrub = (val: any): any => {
    if (Array.isArray(val)) return val.map(scrub);
    if (val && typeof val === 'object') {
      const out: Record<string, any> = {};
      for (const [k, v] of Object.entries(val)) {
        if (/^(lat|lng|latitude|longitude)$/i.test(k)) {
          out[k] = '[redacted]';
        } else {
          out[k] = scrub(v);
        }
      }
      return out;
    }
    return val;
  };
  try {
    const obj = JSON.parse(text);
    const sanitized = scrub(obj);
    return JSON.stringify(sanitized);
  } catch {
    let out = text;
    const patterns = [
      /(\"?latitude\"?\s*:\s*)(-?\d+(?:\.\d+)?)/gi,
      /(\"?longitude\"?\s*:\s*)(-?\d+(?:\.\d+)?)/gi,
      /(\"?lat\"?\s*:\s*)(-?\d+(?:\.\d+)?)/gi,
      /(\"?lng\"?\s*:\s*)(-?\d+(?:\.\d+)?)/gi,
    ];
    for (const re of patterns) {
      out = out.replace(re, '$1[redacted]');
    }
    return out;
  }
}

function createUserClient(authHeader: string) {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error('Missing Supabase configuration')
  }
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
}

// What we want to be returned from the places API
const googleFieldMask = [
  'places.formattedAddress',
  'places.adrFormatAddress',
  'places.displayName',
  'places.googleMapsUri',
  'places.id',
  'places.location',
  'places.name',
  'places.primaryType',
  'places.primaryTypeDisplayName',
  'places.subDestinations',
  'places.types'
]

interface RequestBody {
  latitude: number
  longitude: number
  radius?: number
}

serve(async (req) => {
  const correlationId = crypto.randomUUID()
  const logger: Logger = createLogger({ fn: 'nearby-places', correlationId })
  const corsResponseHeaders = buildCorsHeaders(req.headers.get('Origin'))

  // Base headers for all responses
  const baseHeaders = {
    ...corsResponseHeaders,
    'X-Correlation-Id': correlationId,
  }

  logger.info('Request received', { method: req.method })

  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    logger.debug('Handling CORS preflight request')
    return new Response('ok', { headers: baseHeaders })
  }

  try {
    const handlerLogger = logger.child({ scope: 'handler' })

    if (!GOOGLE_MAPS_API_KEY) {
      handlerLogger.error('GOOGLE_MAPS_API_KEY is not set')
      return new Response(
        JSON.stringify({ error: 'Server configuration error: Missing API key' }),
        {
          status: 500,
          headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      handlerLogger.warn('Missing Authorization header')
      return new Response(
        JSON.stringify({
          error: 'not_authenticated',
          message: 'User is not authenticated',
        }),
        {
          status: 401,
          headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    const token = authHeader.replace(/^Bearer\s+/i, '').trim()
    if (!token) {
      handlerLogger.warn('Authorization header present but token missing')
      return new Response(
        JSON.stringify({
          error: 'not_authenticated',
          message: 'User is not authenticated',
        }),
        {
          status: 401,
          headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    const supabaseUser = createUserClient(authHeader)
    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser()

    if (userError || !user) {
      handlerLogger.warn('User authentication failed', { errorMessage: userError?.message })
      return new Response(
        JSON.stringify({
          error: 'not_authenticated',
          message: 'User is not authenticated',
        }),
        {
          status: 401,
          headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    handlerLogger.info('User authenticated', { userIdMasked: maskId(user.id) })

    const { data: rateLimitAllowed, error: rateLimitError } = await supabaseUser.rpc(
      'enforce_nearby_places_rate_limit',
      {
        p_user_id: user.id,
        p_window_seconds: RATE_LIMIT_WINDOW_SECONDS,
        p_max_requests: RATE_LIMIT_MAX_REQUESTS,
      }
    )

    if (rateLimitError) {
      handlerLogger.error('Rate limit enforcement failed', { errorMessage: rateLimitError?.message ?? String(rateLimitError) })
      return new Response(
        JSON.stringify({
          error: 'rate_limit_error',
          message: 'Unable to validate request quota',
        }),
        {
          status: 500,
          headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    if (!rateLimitAllowed) {
      handlerLogger.warn('Rate limit exceeded', { userIdMasked: maskId(user.id) })
      return new Response(
        JSON.stringify({
          error: 'rate_limited',
          message: `Too many requests — up to ${RATE_LIMIT_MAX_REQUESTS} per minute allowed.`,
        }),
        {
          status: 429,
          headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Parse request body
    let requestData: RequestBody
    try {
      requestData = await req.json() as RequestBody
    } catch (e) {
      handlerLogger.warn('Error parsing request body', { errorMessage: e instanceof Error ? e.message : String(e) })
      return new Response(
        JSON.stringify({
          error: 'invalid_request',
          message: 'Could not parse request body',
        }),
        {
          status: 400,
          headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    const { latitude, longitude, radius = 250 } = requestData

    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      handlerLogger.warn('Missing required parameters: coordinates not provided')
      return new Response(
        JSON.stringify({
          error: 'missing_parameters',
          message: 'latitude and longitude are required'
        }),
        {
          status: 400,
          headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Create request body for Google Places API
    const requestBody = {
      includedPrimaryTypes: [
        'art_gallery', 'museum', 'performing_arts_theater', 'library', 'university',
        'amusement_center', 'amusement_park', 'aquarium', 'community_center',
        'convention_center', 'cultural_center', 'dog_park', 'event_venue',
        'hiking_area', 'historical_landmark', 'marina', 'movie_theater',
        'national_park', 'night_club', 'park', 'tourist_attraction', 'zoo',
        'city_hall', 'courthouse', 'embassy', 'local_government_office',
        'campground', 'church', 'hindu_temple', 'mosque', 'synagogue', 'market',
        'athletic_field', 'golf_course', 'ski_resort', 'sports_club',
        'sports_complex', 'stadium', 'airport', 'ferry_terminal'
      ],
      maxResultCount: 10,
      locationRestriction: {
        circle: {
          center: {
            latitude,
            longitude
          },
          radius: radius
        }
      }
    }

    const googleLogger = logger.child({ scope: 'google' })
    googleLogger.info('Calling Google Places API', {
      hasCoordinates: true,
      radius,
      fieldMaskCount: googleFieldMask.length,
    })

    // Call Google Places API
    const response = await fetch('https://places.googleapis.com/v1/places:searchNearby', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': GOOGLE_MAPS_API_KEY,
        'X-Goog-FieldMask': googleFieldMask.join(',')
      },
      body: JSON.stringify(requestBody)
    })

    if (!response.ok) {
      const errorText = await response.text()
      const sanitizedErrorText = sanitizeErrorTextCoordinates(errorText)
      googleLogger.error('Google Places API error', {
        status: response.status,
        errorText: sanitizedErrorText,
        responseBodyLength: errorText.length,
      })
      const errorPayload: Record<string, unknown> = {
        error: 'google_api_error',
        message: 'Error from Google Places API',
        status: response.status
      }
      return new Response(
        JSON.stringify(errorPayload),
        {
          status: 502,
          headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    const data = await response.json()
    const placeCount = Array.isArray((data as any)?.places) ? (data as any).places.length : 0
    googleLogger.info('Nearby places fetched', { placeCount })

    return new Response(
      JSON.stringify(data),
      {
        status: 200,
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown'
    const handlerLogger = logger.child({ scope: 'handler' })
    handlerLogger.error('Unexpected error in nearby-places function', { errorMessage: message })
    if (error instanceof Error && error.stack) {
      handlerLogger.debug('Stack trace', { stack: error.stack })
    }
    const errorPayload: Record<string, unknown> = {
      error: 'internal_error',
      message: 'An unexpected error occurred'
    }
    return new Response(
      JSON.stringify(errorPayload),
      {
        status: 500,
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
