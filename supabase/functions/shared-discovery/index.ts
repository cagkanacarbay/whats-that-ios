// Shared Discovery Edge Function
// Endpoint: /shared-discovery?token=<uuid> OR /shared-discovery/<uuid>
// Returns: { title, short_description, description, image_url, created_at, country, locality, street_name, closest_place, lat, lng }
// Notes:
// - Uses SUPABASE_SERVICE_ROLE_KEY on the server to read one discovery by share_token
// - Signs private storage image URLs (discovery_images) with a short-lived URL
// - Origin policy is driven by DENO_ENV via ../_shared/cors.ts

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { buildCorsHeaders, isOriginAllowed } from '../_shared/cors.ts'
import { createLogger } from '../_shared/logger.ts'


// --- location helpers: parse geometry -> lat/lng ---
function hexToBytes(hex: string): Uint8Array {
  const clean = hex.trim();
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substr(i * 2, 2), 16);
  return out;
}

function parseWkbPoint(wkbHex: string): { lat: number; lng: number } | null {
  try {
    const bytes = hexToBytes(wkbHex);
    if (bytes.length < 1 + 4 + 16) return null;
    const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const little = dv.getUint8(0) === 1;
    const typeWord = dv.getUint32(1, little);
    const hasSrid = (typeWord & 0x20000000) !== 0; // EWKB SRID flag
    let offset = 1 + 4;
    if (hasSrid) offset += 4; // skip SRID
    const x = dv.getFloat64(offset + 0, little); // lon
    const y = dv.getFloat64(offset + 8, little); // lat
    if (Number.isFinite(x) && Number.isFinite(y)) return { lat: y, lng: x };
  } catch {}
  return null;
}

function extractCoords(row: any): { lat: number | null; lng: number | null; source: string } {
  if (typeof row?.lat === 'number' && typeof row?.lng === 'number') return { lat: row.lat, lng: row.lng, source: 'columns' };
  if (row?.location && typeof row.location === 'object' && Array.isArray(row.location.coordinates)) {
    const [lng, lat] = row.location.coordinates;
    if (typeof lat === 'number' && typeof lng === 'number') return { lat, lng, source: 'geojson' };
  }
  if (typeof row?.location === 'string' && row.location.startsWith('{')) {
    try {
      const v = JSON.parse(row.location);
      if (v && v.type && String(v.type).toLowerCase() === 'point' && Array.isArray(v.coordinates)) {
        const [lng, lat] = v.coordinates;
        if (typeof lat === 'number' && typeof lng === 'number') return { lat, lng, source: 'geojson-str' };
      }
    } catch {}
  }
  if (typeof row?.location === 'string') {
    const pt = parseWkbPoint(row.location);
    if (pt) return { lat: pt.lat, lng: pt.lng, source: 'wkb' };
  }
  return { lat: null, lng: null, source: 'none' };
}
// --- end helpers ---

function getOrigin(req: Request): string | null {
  const origin = req.headers.get('Origin');
  if (origin) return origin;
  const referer = req.headers.get('Referer');
  if (!referer) return null;
  try { return new URL(referer).origin; } catch { return null; }
}

function isUUIDv4(token: string | null): token is string {
  if (!token) return false;
  const uuidV4 = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidV4.test(token);
}

function isAbsoluteUrl(value: string | null | undefined): value is string {
  if (!value) return false;
  try {
    const u = new URL(value);
    return !!u.protocol && !!u.host;
  } catch {
    return false;
  }
}

function extractDiscoveryImagesPath(value: string): string | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const marker = '/discovery_images/';
  if (isAbsoluteUrl(trimmed)) {
    const idx = trimmed.toLowerCase().indexOf(marker);
    if (idx >= 0) {
      let path = trimmed.substring(idx + marker.length);
      const q = path.indexOf('?');
      if (q >= 0) path = path.substring(0, q);
      return decodeURIComponent(path.replace(/^\/+|\/+$/g, ''));
    }
    return null;
  }
  return trimmed.replace(/^\/+|\/+$/g, '');
}

serve(async (req: Request) => {
  const correlationId = crypto.randomUUID();
  const origin = getOrigin(req);
  const corsHeaders = buildCorsHeaders(origin);
  const baseHeaders = { ...corsHeaders, 'X-Correlation-Id': correlationId } as HeadersInit;
  const logger = createLogger({ fn: 'shared-discovery', correlationId });

  if (req.method === 'OPTIONS') {
    logger.debug('CORS preflight');
    return new Response(null, { status: 204, headers: baseHeaders });
  }

  if (!isOriginAllowed(origin)) {
    logger.warn('Forbidden origin', { origin });
    return new Response(JSON.stringify({ error: 'forbidden_origin' }), {
      status: 403,
      headers: { ...baseHeaders, 'Content-Type': 'application/json' },
    });
  }

  try {
    const url = new URL(req.url);
    let token = url.searchParams.get('token');
    if (!token) {
      const parts = url.pathname.split('/').filter(Boolean);
      if (parts.length >= 2) token = parts[1];
    }

    if (!isUUIDv4(token)) {
      logger.warn('Invalid token');
      return new Response(JSON.stringify({ error: 'invalid_token', message: 'Token is missing or invalid' }), {
        status: 400,
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
      });
    }

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      logger.error('Server misconfigured: missing Supabase env');
      return new Response(JSON.stringify({ error: 'server_misconfigured' }), {
        status: 500,
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { 'X-Client-Info': 'shared-discovery-edge' } },
    });

    const { data, error } = await supabase
      .from('discoveries')
      .select(
        'id, title, short_description, description, image_url, created_at, country, locality, location'
      )
      .eq('share_token', token)
      .limit(1)
      .maybeSingle();

    if (error) {
      logger.error('DB error while fetching discovery', { error: error.message, tokenSuffix: token.slice(-6) });
      return new Response(JSON.stringify({ error: 'not_found' }), {
        status: 404,
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!data) {
      logger.warn('Discovery not found', { tokenSuffix: token.slice(-6) });
      return new Response(JSON.stringify({ error: 'not_found' }), {
        status: 404,
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
      });
    }

    const title = (data.title ?? 'Discovery').trim();
    const short_description = data.short_description ?? null;
    const description = data.description ?? null;

    let finalImageUrl: string | null = null;
    if (isAbsoluteUrl(data.image_url)) {
      finalImageUrl = data.image_url!;
    } else {
      const storagePath = data.image_url ? extractDiscoveryImagesPath(data.image_url) : null;
      if (storagePath) {
        const { data: signed, error: signErr } = await supabase.storage
          .from('discovery_images')
          .createSignedUrl(storagePath, 60 * 60); // 1 hour
        if (!signErr && signed?.signedUrl) {
          finalImageUrl = signed.signedUrl;
        } else if (signErr) {
          logger.warn('Failed to sign image URL', { storagePath, error: signErr.message });
        }
      }
    }

    const payload = {
      title,
      short_description,
      description,
      image_url: finalImageUrl ?? (isAbsoluteUrl(data.image_url) ? data.image_url : null),
      created_at: data.created_at,
      country: data.country ?? null,
      locality: data.locality ?? null,
      street_name: data.street_name ?? null,
      closest_place: data.closest_place ?? null,
      // Precise coordinates expected by the web client (js/share.js)
      // Extract from geo column or precomputed lat/lng with full precision
      ...((): { lat: number | null; lng: number | null } => {
        const c = extractCoords(data);
        return { lat: c.lat, lng: c.lng };
      })(),
    };

    logger.info('Shared discovery served', {
      tokenSuffix: token.slice(-6),
      hasImage: Boolean(payload.image_url),
      discoveryId: data.id,
    });
    return new Response(JSON.stringify(payload), {
      headers: { ...baseHeaders, 'Content-Type': 'application/json; charset=utf-8' },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    createLogger({ fn: 'shared-discovery' }).error('Unhandled error', { error: message });
    return new Response(JSON.stringify({ error: 'internal', message: 'Unexpected server error' }), {
      status: 500,
      headers: { ...buildCorsHeaders(getOrigin(req)), 'Content-Type': 'application/json' },
    });
  }
});
