// Shared CORS utilities aligned with project conventions
// Origin policy is controlled by DENO_ENV only:
// - production: allow only https://whats-that.app
// - development: also allow http://localhost:5173 for local testing

const denoEnv = (Deno.env.get('DENO_ENV') || 'production').toLowerCase();
const DEFAULT_ALLOWED_ORIGINS = denoEnv === 'development'
  ? ['https://whats-that.app', 'https://dev.whats-that.app', 'http://localhost:5173']
  : ['https://whats-that.app'];

const normalizedAllowedOrigins = new Set(DEFAULT_ALLOWED_ORIGINS.map(o => o.toLowerCase()));

export const isOriginAllowed = (origin?: string | null): boolean => {
  const norm = origin?.toLowerCase();
  return !!(norm && normalizedAllowedOrigins.has(norm));
};

export const buildCorsHeaders = (origin?: string | null) => {
  const allowOrigin = isOriginAllowed(origin) ? (origin as string) : DEFAULT_ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Expose-Headers': 'X-Correlation-Id',
    'Vary': 'Origin',
  } as HeadersInit;
};

export const corsHeaders = buildCorsHeaders();

