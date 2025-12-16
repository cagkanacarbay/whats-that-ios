-- Generic rate limiting table for Edge functions
-- This replaces function-specific tables with a unified approach
-- Follows the same pattern as nearby_places_rate_limits but is generic

-- Create table for tracking rate limits per user per function
create table if not exists public.edge_function_rate_limits (
  user_id uuid not null,
  function_name text not null,
  window_start timestamptz not null default timezone('utc', now()),
  request_count integer not null default 0,
  primary key (user_id, function_name)
);

comment on table public.edge_function_rate_limits is
  'Sliding window counters for Edge function rate limiting. Keyed by user+function.';

comment on column public.edge_function_rate_limits.window_start is
  'UTC timestamp marking the beginning of the active fixed window.';

comment on column public.edge_function_rate_limits.request_count is
  'Number of requests recorded within the active window.';

-- Index for efficient lookups (primary key already indexes user_id, function_name)
-- Create additional index for cleanup queries if needed
create index if not exists idx_edge_rate_limits_window_start
  on public.edge_function_rate_limits (window_start);

-- Enable RLS (no direct user access, only via server-side functions)
alter table public.edge_function_rate_limits enable row level security;

-- No RLS policies needed since only service_role accesses this table

-- Generic rate limit enforcement function
-- Returns true if request is allowed, false if rate limited
create or replace function public.enforce_edge_function_rate_limit(
  p_user_id uuid,
  p_function_name text,
  p_window_seconds integer,
  p_max_requests integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := timezone('utc', now());
  v_window_start timestamptz;
  v_request_count integer;
begin
  -- Validate inputs
  if p_user_id is null then
    raise exception 'user_id cannot be null';
  end if;
  
  if p_function_name is null or p_function_name = '' then
    raise exception 'function_name cannot be null or empty';
  end if;
  
  if p_window_seconds <= 0 or p_max_requests <= 0 then
    raise exception 'window_seconds and max_requests must be positive';
  end if;

  -- Use upsert with locking to handle concurrent requests atomically
  loop
    -- Try to get existing record with lock
    select window_start, request_count
      into v_window_start, v_request_count
    from public.edge_function_rate_limits
    where user_id = p_user_id and function_name = p_function_name
    for update;

    if not found then
      -- No record exists, try to insert
      begin
        insert into public.edge_function_rate_limits (user_id, function_name, window_start, request_count)
        values (p_user_id, p_function_name, v_now, 1);
        return true;
      exception
        when unique_violation then
          -- Another transaction inserted simultaneously; retry the loop
          continue;
      end;
    end if;

    -- Check if window has expired
    if v_window_start <= v_now - make_interval(secs => p_window_seconds) then
      -- Window expired, reset counter
      update public.edge_function_rate_limits
         set window_start = v_now,
             request_count = 1
       where user_id = p_user_id and function_name = p_function_name;
      return true;
    end if;

    -- Check if limit exceeded
    if v_request_count >= p_max_requests then
      return false;
    end if;

    -- Increment counter
    update public.edge_function_rate_limits
       set request_count = v_request_count + 1
     where user_id = p_user_id and function_name = p_function_name;
    return true;
  end loop;
end;
$$;

comment on function public.enforce_edge_function_rate_limit is
  'Atomically enforces a fixed-window rate limit for Edge functions. Returns true if allowed, false if rate limited.';

-- Grant execute permission to service_role only
revoke all on function public.enforce_edge_function_rate_limit(uuid, text, integer, integer) from public;
grant execute on function public.enforce_edge_function_rate_limit(uuid, text, integer, integer) to service_role;
