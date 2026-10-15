-- 1. Requester confirmation: helpers can move a request as far as "delivered"; only the requester
--    marks it completed. Unconfirmed deliveries auto-complete after 24 hours.
-- 2. Expiry: open requests past their deadline become "expired"; runs that are done are closed.
-- 3. Account deletion (required by the App Store): delete_my_account().

alter table public.requests
  add column delivered_at timestamptz,
  add column expired_at timestamptz;

-- A helper is required only while a delivery is in progress. Finished requests may lose their
-- helper when that account is deleted.
alter table public.requests drop constraint helper_matches_status;
alter table public.requests add constraint helper_matches_status check (
  status not in ('accepted', 'picking_up', 'on_the_way', 'delivered') or helper_id is not null
);

-- ---------------------------------------------------------------------------
-- Lifecycle
--   open -> accepted -> picking_up -> on_the_way -> delivered -> completed
--   requester confirms from on_the_way or delivered; delivered auto-completes after 24 h
-- ---------------------------------------------------------------------------

create or replace function public.advance_request(p_request_id uuid, p_status public.request_status)
returns public.requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_request public.requests;
  v_order constant public.request_status[] :=
    array['accepted', 'picking_up', 'on_the_way', 'delivered', 'completed']::public.request_status[];
  v_from integer;
  v_to integer;
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;

  select * into v_request from public.requests where id = p_request_id for update;
  if not found or v_uid not in (v_request.requester_id, coalesce(v_request.helper_id, v_request.requester_id)) then
    raise exception 'request not found' using errcode = 'P0002';
  end if;

  v_from := array_position(v_order, v_request.status);
  v_to := array_position(v_order, p_status);
  if v_from is null or v_to is null or v_to <= v_from then
    raise exception 'cannot move request from % to %', v_request.status, p_status using errcode = 'P0001';
  end if;

  if v_uid = v_request.requester_id then
    -- The requester only confirms receipt, once it's on the way or marked delivered.
    if not (p_status = 'completed' and v_request.status in ('on_the_way', 'delivered')) then
      raise exception 'only the helper can update this step' using errcode = '42501';
    end if;
  elsif p_status = 'completed' then
    raise exception 'the requester confirms completion; mark it delivered instead' using errcode = '42501';
  end if;

  update public.requests
  set status = p_status,
      delivered_at = case when p_status = 'delivered' then now() else delivered_at end,
      completed_at = case when p_status = 'completed' then now() else completed_at end
  where id = p_request_id
  returning * into v_request;
  return v_request;
end;
$$;

create or replace function public.run_seats_left(p_run_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select r.capacity - (
    select count(*)::integer from public.requests q
    where q.run_id = r.id and q.status in ('accepted', 'picking_up', 'on_the_way', 'delivered')
  )
  from public.runs r where r.id = p_run_id;
$$;

create or replace function public.my_earnings()
returns table (completed_count integer, earned_cents bigint, active_count integer)
language sql
stable
security definer
set search_path = ''
as $$
  select
    count(*) filter (where status = 'completed')::integer,
    coalesce(sum(reward_cents) filter (where status = 'completed'), 0)::bigint,
    count(*) filter (where status in ('accepted', 'picking_up', 'on_the_way', 'delivered'))::integer
  from public.requests
  where helper_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Housekeeping, run every minute by pg_cron
-- ---------------------------------------------------------------------------

create function public.expire_stale()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expired integer;
  v_confirmed integer;
  v_runs integer;
begin
  update public.requests
  set status = 'expired', expired_at = now()
  where status = 'open' and deliver_by < now();
  get diagnostics v_expired = row_count;

  update public.requests
  set status = 'completed', completed_at = now()
  where status = 'delivered' and delivered_at < now() - interval '24 hours';
  get diagnostics v_confirmed = row_count;

  -- A run is done an hour after it stops taking requests once nothing is in flight,
  -- and three hours after regardless.
  update public.runs r
  set status = 'completed'
  where r.status in ('open', 'shopping', 'returning')
    and (
      r.closes_at < now() - interval '3 hours'
      or (
        r.closes_at < now() - interval '1 hour'
        and not exists (
          select 1 from public.requests q
          where q.run_id = r.id and q.status in ('accepted', 'picking_up', 'on_the_way')
        )
      )
    );
  get diagnostics v_runs = row_count;

  return jsonb_build_object('expired_requests', v_expired, 'auto_completed', v_confirmed, 'closed_runs', v_runs);
end;
$$;

-- pg_cron ships with hosted Supabase; skip scheduling where it isn't available (e.g. tests).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('grab-expire-stale', '* * * * *', 'select public.expire_stale()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Account deletion
-- ---------------------------------------------------------------------------

-- Only stamp the editor on real edits. Deleting a profile clears list_items.updated_by via its
-- foreign key; stamping that update would write the deleted user's id straight back.
create or replace function public.stamp_list_item_editor()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.body, new.quantity, new.status) is distinct from (old.body, old.quantity, old.status) then
    new.updated_by := coalesce(auth.uid(), new.updated_by);
  end if;
  return new;
end;
$$;

create function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;

  -- Deliveries you were making: hand them back (or expire them if the deadline passed);
  -- ones you already delivered count as completed.
  update public.requests
  set status = case when deliver_by > now() then 'open'::public.request_status else 'expired'::public.request_status end,
      expired_at = case when deliver_by > now() then null else now() end,
      helper_id = null, run_id = null, accepted_at = null
  where helper_id = v_uid and status in ('accepted', 'picking_up', 'on_the_way');

  update public.requests
  set status = 'completed', completed_at = now()
  where helper_id = v_uid and status = 'delivered';

  -- Groups you own pass to the longest-standing admin, else the longest-standing member.
  update public.group_members gm
  set role = 'owner'
  from (
    select distinct on (m.group_id) m.group_id, m.user_id
    from public.group_members m
    join public.group_members mine
      on mine.group_id = m.group_id and mine.user_id = v_uid and mine.role = 'owner'
    where m.user_id <> v_uid
    order by m.group_id, (m.role = 'admin') desc, m.joined_at
  ) heir
  where gm.group_id = heir.group_id and gm.user_id = heir.user_id;

  -- Friend groups where you're the last member go away. Building groups stay for future neighbors.
  delete from public.groups g
  where g.kind = 'friends'
    and exists (select 1 from public.group_members where group_id = g.id and user_id = v_uid)
    and not exists (select 1 from public.group_members where group_id = g.id and user_id <> v_uid);

  -- Cascades remove the profile, your requests, runs and memberships; messages and list items
  -- stay with the author cleared.
  delete from auth.users where id = v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants (hosted Supabase grants EXECUTE on new functions by default; see migration 5)
-- ---------------------------------------------------------------------------

revoke execute on function public.expire_stale() from public, anon, authenticated;
revoke execute on function public.stamp_list_item_editor() from public, anon, authenticated;
revoke execute on function public.delete_my_account() from public, anon;
revoke execute on function public.advance_request(uuid, public.request_status) from public, anon;
revoke execute on function public.run_seats_left(uuid) from public, anon;
revoke execute on function public.my_earnings() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.advance_request(uuid, public.request_status) to authenticated;
grant execute on function public.run_seats_left(uuid) to authenticated;
grant execute on function public.my_earnings() to authenticated;
