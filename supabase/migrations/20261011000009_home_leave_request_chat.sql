-- 1. Home building: set_home_place() sets where you live and, for residences, puts you in that
--    building's group (creating it the first time anyone from that building joins).
-- 2. Leaving groups: leave_group().
-- 3. Private chat between a requester and their helper: request_messages.

-- ---------------------------------------------------------------------------
-- Home building
-- ---------------------------------------------------------------------------

create function public.set_home_place(p_place_id uuid)
returns public.groups
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_place public.places;
  v_group public.groups;
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;

  if p_place_id is null then
    update public.profiles set home_place_id = null where id = v_uid;
    return null;
  end if;

  select * into v_place from public.places where id = p_place_id;
  if not found then
    raise exception 'place not found' using errcode = 'P0002';
  end if;
  if v_place.campus_id is distinct from public.my_campus_id() then
    raise exception 'that place is not on your campus' using errcode = '22023';
  end if;

  update public.profiles set home_place_id = v_place.id where id = v_uid;

  -- You live in one building at a time: leave the groups of other buildings.
  delete from public.group_members m
  using public.groups g
  where g.id = m.group_id and m.user_id = v_uid and g.kind = 'building' and g.place_id <> v_place.id;

  if v_place.kind <> 'residence' then
    return null;
  end if;

  select * into v_group from public.groups where kind = 'building' and place_id = v_place.id
  order by created_at limit 1;
  if not found then
    insert into public.groups (name, kind, campus_id, place_id, created_by)
    values (left(v_place.name, 60), 'building', v_place.campus_id, v_place.id, v_uid)
    returning * into v_group;
  end if;

  insert into public.group_members (group_id, user_id) values (v_group.id, v_uid)
  on conflict do nothing;
  return v_group;
end;
$$;

-- Joining a building group makes it your home.
create or replace function public.join_building_group(p_group_id uuid)
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

  return public.set_home_place(v_group.place_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Leaving groups
-- ---------------------------------------------------------------------------

create function public.leave_group(p_group_id uuid)
returns void
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

  select g.* into v_group from public.groups g
  join public.group_members m on m.group_id = g.id and m.user_id = v_uid
  where g.id = p_group_id;
  if not found then
    raise exception 'you are not in that group' using errcode = 'P0002';
  end if;

  delete from public.group_members where group_id = p_group_id and user_id = v_uid;

  if v_group.kind = 'building' then
    update public.profiles set home_place_id = null where id = v_uid and home_place_id = v_group.place_id;
  elsif not exists (select 1 from public.group_members where group_id = p_group_id) then
    -- The last friend out closes the group.
    delete from public.groups where id = p_group_id;
  elsif not exists (select 1 from public.group_members where group_id = p_group_id and role in ('owner', 'admin')) then
    -- Hand the group to the longest-standing member so someone can still manage it.
    update public.group_members set role = 'owner'
    where (group_id, user_id) = (
      select group_id, user_id from public.group_members where group_id = p_group_id order by joined_at limit 1
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Requester <-> helper chat
-- ---------------------------------------------------------------------------

create table public.request_messages (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests (id) on delete cascade,
  sender_id uuid references public.profiles (id) on delete set null default auth.uid(),
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index request_messages_request_idx on public.request_messages (request_id, created_at);

-- True when the caller is the requester or the current helper.
create function public.is_request_participant(p_request_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.requests q
    where q.id = p_request_id and auth.uid() in (q.requester_id, q.helper_id)
  );
$$;

alter table public.request_messages enable row level security;

create policy "participants read the request chat" on public.request_messages
  for select to authenticated using (public.is_request_participant(request_id));
create policy "participants post to an active request chat" on public.request_messages
  for insert to authenticated with check (
    sender_id = auth.uid()
    and public.is_request_participant(request_id)
    and exists (
      select 1 from public.requests q
      where q.id = request_id and q.helper_id is not null
        and q.status in ('accepted', 'picking_up', 'on_the_way', 'delivered')
    )
  );

grant select on public.request_messages to authenticated;
grant insert (request_id, body) on public.request_messages to authenticated;

grant execute on function public.set_home_place(uuid) to authenticated;
grant execute on function public.leave_group(uuid) to authenticated;
grant execute on function public.is_request_participant(uuid) to authenticated;

alter publication supabase_realtime add table public.request_messages;

revoke execute on function public.set_home_place(uuid) from public, anon;
revoke execute on function public.leave_group(uuid) from public, anon;
revoke execute on function public.is_request_participant(uuid) from public, anon;
