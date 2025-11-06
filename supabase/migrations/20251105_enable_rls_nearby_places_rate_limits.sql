-- Enable RLS and owner-scoped policies for nearby-places rate limit table
-- Also ensure RPC is callable by authenticated users and pin function search_path

-- 1) Enable RLS on the table (previous migration disabled it)
alter table if exists public.nearby_places_rate_limits
  enable row level security;

-- 2) Policies: owner can read/insert/update their own counter
do $$ begin
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'nearby_places_rate_limits'
       and policyname = 'Near Places: owner can select'
  ) then
    create policy "Near Places: owner can select"
      on public.nearby_places_rate_limits
      for select
      using (auth.uid() = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'nearby_places_rate_limits'
       and policyname = 'Near Places: owner can insert'
  ) then
    create policy "Near Places: owner can insert"
      on public.nearby_places_rate_limits
      for insert
      with check (auth.uid() = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'nearby_places_rate_limits'
       and policyname = 'Near Places: owner can update'
  ) then
    create policy "Near Places: owner can update"
      on public.nearby_places_rate_limits
      for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end $$;

-- 3) Restrict RPC execute to needed roles and pin search_path for safety
-- Grant EXECUTE to authenticated (user-token calls) and keep service_role
revoke all on function public.enforce_nearby_places_rate_limit(uuid, integer, integer) from public;
grant execute on function public.enforce_nearby_places_rate_limit(uuid, integer, integer) to authenticated;
grant execute on function public.enforce_nearby_places_rate_limit(uuid, integer, integer) to service_role;

-- Pin function search_path per Supabase Advisor recommendation
alter function public.enforce_nearby_places_rate_limit(uuid, integer, integer)
  set search_path = '';

