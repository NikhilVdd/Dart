-- Lifecycle RPCs and the matching engine.
--
-- Core rule: before creating a new trip, try to use movement that is already happening.
-- A request rides along on a run when the run's detour (store -> pickup -> drop-off -> runner's
-- destination, versus store -> destination) fits inside the runner's max_added_minutes.

-- ---------------------------------------------------------------------------
-- Matching math
-- ---------------------------------------------------------------------------

-- Walking pace on a street grid: 80 m/min straight-line speed, with 1.3x grid factor.
-- Each stop that is not on the runner's path costs a fixed handling time.
create function public.walk_minutes(meters double precision)
returns double precision
language sql
immutable
parallel safe
set search_path = ''
as $$
  select meters * 1.3 / 80.0;
$$;

-- Extra minutes a runner spends to serve a request.
--   S = run store, D = run destination, P = request pickup (null => buy at S), Q = request drop-off.
create function public.detour_minutes(
  s_lat double precision, s_lng double precision,
  d_lat double precision, d_lng double precision,
  p_lat double precision, p_lng double precision,
  q_lat double precision, q_lng double precision
)
returns integer
language sql
immutable
parallel safe
set search_path = ''
as $$
  with pts as (
    select coalesce(p_lat, s_lat) as plat, coalesce(p_lng, s_lng) as plng,
           (p_lat is null) as buy_at_store
  )
  select greatest(0, ceil(
      public.walk_minutes(
        public.distance_m(s_lat, s_lng, plat, plng)
        + public.distance_m(plat, plng, q_lat, q_lng)
        + public.distance_m(q_lat, q_lng, d_lat, d_lng)
        - public.distance_m(s_lat, s_lng, d_lat, d_lng)
      )
      + case when buy_at_store then 3 else 2 end  -- shopping or pickup handling
      + 2                                          -- hand-off at drop-off
  ))::integer
  from pts;
$$;

-- ---------------------------------------------------------------------------
-- Groups
-- ---------------------------------------------------------------------------

create function public.create_group(p_name text, p_kind public.group_kind default 'friends', p_place_id uuid default null)
returns public.groups
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_group public.groups;
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;

  insert into public.groups (name, kind, campus_id, place_id, created_by)
  values (btrim(p_name), p_kind, public.my_campus_id(), p_place_id, v_uid)
  returning * into v_group;

  insert into public.group_members (group_id, user_id, role) values (v_group.id, v_uid, 'owner');
  return v_group;
end;
$$;

create function public.join_group(p_invite_code text)
returns public.groups
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_group public.groups;
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;

  select * into v_group from public.groups where invite_code = upper(btrim(p_invite_code));
  if not found then
    raise exception 'invite code not found' using errcode = 'P0002';
  end if;

  insert into public.group_members (group_id, user_id) values (v_group.id, v_uid)
  on conflict do nothing;
  return v_group;
end;
$$;

-- Building communities on your campus can be joined without an invite.
create function public.join_building_group(p_group_id uuid)
returns public.groups
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_group public.groups;
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;

  select * into v_group from public.groups
  where id = p_group_id and kind = 'building' and campus_id = public.my_campus_id();
  if not found then
    raise exception 'building group not found on your campus' using errcode = 'P0002';
  end if;

  insert into public.group_members (group_id, user_id) values (v_group.id, v_uid)
  on conflict do nothing;
  update public.profiles set home_place_id = coalesce(home_place_id, v_group.place_id) where id = v_uid;
  return v_group;
end;
$$;

-- ---------------------------------------------------------------------------
-- Request lifecycle
--   open -> accepted -> picking_up -> on_the_way -> completed
--   open|accepted -> cancelled (requester)
--   accepted|picking_up -> open (helper releases)
-- ---------------------------------------------------------------------------

create function public.run_seats_left(p_run_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select r.capacity - (
    select count(*)::integer from public.requests q
    where q.run_id = r.id and q.status not in ('completed', 'cancelled')
  )
  from public.runs r where r.id = p_run_id;
$$;

create function public.accept_request(p_request_id uuid, p_run_id uuid default null)
returns public.requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_request public.requests;
  v_run public.runs;
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  if not public.can_see_request(p_request_id) then
    raise exception 'request not found' using errcode = 'P0002';
  end if;

  select * into v_request from public.requests where id = p_request_id for update;
  if v_request.status <> 'open' then
    raise exception 'request is no longer open' using errcode = 'P0001';
  end if;
  if v_request.requester_id = v_uid then
    raise exception 'you cannot accept your own request' using errcode = 'P0001';
  end if;
  if v_request.deliver_by < now() then
    raise exception 'request deadline has passed' using errcode = 'P0001';
  end if;

  if p_run_id is not null then
    select * into v_run from public.runs where id = p_run_id for update;
    if not found or v_run.runner_id <> v_uid then
      raise exception 'run not found' using errcode = 'P0002';
    end if;
    if v_run.status not in ('open', 'shopping', 'returning') then
      raise exception 'run is no longer active' using errcode = 'P0001';
    end if;
    if public.run_seats_left(p_run_id) <= 0 then
      raise exception 'run is full' using errcode = 'P0001';
    end if;
  end if;

  update public.requests
  set status = 'accepted', helper_id = v_uid, run_id = p_run_id, accepted_at = now()
  where id = p_request_id
  returning * into v_request;
  return v_request;
end;
$$;

create function public.advance_request(p_request_id uuid, p_status public.request_status)
returns public.requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_request public.requests;
  v_order constant public.request_status[] := array['accepted', 'picking_up', 'on_the_way', 'completed']::public.request_status[];
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

  -- The helper drives the trip; the requester may only confirm receipt once it is on the way.
  if v_uid = v_request.requester_id and not (v_request.status = 'on_the_way' and p_status = 'completed') then
    raise exception 'only the helper can update this step' using errcode = '42501';
  end if;

  update public.requests
  set status = p_status,
      completed_at = case when p_status = 'completed' then now() else completed_at end
  where id = p_request_id
  returning * into v_request;
  return v_request;
end;
$$;

create function public.release_request(p_request_id uuid)
returns public.requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.requests;
begin
  update public.requests
  set status = 'open', helper_id = null, run_id = null, accepted_at = null
  where id = p_request_id
    and helper_id = auth.uid()
    and status in ('accepted', 'picking_up')
  returning * into v_request;
  if not found then
    raise exception 'request cannot be released' using errcode = 'P0001';
  end if;
  return v_request;
end;
$$;

create function public.cancel_request(p_request_id uuid)
returns public.requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.requests;
begin
  update public.requests
  set status = 'cancelled', cancelled_at = now()
  where id = p_request_id
    and requester_id = auth.uid()
    and status in ('open', 'accepted')
  returning * into v_request;
  if not found then
    raise exception 'request cannot be cancelled' using errcode = 'P0001';
  end if;
  return v_request;
end;
$$;

-- Ask a run's shopper for something: creates a request pre-filled from the run and visible to the
-- run's audience. The shopper still approves it with accept_request(request, run).
create function public.request_from_run(
  p_run_id uuid,
  p_title text,
  p_details text default '',
  p_merchandise_budget_cents integer default null
)
returns public.requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_run public.runs;
  v_request public.requests;
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  if not public.can_see_run(p_run_id) then
    raise exception 'run not found' using errcode = 'P0002';
  end if;

  select * into v_run from public.runs where id = p_run_id;
  if v_run.runner_id = v_uid then
    raise exception 'this is your own run' using errcode = 'P0001';
  end if;
  if v_run.status not in ('open', 'shopping') or v_run.closes_at < now() then
    raise exception 'run is closed to new requests' using errcode = 'P0001';
  end if;

  insert into public.requests (
    requester_id, campus_id, group_id, title, details,
    pickup_place_id, pickup_label, destination_place_id, destination_label,
    deliver_by, reward_cents, merchandise_budget_cents
  )
  values (
    v_uid, v_run.campus_id, v_run.group_id, btrim(p_title), coalesce(p_details, ''),
    v_run.store_place_id, v_run.store_label, v_run.destination_place_id, v_run.destination_label,
    v_run.closes_at + interval '1 hour', v_run.fee_cents, p_merchandise_budget_cents
  )
  returning * into v_request;
  return v_request;
end;
$$;

-- ---------------------------------------------------------------------------
-- Discovery and matching
-- ---------------------------------------------------------------------------

-- Earn feed: open requests you could take, nearest first (or soonest due when no location).
create function public.open_requests_nearby(
  p_lat double precision default null,
  p_lng double precision default null,
  p_radius_m double precision default 5000
)
returns setof public.requests
language sql
stable
security definer
set search_path = ''
as $$
  select q.*
  from public.requests q
  left join public.places pickup on pickup.id = q.pickup_place_id
  left join public.places dest on dest.id = q.destination_place_id
  where q.status = 'open'
    and q.deliver_by > now()
    and q.requester_id <> auth.uid()
    and public.can_see_request(q.id)
    and (
      p_lat is null or p_lng is null
      or coalesce(pickup.lat, dest.lat) is null
      or public.distance_m(p_lat, p_lng, coalesce(pickup.lat, dest.lat), coalesce(pickup.lng, dest.lng)) <= p_radius_m
    )
  order by
    case when p_lat is null or p_lng is null or coalesce(pickup.lat, dest.lat) is null then null
         else public.distance_m(p_lat, p_lng, coalesce(pickup.lat, dest.lat), coalesce(pickup.lng, dest.lng)) end
      nulls last,
    q.deliver_by;
$$;

-- For a runner: which open requests fit on this trip, smallest detour first.
create function public.match_requests_for_run(p_run_id uuid)
returns table (request_id uuid, detour_minutes integer, reward_cents integer)
language sql
stable
security definer
set search_path = ''
as $$
  select q.id, d.minutes, q.reward_cents
  from public.runs r
  join public.places s on s.id = r.store_place_id
  join public.places rd on rd.id = r.destination_place_id
  join public.requests q
    on q.status = 'open'
   and q.deliver_by > now()
   and q.requester_id <> r.runner_id
   and (q.group_id = r.group_id or (q.group_id is null and q.campus_id = r.campus_id))
  left join public.places p on p.id = q.pickup_place_id
  left join public.places qd on qd.id = q.destination_place_id
  cross join lateral (
    select case when qd.id is null then null
                else public.detour_minutes(s.lat, s.lng, rd.lat, rd.lng, p.lat, p.lng, qd.lat, qd.lng) end as minutes
  ) d
  where r.id = p_run_id
    and r.runner_id = auth.uid()
    and r.status in ('open', 'shopping', 'returning')
    -- Requests posted straight to this run's group always show; others must fit the detour budget.
    and ((r.group_id is not null and q.group_id = r.group_id) or d.minutes <= r.max_added_minutes)
  order by d.minutes nulls last, q.deliver_by;
$$;

-- For a requester: which active runs could carry this request, smallest detour first.
create function public.match_runs_for_request(p_request_id uuid)
returns table (run_id uuid, detour_minutes integer, fee_cents integer, seats_left integer)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, d.minutes, r.fee_cents, public.run_seats_left(r.id)
  from public.requests q
  join public.places qd on qd.id = q.destination_place_id
  left join public.places p on p.id = q.pickup_place_id
  join public.runs r
    on r.status in ('open', 'shopping', 'returning')
   and r.closes_at > now()
   and r.runner_id <> q.requester_id
   and public.can_see_run(r.id)
  join public.places s on s.id = r.store_place_id
  join public.places rd on rd.id = r.destination_place_id
  cross join lateral (
    select public.detour_minutes(s.lat, s.lng, rd.lat, rd.lng, p.lat, p.lng, qd.lat, qd.lng) as minutes
  ) d
  where q.id = p_request_id
    and q.requester_id = auth.uid()
    and q.status = 'open'
    -- A specific pickup must be the run's store, or close enough to fit; "any store" needs a store run.
    and (q.pickup_place_id is not null or s.kind = 'store')
    and d.minutes <= r.max_added_minutes
    and public.run_seats_left(r.id) > 0
  order by d.minutes, r.fee_cents;
$$;

create function public.my_earnings()
returns table (completed_count integer, earned_cents bigint, active_count integer)
language sql
stable
security definer
set search_path = ''
as $$
  select
    count(*) filter (where status = 'completed')::integer,
    coalesce(sum(reward_cents) filter (where status = 'completed'), 0)::bigint,
    count(*) filter (where status in ('accepted', 'picking_up', 'on_the_way'))::integer
  from public.requests
  where helper_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

grant execute on function public.walk_minutes(double precision) to authenticated;
grant execute on function public.detour_minutes(double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) to authenticated;
grant execute on function public.create_group(text, public.group_kind, uuid) to authenticated;
grant execute on function public.join_group(text) to authenticated;
grant execute on function public.join_building_group(uuid) to authenticated;
grant execute on function public.run_seats_left(uuid) to authenticated;
grant execute on function public.accept_request(uuid, uuid) to authenticated;
grant execute on function public.advance_request(uuid, public.request_status) to authenticated;
grant execute on function public.release_request(uuid) to authenticated;
grant execute on function public.cancel_request(uuid) to authenticated;
grant execute on function public.request_from_run(uuid, text, text, integer) to authenticated;
grant execute on function public.open_requests_nearby(double precision, double precision, double precision) to authenticated;
grant execute on function public.match_requests_for_run(uuid) to authenticated;
grant execute on function public.match_runs_for_request(uuid) to authenticated;
grant execute on function public.my_earnings() to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime: chat, lists, runs and request status stream to subscribed clients (RLS applies).
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table
  public.messages,
  public.list_items,
  public.runs,
  public.requests,
  public.request_events;
