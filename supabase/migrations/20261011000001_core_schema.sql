-- Grab core schema
--
-- Vocabulary (matches the iOS app):
--   request  – a person asking for a physical outcome ("charger from Moffitt to Unit 3, $10").
--   run      – movement that is already happening ("Maya is at Trader Joe's, heading home").
--              Runs are the supply side: before anyone makes a dedicated trip, we try to
--              attach requests to runs whose detour is small.
--   group    – a free friend group or a paid building community.
--
-- Money is stored in integer cents. Coordinates are WGS84 lat/lng doubles; at campus scale a
-- haversine distance is plenty, so PostGIS is not required.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.place_kind as enum ('store', 'restaurant', 'library', 'residence', 'campus', 'transit', 'other');
create type public.group_kind as enum ('friends', 'building');
create type public.member_role as enum ('owner', 'admin', 'member');
create type public.run_audience as enum ('friends', 'building', 'campus');
create type public.run_status as enum ('open', 'shopping', 'returning', 'completed', 'cancelled');
create type public.request_status as enum ('open', 'accepted', 'picking_up', 'on_the_way', 'completed', 'cancelled');
create type public.list_item_status as enum ('needed', 'picked', 'unavailable');

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create function public.initials_for(name text)
returns text
language sql
immutable
set search_path = ''
as $$
  with n as (select regexp_split_to_array(btrim(name), '\s+') as parts)
  select coalesce(nullif(upper(
    left(parts[1], 1) ||
    case when cardinality(parts) > 1 then left(parts[cardinality(parts)], 1) else '' end
  ), ''), '?')
  from n;
$$;

-- Great-circle distance in meters.
create function public.distance_m(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision
language sql
immutable
parallel safe
set search_path = ''
as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- ---------------------------------------------------------------------------
-- Campuses and places
-- ---------------------------------------------------------------------------

create table public.campuses (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  email_domains text[] not null default '{}',
  lat double precision not null,
  lng double precision not null,
  created_at timestamptz not null default now()
);

create table public.places (
  id uuid primary key default gen_random_uuid(),
  campus_id uuid not null references public.campuses (id) on delete cascade,
  name text not null,
  detail text,
  kind public.place_kind not null,
  address text,
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  created_at timestamptz not null default now()
);

create index places_campus_idx on public.places (campus_id, kind);

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 60),
  initials text generated always as (public.initials_for(display_name)) stored,
  campus_id uuid references public.campuses (id) on delete set null,
  home_place_id uuid references public.places (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- Create a profile for every new auth user; campus comes from the email domain.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_domain text := lower(split_part(coalesce(new.email, ''), '@', 2));
  v_name text := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
    nullif(initcap(replace(split_part(coalesce(new.email, ''), '@', 1), '.', ' ')), ''),
    'Grab member'
  );
begin
  insert into public.profiles (id, display_name, campus_id)
  values (
    new.id,
    left(v_name, 60),
    (select c.id from public.campuses c
      where v_domain = any (c.email_domains)
         or exists (select 1 from unnest(c.email_domains) d where v_domain like '%.' || d)
      limit 1)
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Groups
-- ---------------------------------------------------------------------------

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 60),
  kind public.group_kind not null,
  campus_id uuid references public.campuses (id) on delete set null,
  place_id uuid references public.places (id) on delete set null,
  invite_code text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint building_groups_have_place check (kind <> 'building' or place_id is not null)
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role public.member_role not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index group_members_user_idx on public.group_members (user_id);

-- ---------------------------------------------------------------------------
-- Runs (supply: trips that are already happening)
-- ---------------------------------------------------------------------------

create table public.runs (
  id uuid primary key default gen_random_uuid(),
  runner_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  campus_id uuid references public.campuses (id) on delete set null,
  group_id uuid references public.groups (id) on delete cascade,
  audience public.run_audience not null,
  store_place_id uuid references public.places (id) on delete set null,
  store_label text not null,
  destination_place_id uuid references public.places (id) on delete set null,
  destination_label text not null,
  note text,
  status public.run_status not null default 'open',
  closes_at timestamptz not null,
  fee_cents integer not null default 0 check (fee_cents >= 0),
  max_added_minutes integer not null default 10 check (max_added_minutes between 0 and 120),
  capacity integer not null default 3 check (capacity between 1 and 20),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_runs_have_group check (audience = 'campus' or group_id is not null),
  constraint friend_runs_are_free check (audience <> 'friends' or fee_cents = 0)
);

create index runs_open_idx on public.runs (campus_id, status, closes_at);
create index runs_group_idx on public.runs (group_id, created_at desc);

create trigger runs_updated_at before update on public.runs
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Shared shopping lists
-- ---------------------------------------------------------------------------

create table public.list_items (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  run_id uuid references public.runs (id) on delete set null,
  added_by uuid default auth.uid() references public.profiles (id) on delete set null,
  body text not null check (char_length(btrim(body)) between 1 and 200),
  quantity integer not null default 1 check (quantity between 1 and 99),
  status public.list_item_status not null default 'needed',
  updated_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index list_items_group_idx on public.list_items (group_id, created_at);

create trigger list_items_updated_at before update on public.list_items
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Requests (demand: a person asking for a physical outcome)
-- ---------------------------------------------------------------------------

create table public.requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  campus_id uuid references public.campuses (id) on delete set null,
  -- When set, only members of this group see the request.
  group_id uuid references public.groups (id) on delete cascade,
  -- The run that is fulfilling this request, if it rode along on existing movement.
  run_id uuid references public.runs (id) on delete set null,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  details text not null default '',
  -- A null pickup place means "any store works" – the network decides where it comes from.
  pickup_place_id uuid references public.places (id) on delete set null,
  pickup_label text not null,
  destination_place_id uuid references public.places (id) on delete set null,
  destination_label text not null,
  deliver_by timestamptz not null,
  reward_cents integer not null default 0 check (reward_cents >= 0),
  merchandise_budget_cents integer check (merchandise_budget_cents >= 0),
  est_minutes integer check (est_minutes between 1 and 240),
  status public.request_status not null default 'open',
  helper_id uuid references public.profiles (id) on delete set null,
  accepted_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint helper_is_not_requester check (helper_id is null or helper_id <> requester_id),
  constraint helper_matches_status check (
    (status in ('open', 'cancelled')) or helper_id is not null
  ),
  constraint open_requests_have_no_helper check (status <> 'open' or helper_id is null)
);

create index requests_open_idx on public.requests (campus_id, status, deliver_by);
create index requests_requester_idx on public.requests (requester_id, created_at desc);
create index requests_helper_idx on public.requests (helper_id, created_at desc);
create index requests_run_idx on public.requests (run_id);

create trigger requests_updated_at before update on public.requests
  for each row execute function public.set_updated_at();

-- Status timeline, written only by trigger.
create table public.request_events (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.requests (id) on delete cascade,
  status public.request_status not null,
  actor_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create index request_events_request_idx on public.request_events (request_id, created_at);

create function public.log_request_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.request_events (request_id, status, actor_id)
    values (new.id, new.status, auth.uid());
  end if;
  return new;
end;
$$;

create trigger requests_log_status after insert or update of status on public.requests
  for each row execute function public.log_request_status();

-- ---------------------------------------------------------------------------
-- Group chat
-- ---------------------------------------------------------------------------

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  sender_id uuid references public.profiles (id) on delete set null default auth.uid(),
  run_id uuid references public.runs (id) on delete set null,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index messages_group_idx on public.messages (group_id, created_at desc);
