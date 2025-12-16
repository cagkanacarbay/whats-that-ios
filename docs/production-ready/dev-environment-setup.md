# Development Environment Setup

Guide for creating a new Supabase development environment after promoting the existing dev to production.

---

## Overview

This creates a fresh development database by cloning the schema from production. Use this for ongoing development and testing.

---

## 1. Create New Supabase Project

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard)
2. Click **New Project**
3. Configure:
   - **Name**: `whats-that-dev`
   - **Database Password**: Generate and save
   - **Region**: Same as production
   - **Plan**: Free tier is sufficient for dev
4. Save credentials:
   - Project URL
   - Anon Key
   - Service Role Key
   - Database Password

---

## 2. Enable Extensions

In SQL Editor:

```sql
CREATE EXTENSION IF NOT EXISTS postgis SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

---

## 3. Clone Schema from Production

```bash
# Export schema from production (no data)
pg_dump \
  --schema-only \
  --no-owner \
  --no-privileges \
  -h db.<prod-project-ref>.supabase.co \
  -p 5432 \
  -U postgres \
  -d postgres \
  -f schema_dump.sql

# Import to new dev project
psql \
  -h db.<dev-project-ref>.supabase.co \
  -p 5432 \
  -U postgres \
  -d postgres \
  -f schema_dump.sql
```

---

## 4. Seed Voice Inventory

```sql
INSERT INTO public.voice_inventory (provider, tts_model, voice_model_id, display_name) VALUES
  ('fish','s1','bf322df2096a46f18c579d0baa36f41d','Adrian'),
  ('fish','s1','933563129e564b19a115bedd57b7406a','Sarah'),
  ('fish','s1','536d3a5e000945adb7038665781a4aca','Ethan'),
  ('fish','s1','e3cd384158934cc9a01029cd7d278634','Laura')
ON CONFLICT DO NOTHING;
```

---

## 5. Create Storage Buckets

Create via Storage dashboard:

### `discovery_images`
- Public: No
- MIME types: `image/jpeg`, `image/png`, `image/heic`, `image/heif`
- Max size: 50MB

### `voiceovers`
- Public: No
- MIME types: `audio/mpeg`, `audio/mp3`
- Max size: 100MB

Add RLS policies (see production setup for SQL).

---

## 6. Configure Auth Providers

Set up Apple and Google with **development/sandbox** credentials.

---

## 7. Set Dev Secrets

```bash
supabase link --project-ref <dev-project-ref>

supabase secrets set \
  DENO_ENV=development \
  LOG_LEVEL=debug \
  APNS_ENVIRONMENT=sandbox \
  ALLOWED_ORIGINS="https://whats-that.app,http://localhost:5173"
```

Set remaining API keys (can use same keys as production or separate dev keys).

---

## 8. Deploy Edge Functions

```bash
supabase functions deploy ask-ai-v7
supabase functions deploy generate-voiceover
supabase functions deploy validate-receipt
supabase functions deploy nearby-places
supabase functions deploy shared-discovery --no-verify-jwt
```

---

## 9. Update iOS Development.xcconfig

Create/update `native/Config/Environments/Development.xcconfig`:

```xcconfig
SUPABASE_URL_SCHEME = https:/
SUPABASE_URL_HOST_PATH = /<dev-project-ref>.supabase.co
SUPABASE_URL = $(SUPABASE_URL_SCHEME)$(SUPABASE_URL_HOST_PATH)
SUPABASE_ANON_KEY = <dev-anon-key>
GOOGLE_CLIENT_ID = <dev-google-client-id>
GOOGLE_REVERSED_CLIENT_ID = <dev-reversed-client-id>
```

---

## 10. Test Account

Create a test user for development:
- Email: `dev@whats-that.app`
- Grant initial credits manually via SQL if needed
