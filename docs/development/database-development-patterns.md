# Database Development Patterns

Established conventions for developing database functions and Supabase features. Follow these patterns to ensure consistency and avoid common pitfalls.

---

## RPC Functions: Use `RETURNS TABLE` for Timestamps

When creating RPC functions that return timestamps, **always use `RETURNS TABLE`** instead of `RETURNS JSON`.

### Why

PostgREST (Supabase's API layer) automatically serializes `timestamptz` columns as ISO8601 when returning table rows. However, `json_build_object()` uses PostgreSQL's default text format which iOS/Swift `JSONDecoder` cannot parse.

| Approach | Timestamp Format | iOS Compatibility |
|----------|------------------|-------------------|
| `RETURNS TABLE` with `timestamptz` | `2026-02-03T12:00:00Z` | Works |
| `RETURNS JSON` with `json_build_object` | `2026-02-03 12:00:00+00` | Fails |

### Pattern

**Do this:**
```sql
CREATE FUNCTION get_data()
RETURNS TABLE (
  id bigint,
  name text,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY SELECT t.id, t.name, t.created_at, t.updated_at FROM my_table t;
END;
$$;
```

**Avoid this:**
```sql
CREATE FUNCTION get_data()
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN (
    SELECT json_build_object(
      'id', id,
      'name', name,
      'created_at', created_at  -- Will NOT be ISO8601
    ) FROM my_table
  );
END;
$$;
```

### If You Must Use `RETURNS JSON`

Explicitly format timestamps as ISO8601:
```sql
'created_at', to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
```

### Swift Repository Pattern

When the SQL function returns a flat table but the domain model expects nested objects, handle the mapping in the repository layer.

**IMPORTANT: When decoding Date fields, always use `JSONObject` + `jsonArray.decode()`**

PostgreSQL returns timestamps with fractional seconds (e.g., `2026-02-03T16:54:36.884454+00:00`). Swift's default `.iso8601` decoder does NOT support fractional seconds. The Supabase SDK's `jsonArray.decode()` method handles this correctly.

```swift
// Private struct matching the flat SQL response
private struct DataRow: Decodable {
    let id: Int64
    let name: String
    let createdAt: Date  // Has Date field - must use JSONObject pattern

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
    }
}

// CORRECT: Use JSONObject + jsonArray.decode() for Date fields
func fetchData() async throws -> DomainModel {
    let response: PostgrestResponse<[JSONObject]> = try await client.rpc("get_data").execute()
    let jsonArray: JSONArray = response.value.map { AnyJSON.object($0) }
    let rows: [DataRow] = try jsonArray.decode(as: DataRow.self)
    guard let row = rows.first else { throw DataError.noData }
    return row.toDomainModel()
}

// WRONG: Direct .value decoding fails for Date fields with fractional seconds
func fetchData() async throws -> DomainModel {
    let rows: [DataRow] = try await client.rpc("get_data").execute().value  // May fail on some devices!
    // ...
}
```

**When to use which pattern:**

| Struct has Date fields? | Pattern to use |
|------------------------|----------------|
| No | Direct `.execute().value` is fine |
| Yes | Must use `JSONObject` + `jsonArray.decode()` |

**Reference implementations:**
- `SupabaseDiscoveryRepository` - Uses `JSONObject` pattern for `DiscoveryRecord.createdAt`
- `SupabaseAppConfigRepository` - Uses `JSONObject` pattern for `AppConfigRow` timestamps
- `VoiceInventoryRepository` - Uses direct `.value` (no Date fields)

### Reference

Migration `20260203100000_refactor_get_app_config_returns_table.sql` demonstrates this pattern.

---

## Adding New Patterns

When documenting a new pattern:
1. **Clear title** describing what it covers
2. **Why** - The reasoning behind the pattern
3. **Pattern** - Code examples showing the correct approach
4. **Anti-pattern** - What to avoid and why
5. **Reference** - Related migrations or code
