# Web Sharing Pages Plan (2025-10-30)

This document captures the plan to implement public, shareable “Discovery” pages on the web that mirror the iOS app’s Discovery detail design and behavior.

## Summary

- Add a polished, brand-aligned web view for shared discoveries at `https://whats-that.app/<uuid>`.
- Use a Supabase Edge Function to fetch discovery data by share token and return a signed image URL for private storage objects.
- Mirror iOS brand tokens (colors, spacing, radii) so the page looks and feels like an extension of the app.
- Keep static landing/auth pages intact; progressively enhance for share routes.

## Current State Snapshot

- Web repo: `../whats-that-web`
  - `index.html`: Static marketing page using a blue palette and `logo.png` (missing).
  - `recovery-click.html` and `auth/reset/index.html`: Password reset deep-link helpers.
  - `.well-known/apple-app-site-association`: Associated domains configured for `/auth/reset*`, `/d/*`, `/p/*`.
- iOS app share URL shape: `https://whats-that.app/<uuid>` built in
  `native/WhatsThatIOSPackage/Sources/WhatsThatPresentation/Features/DiscoveriesFeed/DetailOverlay/Components/DiscoveryDetailShareHelpers.swift:44`.
- Brand tokens (source of truth):
  `native/WhatsThatIOSPackage/Sources/WhatsThatShared/Branding/BrandTheme.swift`.
  - Light: primary `#5BB98C` (pressed `#30A46C`), text `#1F2933`/`#4B5563`, border `#E8E8E8`, bg `#FFFFFF`.
  - Dark: bg `#080A15`, border `#2E2E2E`, text `#FFFFFF`/`~0.85`, primary `#236E4A` / pressed `#1B543A`.
  - Spacing: 8/16/24/32. Radii: 12/16.
- Brand asset: `native/WhatsThatIOS/Assets.xcassets/BrandLogo.imageset/logov2.png`.
- Supabase DB tables (public): `discoveries` (RLS enabled), `credit_transactions`, `user_credits`, `push_tokens`, `nearby_places_rate_limits`.
  - `discoveries` includes: `id, user_id, image_url, description, title, short_description, created_at, location (geometry), country, locality, street_name, closest_place, share_token (uuid unique)`.
  - RLS: owners-only read/write; no public reads by default.
  - Functions present: `get_discoveries_with_location(limit, last_id)` (owner-scoped), credit helpers.

## Gaps

1. No route/page for `/<share_token>` that renders a discovery.
2. Landing page not brand-aligned (palette + missing logo).
3. Public image access: `image_url` may be a storage path requiring a signed URL.
4. No public data endpoint for shared discoveries.

## Architecture

- Web delivery: static site + small client router.
  - Root (`/`): existing landing page (brand-aligned).
  - `/<uuid>`: discovery renderer (client-side), or server-rendered HTML via Edge Function for OG in a later phase.
- Data access: Supabase Edge Function `shared-discovery` (no JWT) returns sanitized JSON for a share token and a short‑lived signed image URL.
  - Uses service role server-side; no secrets in the browser.
  - Validates UUID, returns `404` on invalid/unknown token.
- Branding: CSS variables to match iOS `BrandTheme` (light/dark with `prefers-color-scheme`).

## UX for Discovery Page

- Hero image with 16px radius, subtle shadow on light.
- Title + highlight (short description fallback to `description`).
- Optional metadata row (captured time, location line: closestPlace/locality/country when present).
- Actions: “Open in app” deep link; “View on map” (Apple Maps `http://maps.apple.com/?ll=lat,lon&q=label`).
- Error/empty: “This discovery is unavailable” with secondary link back to landing.
- Dark mode support; responsive layout.

## Security & Policies

- Keep RLS as-is (owners only). Do not grant `SELECT` to `anon`.
- Expose read-only public endpoint via Edge Function.
- Ensure unique index on `share_token` (already present) for fast lookup.
- CORS: allow `https://whats-that.app` on the Edge Function response.

## Deliverables

- Supabase Edge Function: `shared-discovery` (public GET, returns JSON with signed image URL).
- Web repo:
  - `assets/brand-logo.png` (copy of iOS BrandLogo).
  - `styles/brand.css` (tokens + components).
  - `js/app.js` (client router, fetch to Edge Function, renderer).
  - Landing page restyled to use brand tokens and correct logo.

## Phased Plan

1. Edge Function for shared discovery (data + signed image).
2. Web UI + routing and brand polish; implement discovery renderer.
3. Optional: SSR/OG HTML via another Edge Function for rich previews.
4. Hardening: analytics, rate limiting, a11y pass, error states.

## Implementation Notes

- Edge Function behavior:
  - Input: `GET /shared-discovery?token=<uuid>` (or `/shared-discovery/<uuid>`).
  - Output: `{ title, short_description, description, image_url, created_at, country, locality, street_name, closest_place, location_text? }`.
  - `image_url` is a direct URL: if original `image_url` is absolute, return as-is; if storage path, return a short‑lived signed URL.
  - Use `createSignedUrl` on `discovery_images` bucket.
- Web rendering:
  - On load, if URL path matches UUID v4, mount the discovery view and fetch JSON; else render landing.
  - Progressive enhancement—bots will see landing until SSR/OG lands.

## Open Questions / Next

- If we want deep links handled by `/d/<token>` for Universal Links, update AASA and router later.
- If image bucket should remain private long term, keep signing via Edge Function. If public, store a `public_image_url` on share to avoid signing.

