# Environments: Development vs Production (Web Share + Supabase)

This guide defines how our Development and Production environments differ for the public "shared discovery" website flow and the Supabase Edge Function that powers it.

## Overview

- The website is a static SPA (`../whats-that-web`) that renders a discovery page at `/<share_token>` by calling a Supabase Edge Function.
- The Edge Function (`shared-discovery`) reads one discovery by its public `share_token` and returns sanitized fields plus a usable `image_url` (signs private Storage paths with a short‑lived URL).
- Public share pages must work for anonymous users; we do not require JWT for viewing a shared discovery.

## Differences at a Glance

- Auth: No JWT required for public share pages (both Dev and Prod).
- Service Role: Used server-side inside the Edge Function only (never shipped to the browser).
- CORS/Origin policy (controlled by `DENO_ENV` only):
  - `DENO_ENV=production`: Only `https://whats-that.app` is allowed.
  - `DENO_ENV=development`: Also allow `http://localhost:5173` for local testing.
- Function JWT verification: Disabled (`--no-verify-jwt`) for this public endpoint.
- Website hosting:
  - Production: CDN/static hosting with SPA fallback (rewrite all unknown paths to `/index.html`).
  - Development: Local static server with SPA fallback for `/<share_token>`.

## Supabase Edge Function: `shared-discovery`

- Responsibilities:
  - Validate a `share_token` (UUID v4) from `?token=` or `/<token>`.
  - Fetch a single row from `public.discoveries` by `share_token` using the service role.
  - Sign a private Storage path from the `discovery_images` bucket when needed and return a usable `image_url`.
  - Return only public fields: `title, short_description, description, image_url, created_at, country, locality, street_name, closest_place`.

- Environment variables:
  - `SUPABASE_URL` — your project URL.
  - `SUPABASE_SERVICE_ROLE_KEY` — service role, stored only in Function secrets.
  - `DENO_ENV` — `production` (default) or `development`.

- Origin policy logic (enforced per request):
  - `DENO_ENV=production` → allow only `https://whats-that.app`.
  - `DENO_ENV=development` → allow `https://whats-that.app` and `http://localhost:5173`.

- JWT verification:
  - Disabled for this function via `--no-verify-jwt`, because public share pages are anonymous.

- RLS posture:
  - Keep RLS strict on `public.discoveries` (owners‑only). The function uses the service role to fetch a single row by token and returns sanitized data.

### Deploy: Production

```bash
# Required secrets (server-side only)
supabase functions secrets set \
  SUPABASE_URL=YOUR_PROJECT_URL \
  SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE

# Allow only the production domain
supabase functions secrets set \
  ALLOWED_ORIGINS="https://whats-that.app" \
  ENVIRONMENT=production

# Deploy with JWT verification disabled (public endpoint)
supabase functions deploy shared-discovery --no-verify-jwt
```

### Deploy: Development (Local Testing)

```bash
# Same required secrets
supabase functions secrets set \
  SUPABASE_URL=YOUR_PROJECT_URL \
  SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE

# Temporarily allow localhost for local SPA testing
supabase functions secrets set \
  ALLOWED_ORIGINS="http://localhost:5173,https://whats-that.app" \
  ENVIRONMENT=development

supabase functions deploy shared-discovery --no-verify-jwt
```

## Global Edge Runtime Patterns (Deno)

All edge functions in this project follow the same Deno runtime conventions:

- `DENO_ENV` controls behavior
  - `production` (default): production CORS allowlist, sanitized/obfuscated logs, default log level `info`.
  - `development`: includes localhost in CORS, verbose logs, default log level `debug`.
- `LOG_LEVEL` (optional) overrides the default
  - Valid: `debug`, `info`, `warn`, `error` (case-insensitive; `warning` maps to `warn`).
  - Example:
    - `supabase functions secrets set LOG_LEVEL=debug` (dev)
    - `supabase functions secrets set LOG_LEVEL=info` (prod)
- Correlation IDs
  - Each request is assigned a correlation ID and emitted via `X-Correlation-Id` and logs.
- Log sanitization (production)
  - Sensitive keys (token/secret/password/receipt/base64/body/payload/image/etc.) are redacted.
  - IDs and coordinates are masked/rounded.

Recommended secrets per environment:

```bash
# Production
supabase functions secrets set DENO_ENV=production LOG_LEVEL=info

# Development
supabase functions secrets set DENO_ENV=development LOG_LEVEL=debug
```

## Website (`../whats-that-web`)

- The SPA calls the edge function at:
  - `https://<project-ref>.functions.supabase.co/shared-discovery?token=<uuid>`
- Files:
  - `index.html` — landing page + mount point for discovery view.
  - `js/app.js` — client-side router + fetch to the edge function.
  - `styles/brand.css` — brand tokens mirroring the iOS app.

### Run Locally (Dev)

```bash
# From the repo root
npx serve -s ../whats-that-web -l 5173
# Visit
http://localhost:5173/                # landing page
http://localhost:5173/<share_token>   # discovery page
```

- The local origin `http://localhost:5173` must be in the function allowlist (see Dev secrets above).

### Deploy (Prod)

- Host the contents of `../whats-that-web` behind a CDN/static host with SPA fallback:
  - Rewrite all unknown paths (e.g., `/<share_token>`) to `/index.html` so the client router can render the discovery page.
- Ensure the function allowlist only includes `https://whats-that.app`.

## Security Posture

- Public by design: Any holder of a valid share URL can view.
- No JWT for viewers; do not require auth for public share pages.
- The service role stays server-side in the function; never ship it to the browser.
- CORS + Origin allowlist restricts which sites can call the function directly.
- Optional hardening (recommended):
  - Add a website-side proxy (e.g., `https://whats-that.app/api/shared-discovery`) that injects a private header; require that header in the edge function to strongly bind calls to your site.
  - Rate limiting per IP.
  - SSR/OG rendering for richer social previews.

## Troubleshooting

- `403 forbidden_origin` from function:
  - Check `ALLOWED_ORIGINS` and `ENVIRONMENT` secrets; ensure your origin matches exactly and that the `Origin` header is present.
- `404 not_found` from function:
  - Invalid or unknown `share_token`.
- Image missing:
  - Confirm `image_url` is either public or a valid Storage path to be signed; check the Storage bucket name (`discovery_images`).
- Local SPA 404 on deep link:
  - Use the Node `serve -s` command or configure your host to rewrite to `/index.html`.

---

Keep production tight: no localhost in `ALLOWED_ORIGINS`, and never expose the service role or Supabase keys in the website.
