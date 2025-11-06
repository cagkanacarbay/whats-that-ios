Supabase Security Audit and GDPR Readiness

Overview
- Scope: Database (RLS/policies/functions), Edge Functions, Auth, and configuration.
- Goal: Identify security gaps, prioritize fixes, and outline GDPR readiness steps before production launch.
- Date: [Generated]

Status Update (2025-11-06)
- Implemented: Pinned search_path and fully-qualified objects for key SECURITY DEFINER functions via migrations.
  - Migrations:
    - `20251106_pin_search_path_get_discoveries_with_location.sql`
    - `20251107_pin_search_path_remaining_functions.sql`
  - Functions updated: `get_discoveries_with_location`, `add_credits_after_validation`, `consume_credit_for_discovery`, `refund_credit`, `grant_initial_credits`, `get_discovery_analysis`.
- Verified in staging/remote:
  - get_discoveries_with_location – iOS feed loads successfully using authenticated session.
  - add_credits_after_validation – credits granted after sandbox purchase via validate-receipt.
  - consume_credit_for_discovery – credits decremented during Ask AI analysis.
- Pending explicit verification:
  - refund_credit – refund applied after failed Ask AI analysis (Edge path).
  - grant_initial_credits – starter credits flow (admin/service-role path).
  - get_discovery_analysis – owner/admin access path.
- Notes:
  - No app code changes required; function signatures and return shapes preserved.
  - Grants aligned to callers: `authenticated` (user-token RPCs) vs `service_role` (backend-only).

Decision Log
- Public sharing endpoint (shared‑discovery)
  - Decision: Keep current design (public link semantics, origin allowlist for browsers, no IP throttling, no token expiry). Links remain always available until the user deletes the discovery.
  - Rationale: Content is intentionally public; we prioritize always‑on links and operational simplicity. Origin checks deter casual cross‑origin browser calls; tokens are unguessable.
  - Deferred improvement: Consider a tiny website backend that holds a private JWT and calls the Edge Function (verify_jwt=true) so the function can quickly reject non‑website callers without DB access. See `docs/security/DocSecurity.md` for details.

Executive Summary
- Critical
  - Enable RLS on public.nearby_places_rate_limits or ensure it is truly private. Advisors flagged: “RLS Disabled in Public”.
  - Pin function search_path and fully-qualify objects for all SECURITY DEFINER functions (advisor: function_search_path_mutable). Prevents search_path hijacking.
  - Confirm Postgres upgrades (advisory: supabase-postgres-15.8.1.121 has available security patches). Schedule DB upgrade.
- High
  - Enable leaked password protection in Supabase Auth (HaveIBeenPwned check).
  - Validate Edge Functions’ verify_jwt settings: shared-discovery intentionally public; others should remain verify_jwt = true.
  - Add rate limiting and abuse protections to public endpoints (notably shared-discovery) to reduce token brute-force risks.
- Medium
  - Review RLS/policies for least-privilege on storage and core tables; tighten any policies that allow role public when authenticated suffices.
  - Review retention for sensitive payloads (e.g., raw Apple receipt data). Consider encrypt-at-rest and short retention.
  - Align config.toml with deployed function configs (verify_jwt), and restrict exposed schemas if GraphQL is unused.

Evidence (Automated Checks)
- Supabase Advisors (project):
  - 0011_function_search_path_mutable WARN: public functions with mutable search_path: add_credits_after_validation, consume_credit_for_discovery, enforce_nearby_places_rate_limit, get_discoveries_with_location, get_discovery_analysis, grant_initial_credits, refund_credit.
  - 0013_rls_disabled_in_public ERROR: Table public.nearby_places_rate_limits has RLS disabled.
  - Auth leaked password protection WARN: Feature disabled.
  - Postgres version WARN: Security patches available for current version; upgrade recommended.
- Tables with RLS (sample):
  - Enabled: public.discoveries, public.credit_transactions, public.user_credits, storage.objects, storage.buckets (and many auth tables)
  - Disabled: public.nearby_places_rate_limits (flagged)
- Policies (sample highlights):
  - discoveries: select limited to owner (auth.uid() = user_id); insert for authenticated; insert for user_id also present (role public + with_check). Consider simplifying to just authenticated.
  - push_tokens and user_credits scoped to owner.
  - storage.objects: discovery_images folder-scoped per user; voiceovers bucket has bot user policy bound to a specific UUID.
- Functions (selected definitions):
  - Several are SECURITY DEFINER and reference unqualified relations (e.g., FROM discoveries). With search_path pinned, bodies must fully-qualify.

Database Hardening
- RLS and Policy Remediation
  - public.nearby_places_rate_limits
    - Option A (recommended): Enable RLS and limit to owner; the service role will still bypass RLS as needed.
      - SQL:
        - alter table public.nearby_places_rate_limits enable row level security;
        - create policy "Near Places: owner can select" on public.nearby_places_rate_limits for select using (auth.uid() = user_id);
        - create policy "Near Places: owner can upsert" on public.nearby_places_rate_limits for insert with check (auth.uid() = user_id);
        - create policy "Near Places: owner can update" on public.nearby_places_rate_limits for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
    - Option B (alternative): Move to a private schema (e.g., private) or revoke all privileges to anon/authenticated and force access via SECURITY DEFINER RPC only.
  - discoveries
    - Prefer using authenticated role for inserts. If both authenticated and public insert policies exist, keep a single INSERT policy for authenticated with with_check (auth.uid() = user_id) to reduce complexity.
  - storage.objects
    - Validate bucket-level public access is not granted elsewhere. The current per-path policies for discovery_images and bot-user voiceovers look scoped; document the bot user risk (compromised bot account would access restricted paths).

- Pin search_path for Functions and Fully‑Qualify Objects
  - Risk: Mutable search_path + SECURITY DEFINER can route lookups to unexpected objects.
  - Approach 1 (preferred by Supabase’s advisor): set search_path = '' and fully‑qualify every object.
    - Example for get_discoveries_with_location (changes in body shown):
      - CREATE OR REPLACE FUNCTION public.get_discoveries_with_location(...)
        RETURNS TABLE(...) LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
        BEGIN
          RETURN QUERY
            SELECT d.id, ... , extensions.ST_AsText(d.location) as location, ...
            FROM public.discoveries d
            WHERE d.user_id = auth.uid() ...
        END; $$;
  - Approach 2 (simpler, still acceptable): SET search_path = 'public, pg_temp' for affected functions and qualify extension calls, then re‑check.
  - Ensure execute privileges:
    - Grant EXECUTE only to roles that need them (typically service_role and/or authenticated). Avoid anon for mutating RPCs.

- Global Data API Hardening
  - Ensure all tables in exposed schemas (config.toml → [api].schemas) have RLS enabled unless truly private and not granted to anon/authenticated.
  - If GraphQL is unused, remove "graphql_public" from [api].schemas to reduce attack surface. If used, it still honors RLS.
  - Consider a pre-request hook to enforce extra rules (Per Supabase docs: pgrst.db_pre_request) for global quotas or header checks.

Auth and Account Security
- Enable leaked password protection
  - Supabase Auth → Password security → Leaked password protection (HaveIBeenPwned) = Enabled.
- MFA
  - MFA TOTP is enabled in config; ensure UX surfaces it for high‑risk operations.
- Email confirmations
  - For production, prefer enable_confirmations = true for email sign‑ups.
- Session security
  - Keep jwt_expiry reasonable (3600s OK). Consider short refresh reuse interval already set (10s).

Edge Functions Review
- Inventory (deployed)
  - ask-ai-v7 (verify_jwt: true): Auth required. Uses service role for DB/storage, validates Authorization via supabaseAdmin.auth.getUser().
  - nearby-places (verify_jwt: true): Auth required. Uses RPC enforce_nearby_places_rate_limit; ensure table RLS enabled or table not accessible to anon/auth.
  - validate-receipt (verify_jwt: true): Auth required. Uses anon key + user token (runs as user). Stores raw receipt data in credit_transactions via RPC; add retention controls.
  - shared-discovery (verify_jwt: false): Public by design. CORS constrained by DENO_ENV; reads one discovery by share_token using service role; signs storage URL.

- Common protections in code (good)
  - CORS restricted to https://whats-that.app in production (and localhost:5173 in development) via shared CORS helper.
  - Logging masks sensitive fields and truncates text in production.
  - nearby-places: per-user RPC rate limiting, sanitized upstream error logs, and strict auth checks.

- Public endpoint risks (shared-discovery)
  - Token brute force: Share tokens are UUIDv4 and unguessable in practice, but public endpoint invites automated probing.
  - Recommendations
    - Add minimal per-IP and per-token rate limits (e.g., via a small logging table + SECURITY DEFINER RPC policy, or an API Gateway/WAF in front of functions).
    - Keep strict CORS and cache low. CORS is not a security boundary; do not rely on it solely.
    - Consider TTL or revocation for share_token (nullable field; use separate table if needed). Optionally generate short‑lived signed HMAC query parameter derived server‑side and validated per request.

Secrets and Configuration
- Secrets
  - No secrets committed; Edge Functions read SUPABASE_SERVICE_ROLE_KEY, OPENAI_API_KEY, APPLE_SHARED_SECRET from Supabase secrets. Ensure these are set per‑environment and rotated on incidents.
- config.toml hygiene
  - Add explicit function sections to match deployed verify_jwt settings, e.g.:
    - [functions.ask-ai-v7] verify_jwt = true
    - [functions.nearby-places] verify_jwt = true
    - [functions.validate-receipt] verify_jwt = true
    - [functions.shared-discovery] verify_jwt = false
  - API exposure: schemas = ["public"] unless GraphQL is required. Keep max_rows conservative (1000 is fine).

Data Protection and GDPR Readiness
- Data Classification (PII & sensitive)
  - Discoveries: image_url (may reference user content), analysis and descriptions (user‑generated), precise location (POINT). Treat as personal data.
  - Credit transactions: store_transaction_id, raw_receipt_data (sensitive). Consider encryption and retention limits.
  - Push tokens: personal data; require consent for notifications.

- Minimization & Retention
  - Store only data required for the feature.
  - Add retention windows: e.g., delete raw_receipt_data after X days; keep only minimal fields needed for dispute resolution.
  - Location precision: consider rounding or obfuscation in analytics/derivatives; enforce user consent for location usage.

- Encryption & Keys
  - At-rest: Supabase Postgres is encrypted; optionally use pgsodium for application‑level encryption of raw_receipt_data or other sensitive columns (key management via KMS/secret rotation process).
  - In-transit: TLS enforced by Supabase endpoints; never log tokens or full payloads in production (current logger masks many fields).

- Data Subject Requests (DSAR)
  - Provide a documented process to export and delete user data on request.
  - Add a database function to delete user-owned rows across tables (discoveries, credit_transactions, user_credits, push_tokens), ensuring cascading deletion of storage objects.
  - Example outline (adjust to schema):
    - create or replace function public.delete_user_data(p_user uuid) returns void language plpgsql security definer set search_path = '' as $$
      begin
        delete from public.push_tokens where user_id = p_user;
        delete from public.credit_transactions where user_id = p_user;
        delete from public.discoveries where user_id = p_user;
        delete from public.user_credits where user_id = p_user;
      end;$$;
    - Grant EXECUTE only to service_role; invoke from a privileged backend tool with strong operator authorization.

- Legal & Organizational
  - Ensure Supabase project is hosted in an EU region and DPA with Supabase is signed.
  - Publish a privacy policy and internal data inventory (what is stored, where, and for how long).
  - Maintain incident response, key rotation, and access control procedures.

Pre‑Production Checklist (Actionable)
- Database
  - [ ] Enable RLS on public.nearby_places_rate_limits and add owner‑scoped policies OR move to private schema and restrict grants.
  - [ ] Pin search_path on all SECURITY DEFINER functions and fully‑qualify object references.
  - [ ] Re‑audit policies: avoid role public where authenticated suffices; ensure no anon EXECUTE on mutating RPCs.
  - [ ] Schedule Postgres upgrade to latest patched minor version.
  - [ ] If GraphQL not needed, remove graphql_public from config.toml [api].schemas.

- Edge Functions
  - [ ] Ensure verify_jwt = true for ask-ai-v7, nearby-places, validate-receipt; verify_jwt = false only for shared-discovery.
  - [ ] Add basic DoS/brute-force protections for shared-discovery (rate limits, instrumentation, possible IP-based throttling).
  - [ ] Keep CORS strict (production origin allowlist) and verify DENO_ENV per environment.

- Auth
  - [ ] Enable leaked password protection.
  - [ ] Consider enabling email confirmations for sign-ups.
  - [ ] Verify MFA/TOTP UX is covered for high‑risk flows.

- Privacy & Compliance
  - [ ] Define and implement retention policies (e.g., purge raw_receipt_data after X days).
  - [ ] Implement DSAR export/deletion pathways and document operational runbooks.
  - [ ] Verify EU region and DPA signed with Supabase; document subprocessors.

Appendix: SQL Reference Snippets
- Enable RLS and add owner policies (nearby_places_rate_limits)
  - alter table public.nearby_places_rate_limits enable row level security;
  - create policy "Near Places: owner can select" on public.nearby_places_rate_limits for select using (auth.uid() = user_id);
  - create policy "Near Places: owner can insert" on public.nearby_places_rate_limits for insert with check (auth.uid() = user_id);
  - create policy "Near Places: owner can update" on public.nearby_places_rate_limits for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
- Pin search_path for SECURITY DEFINER functions (example)
  - CREATE OR REPLACE FUNCTION public.consume_credit_for_discovery(p_user_id uuid, p_credits_to_consume integer DEFAULT 1)
      RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
        DECLARE v_current_balance INTEGER; BEGIN
          UPDATE public.user_credits SET credit_balance = credit_balance - p_credits_to_consume, updated_at = now()
            WHERE user_id = p_user_id AND credit_balance >= p_credits_to_consume RETURNING credit_balance INTO v_current_balance;
          IF v_current_balance IS NULL THEN
            SELECT credit_balance INTO v_current_balance FROM public.user_credits WHERE user_id = p_user_id;
            IF v_current_balance IS NULL THEN RAISE EXCEPTION 'User not found: %', p_user_id; ELSE RAISE EXCEPTION 'insufficient_credits'; END IF;
          END IF;
          INSERT INTO public.credit_transactions (user_id, transaction_type, amount, description)
            VALUES (p_user_id, 'USAGE', -p_credits_to_consume, 'Credit used for discovery analysis');
        END; $$;
- Restrict RPC execution to service_role/authenticated as appropriate
  - revoke all on function public.enforce_nearby_places_rate_limit(uuid, integer, integer) from public;
  - grant execute on function public.enforce_nearby_places_rate_limit(uuid, integer, integer) to service_role;

References
- Securing your API (RLS best practices): https://supabase.com/docs/guides/api/securing-your-api
- Database Advisor Lint 0011 (search_path): https://supabase.com/docs/guides/database/database-advisors?queryGroups=lint&lint=0011_function_search_path_mutable
- Function configuration (verify_jwt): https://supabase.com/docs/guides/functions/function-configuration

Implementation Status Checklist
- Database
  - [x] Enable RLS on public.nearby_places_rate_limits and add owner policies (auth.uid() = user_id)
  - [x] Restrict RPC EXECUTE and pin search_path for enforce_nearby_places_rate_limit(uuid,int,int)
  - [x] Pin search_path for all remaining SECURITY DEFINER functions (add_credits_after_validation, consume_credit_for_discovery, get_discoveries_with_location, get_discovery_analysis, grant_initial_credits, refund_credit)
    - Verified working: get_discoveries_with_location, add_credits_after_validation, consume_credit_for_discovery
    - [ ] Verify working: refund_credit (failure path refund), grant_initial_credits (starter credits idempotency), get_discovery_analysis (owner/admin access)
  - [ ] Simplify discoveries INSERT policies to authenticated-only with with_check (auth.uid() = user_id)
  - [ ] Schedule Postgres upgrade to latest patched minor version
  - [ ] Remove graphql_public from [api].schemas in config.toml if GraphQL is not required

- Edge Functions
  - [x] nearby-places uses authenticated user (anon key + Authorization header) instead of service role
  - [x] verify_jwt settings confirmed: ask-ai-v7=true, nearby-places=true, validate-receipt=true, shared-discovery=false
  - [ ] Add rate limiting/abuse controls for shared-discovery (per-IP throttle, TTL/HMAC token)

- Auth
  - [ ] Enable leaked password protection (HaveIBeenPwned)
  - [ ] Enable email confirmations for sign-ups in production
  - [ ] Verify MFA/TOTP UX for high‑risk actions

- Privacy & Compliance
  - [ ] Define retention for raw_receipt_data (delete after X days) and/or encrypt with pgsodium
  - [ ] Implement DSAR export/delete function and operational runbook
  - [ ] Confirm EU region and DPA with Supabase; document subprocessors

- Configuration & Secrets
  - [ ] Add explicit per-function verify_jwt blocks in supabase/config.toml for clarity
  - [ ] Document secret rotation procedures and incident response playbooks

Deployment notes for completed items
- Apply DB migration locally or to your target environment:
  - supabase db push
- Redeploy the updated Edge Function:
  - supabase functions deploy nearby-places
