-- Track per-user request counts for nearby-places edge function rate limiting.
create table if not exists public.nearby_places_rate_limits (
  user_id uuid primary key,
  window_start timestamptz not null default timezone('utc', now()),
  request_count integer not null default 0
);

comment on table public.nearby_places_rate_limits is
  'Sliding window counters backing the nearby-places edge function rate limiter.';

comment on column public.nearby_places_rate_limits.window_start is
  'UTC timestamp marking the beginning of the active fixed window.';

comment on column public.nearby_places_rate_limits.request_count is
  'Number of requests recorded within the active window.';

alter table public.nearby_places_rate_limits
  disable row level security;

-- Enforce a fixed-window rate limit atomically for a given user.
create or replace function public.enforce_nearby_places_rate_limit(
  p_user_id uuid,
  p_window_seconds integer,
  p_max_requests integer
)
returns boolean
language plpgsql
as $$
declare
  v_now timestamptz := timezone('utc', now());
  v_window_start timestamptz;
  v_request_count integer;
begin
  if p_window_seconds <= 0 or p_max_requests <= 0 then
    raise exception 'window and max requests must be positive';
  end if;

  loop
    select window_start, request_count
      into v_window_start, v_request_count
    from public.nearby_places_rate_limits
    where user_id = p_user_id
    for update;

    if not found then
      begin
        insert into public.nearby_places_rate_limits (user_id, window_start, request_count)
        values (p_user_id, v_now, 1);
        return true;
      exception
        when unique_violation then
          -- Another transaction inserted simultaneously; retry.
          continue;
      end;
    end if;

    if v_window_start <= v_now - make_interval(secs => p_window_seconds) then
      update public.nearby_places_rate_limits
         set window_start = v_now,
             request_count = 1
       where user_id = p_user_id;
      return true;
    end if;

    if v_request_count >= p_max_requests then
      return false;
    end if;

    update public.nearby_places_rate_limits
       set request_count = v_request_count + 1
     where user_id = p_user_id;
    return true;
  end loop;
end;
$$;

grant execute on function public.enforce_nearby_places_rate_limit(uuid, integer, integer)
  to service_role;
