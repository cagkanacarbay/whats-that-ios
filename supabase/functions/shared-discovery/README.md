# shared-discovery (Supabase Edge Function)

Public endpoint that returns sanitized discovery data by share token and a signed image URL when needed.

- Route: `/shared-discovery?token=<uuid>` (also supports `/shared-discovery/<uuid>`)
- Response: `{ title, short_description, description, image_url, created_at, country, locality, street_name, closest_place, lat, lng }`
- Security: Uses `SUPABASE_SERVICE_ROLE_KEY` on the server; keeps RLS strict (no anon SELECT on `discoveries`).
- CORS: `Access-Control-Allow-Origin: *` for GET/OPTIONS.

## Deploy

From the repo root (this folder does not ship with the iOS app binary):

```bash
# Ensure Supabase CLI is authenticated and project is selected
supabase functions deploy shared-discovery --no-verify-jwt

# Required secrets (server-only)
supabase functions secrets set \
  SUPABASE_URL=YOUR_PROJECT_URL \
  SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE

# Environment — matches other functions in the project
# Production (default): only https://whats-that.app is allowed
supabase functions secrets set DENO_ENV=production

# Development (local testing): also allow http://localhost:5173
supabase functions secrets set DENO_ENV=development

# Optional: control log verbosity
# - production default is 'info'; development default is 'debug'
supabase functions secrets set LOG_LEVEL=info   # or debug|warn|error
```

Production endpoint:

```
https://<project-ref>.functions.supabase.co/shared-discovery?token=<uuid>
```

## Notes

- If your `image_url` is already a public absolute URL, signing is skipped.
- If `image_url` is a storage path or signed URL to the `discovery_images` bucket, the function extracts the storage path and returns a fresh signed URL valid for 1 hour.
- The website fetches this endpoint client‑side and renders a brand‑aligned discovery page.
- Origin policy: controlled solely by `DENO_ENV`.
  - `production` → only `https://whats-that.app`
  - `development` → adds `http://localhost:5173` for local testing
 - Coordinates are returned as `lat` and `lng` as numbers with full precision consumed by the web client.
