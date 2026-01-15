# Edge Function Change Strategy

We use **Strategy A: In-place updates with backwards compatibility** for edge function changes.

## Why Strategy A?

| Strategy | Description | Pros | Cons |
|----------|-------------|------|------|
| **A: In-place (chosen)** | Update existing function to handle old + new clients | Simple, one endpoint per feature | Must maintain backwards compat |
| B: Versioned endpoints | Create new function for each version (v1, v2, v3) | Full control per version | Endpoint proliferation, maintenance burden |

We chose Strategy A because:
- Our edge functions are relatively simple
- Most changes are additive (new fields, new features)
- Maintaining multiple versions of each function would be complex

## Backwards Compatibility Patterns

### Pattern 1: Optional Request Fields

Old apps won't send new fields. Handle their absence gracefully.

```typescript
// ❌ Bad: Requires new field
const { image, location, language } = await req.json();
if (!language) throw new Error('language required');

// ✅ Good: New field is optional with default
const { image, location, language = 'en' } = await req.json();
```

### Pattern 2: Additive Response Fields

Add new fields to responses. Old apps will ignore them.

```typescript
// Old response (v1 app expects this)
{ title: "...", description: "..." }

// New response (v2 app uses new fields, v1 ignores them)
{ title: "...", description: "...", audio_url: "...", is_favorite: false }
```

### Pattern 3: Conditional Behavior

When behavior must differ, check for signals from the client.

```typescript
// Option A: Check for presence of new field
const body = await req.json();
const isNewClient = 'enhanced_mode' in body;

// Option B: Check app version header
const appVersion = req.headers.get('X-App-Version');
const isV2 = appVersion && compareVersions(appVersion, '2.0.0') >= 0;

if (isV2) {
  // Enhanced behavior for new clients
} else {
  // Legacy behavior for old clients
}
```

### Pattern 4: Graceful Degradation

When depending on new database columns that might not exist:

```typescript
// Fetch with new column, handle if it doesn't exist
const { data, error } = await supabase
  .from('discoveries')
  .select('*, audio_guide_url')  // new column
  .eq('id', id)
  .single();

// Return response that works for both old and new apps
return {
  ...data,
  audio_guide_url: data.audio_guide_url ?? null  // null-safe for old DBs
};
```

## Deployment Process for Edge Functions

### 1. Develop and Test Locally

```bash
# Start local Supabase
supabase start

# Run function locally
supabase functions serve analyze-image --env-file .env.local

# Test with curl
curl -X POST http://localhost:54321/functions/v1/analyze-image \
  -H "Authorization: Bearer $ANON_KEY" \
  -d '{"image": "base64...", "location": {...}}'
```

### 2. Deploy to Development

```bash
# Deploy to dev project
supabase functions deploy analyze-image --project-ref vibcgzetgbjgmaigixmh

# Test with dev TestFlight build
# Verify both old and new request formats work
```

### 3. Deploy to Production

```bash
# Deploy to production (with JWT verification as appropriate)
supabase functions deploy analyze-image --project-ref vipghlhvnrdheoydynty

# For public endpoints (like shared-discovery)
supabase functions deploy shared-discovery --no-verify-jwt --project-ref vipghlhvnrdheoydynty
```

### 4. Monitor

```bash
# Check logs for errors
supabase functions logs analyze-image --project-ref vipghlhvnrdheoydynty
```

## Handling Breaking Changes

Sometimes you genuinely need to change behavior in a non-backwards-compatible way.

### Option 1: Sunset Period

1. Deploy new function with deprecation warning for old behavior
2. Log when old clients use deprecated path
3. After X weeks, remove old behavior
4. Force app update announcement if critical

### Option 2: New Endpoint

When in-place update is too complex:

```
analyze-image      → original, maintenance mode only
analyze-image-v2   → new implementation
```

Update new app to call v2, eventually retire original.

### Option 3: Feature Flag

Control behavior via database flag:

```typescript
const { data: flags } = await supabase
  .from('feature_flags')
  .select('*')
  .eq('name', 'use_new_analysis');

if (flags?.[0]?.enabled) {
  return newAnalysis(body);
} else {
  return legacyAnalysis(body);
}
```

## Current Edge Functions

| Function | JWT | Description |
|----------|-----|-------------|
| `analyze-image` | Required | Main discovery analysis |
| `generate-audio-guide` | Required | Audio guide generation |
| `shared-discovery` | No | Public share page API |
| `verify-purchase` | Required | StoreKit receipt verification |
| `nearby-places` | Required | Location-based place lookup |

## Checklist: Before Deploying Edge Function Changes

- [ ] Does the change maintain backwards compatibility?
- [ ] Have I tested with old app request format?
- [ ] Have I tested with new app request format?
- [ ] Have I deployed to development first?
- [ ] Have I verified on development TestFlight?
- [ ] Am I deploying to production before the app update?
- [ ] Do I have logs/monitoring ready?
