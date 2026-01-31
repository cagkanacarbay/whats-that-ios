# Analytics SQL Queries

SQL queries for running in Supabase SQL Editor.

---

## New Users Since Jan 18, 2026 - Discovery Analysis

This query finds all users who first signed up on or after January 18th, 2026, and shows:
- Total count of new users
- How many have made at least one discovery
- How many have made zero discoveries

```sql
WITH new_users AS (
  -- Get all users who signed up on or after Jan 18, 2026
  SELECT id AS user_id
  FROM auth.users
  WHERE created_at >= '2026-01-18'
),
user_discovery_counts AS (
  -- Count discoveries for each new user
  SELECT
    nu.user_id,
    COUNT(d.id) AS discovery_count
  FROM new_users nu
  LEFT JOIN discoveries d ON d.user_id = nu.user_id
  GROUP BY nu.user_id
)
SELECT
  COUNT(*) AS total_new_users,
  COUNT(CASE WHEN discovery_count > 0 THEN 1 END) AS users_with_discoveries,
  COUNT(CASE WHEN discovery_count = 0 THEN 1 END) AS users_without_discoveries
FROM user_discovery_counts;
```

### Sample Output

| total_new_users | users_with_discoveries | users_without_discoveries |
|-----------------|------------------------|---------------------------|
| 150             | 87                     | 63                        |

---

### Detailed Version (per-user breakdown)

If you want to see each user individually:

```sql
WITH new_users AS (
  SELECT id AS user_id, email, created_at
  FROM auth.users
  WHERE created_at >= '2026-01-18'
)
SELECT
  nu.user_id,
  nu.email,
  nu.created_at AS signup_date,
  COUNT(d.id) AS discovery_count,
  CASE WHEN COUNT(d.id) > 0 THEN 'Yes' ELSE 'No' END AS has_discoveries
FROM new_users nu
LEFT JOIN discoveries d ON d.user_id = nu.user_id
GROUP BY nu.user_id, nu.email, nu.created_at
ORDER BY nu.created_at DESC;
```

---

## New Users Without Any Discoveries

Returns all user details for new users (since Jan 18, 2026) who have NOT created any discoveries.

```sql
SELECT
  u.id AS user_id,
  u.email,
  u.created_at AS signup_date,
  u.last_sign_in_at,
  u.raw_user_meta_data
FROM auth.users u
WHERE u.created_at >= '2026-01-18'
  AND NOT EXISTS (
    SELECT 1
    FROM discoveries d
    WHERE d.user_id = u.id
  )
ORDER BY u.created_at DESC;
```
