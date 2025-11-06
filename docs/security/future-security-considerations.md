# Future Security Considerations

This document captures future security improvements we may adopt. Items here are intentionally deferred; they do not
block the current release unless explicitly promoted into the audit’s Pre‑Production Checklist.

## Future Considerations

### Website Backend Gating for Public Share Endpoint (shared‑discovery)

- Context

  - Our shared‑discovery endpoint intentionally serves public content by `share_token` and must remain always online.
  - We do not plan to add IP throttling or token expiry; tokens are long‑lived until the user removes the discovery.
  - Current protection relies on link‑secret semantics (unguessable token) and a server‑side origin allowlist used
    primarily to deter cross‑origin browser calls.
- Why consider a tiny website backend later

  - Origin headers are spoofable outside a browser; we cannot reliably distinguish our website from other clients.
  - A minimal website backend can hold a private JWT and call the Edge Function on behalf of the browser; the Edge
    Function can then verify that the caller is our “website bot user” and quickly reject all other requests without
    hitting the database.
  - Benefits:
    - Early, cheap reject path (fast 401) for non‑website callers.
    - No client‑side secrets; nothing reusable leaks into the browser bundle.
    - Preserves “always‑on” links; no token rotation or expiry is required.
- Sketch of the approach (deferred)

  1) Create a dedicated “website bot user” in Supabase Auth. Store its credentials server‑side only.
  2) Set `[functions.shared-discovery].verify_jwt = true` in `supabase/config.toml`.
  3) In the Edge Function, reject unless `auth.getUser(bearer).user.id == WEBSITE_BOT_USER_ID` (before DB access).
  4) The website backend exposes `/api/shared-discovery?token=...` that forwards to the Edge Function with the bot JWT.
  5) Browser fetches the website’s API, never the Edge Function directly.
- Threat model and tradeoffs

  - Stops non‑website callers from fetching content unless they compromise the bot credentials or the backend.
  - Does not change the public nature of the content: possession of a valid `share_token` still implies access.
  - Does not add throttling; sustained load could still occur but the early reject avoids DB work.
- Operational notes

  - Keep bot credentials and access tokens off the client; refresh tokens server‑side.
  - Add logging and simple alerts for unusual volumes.
  - Optionally cache responses at the website edge/CDN to offload repeat traffic.
- Status: Deferred. We accept the current setup for now (public link semantics). Revisit if:

  - We observe automated scraping/abuse, or
  - We need stronger assurance that only the website can access the endpoint.

---

Add more items here as new security considerations arise.
