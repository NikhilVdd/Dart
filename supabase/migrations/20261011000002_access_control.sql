-- Row level security and column privileges.
--
-- Principles:
--   * Signed-out (anon) clients can read nothing but the campus list.
--   * You see groups you belong to, plus building communities on your campus (so you can find yours).
--   * Runs and requests are visible to their audience: the group, or the whole campus.
--   * Status changes on requests only happen through the RPCs in the next migration, which
--     enforce the lifecycle. Direct UPDATEs can only edit descriptive fields while still open.

-- ---------------------------------------------------------------------------
-- Membership helpers (security definer to avoid recursive RLS on group_members)
-- ---------------------------------------------------------------------------

create function public.my_campus_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select campus_id from public.profiles where id = auth.uid();
$$;

create function public.is_group_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = auth.uid()
  );
$$;

create function public.is_group_admin(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = auth.uid() and role in ('owner', 'admin')
  );
$$;

create function public.can_see_run(p_run_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.runs r
    where r.id = p_run_id
      and (
        r.runner_id = auth.uid()
        or (r.group_id is not null and public.is_group_member(r.group_id))
        or (r.audience = 'campus' and r.campus_id = public.my_campus_id())
      )
  );
$$;

create function public.can_see_request(p_request_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.requests q
    where q.id = p_request_id
      and (
        q.requester_id = auth.uid()
        or q.helper_id = auth.uid()
        or (q.run_id is not null and exists (select 1 from public.runs r where r.id = q.run_id and r.runner_id = auth.uid()))
        or (
          q.status = 'open' and (
            (q.group_id is not null and public.is_group_member(q.group_id))
            or (q.group_id is null and q.campus_id = public.my_campus_id())
          )
        )
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- Integrity triggers that depend on the caller
-- ---------------------------------------------------------------------------

-- Fill campus_id from the creator's profile so clients never have to send it.
create function public.fill_campus_from_creator()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.campus_id is null then
    new.campus_id := (select campus_id from public.profiles where id = coalesce(
      auth.uid(),
      (to_jsonb(new) ->> case tg_table_name when 'runs' then 'runner_id' else 'requester_id' end)::uuid
    ));
  end if;
  return new;
end;
$$;

create trigger runs_fill_campus before insert on public.runs
  for each row execute function public.fill_campus_from_creator();
create trigger requests_fill_campus before insert on public.requests
  for each row execute function public.fill_campus_from_creator();

-- A list item's run (if any) must belong to the same group.
create function public.check_list_item_run()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.run_id is not null and not exists (
    select 1 from public.runs where id = new.run_id and group_id = new.group_id
  ) then
    raise exception 'run % is not part of group %', new.run_id, new.group_id using errcode = '23514';
  end if;
  return new;
end;
$$;

create function public.stamp_list_item_editor()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end;
$$;

create trigger list_items_stamp_editor before update on public.list_items
  for each row execute function public.stamp_list_item_editor();

create trigger list_items_check_run before insert or update of run_id, group_id on public.list_items
  for each row execute function public.check_list_item_run();

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated, public;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

grant select on public.campuses to anon, authenticated;
grant select on public.places to authenticated;

grant select on public.profiles to authenticated;
grant update (display_name, home_place_id) on public.profiles to authenticated;

grant select on public.groups to authenticated;
grant update (name, place_id) on public.groups to authenticated;

grant select, delete on public.group_members to authenticated;

grant select, delete on public.runs to authenticated;
grant insert (group_id, audience, store_place_id, store_label, destination_place_id, destination_label,
              note, closes_at, fee_cents, max_added_minutes, capacity)
  on public.runs to authenticated;
grant update (note, status, closes_at, max_added_minutes, capacity) on public.runs to authenticated;

grant select, delete on public.list_items to authenticated;
grant insert (group_id, run_id, body, quantity) on public.list_items to authenticated;
grant update (body, quantity, status) on public.list_items to authenticated;

grant select on public.requests to authenticated;
grant insert (group_id, title, details, pickup_place_id, pickup_label, destination_place_id,
              destination_label, deliver_by, reward_cents, merchandise_budget_cents, est_minutes)
  on public.requests to authenticated;
grant update (title, details, pickup_place_id, pickup_label, destination_place_id, destination_label,
              deliver_by, reward_cents, merchandise_budget_cents, est_minutes)
  on public.requests to authenticated;

grant select on public.request_events to authenticated;

grant select, delete on public.messages to authenticated;
grant insert (group_id, run_id, body) on public.messages to authenticated;

-- Helper functions used inside policies.
grant execute on function public.my_campus_id() to authenticated;
grant execute on function public.is_group_member(uuid) to authenticated;
grant execute on function public.is_group_admin(uuid) to authenticated;
grant execute on function public.can_see_run(uuid) to authenticated;
grant execute on function public.can_see_request(uuid) to authenticated;
grant execute on function public.distance_m(double precision, double precision, double precision, double precision) to authenticated;
grant execute on function public.initials_for(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------

alter table public.campuses enable row level security;
alter table public.places enable row level security;
alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.runs enable row level security;
alter table public.list_items enable row level security;
alter table public.requests enable row level security;
alter table public.request_events enable row level security;
alter table public.messages enable row level security;

create policy "campuses are public" on public.campuses
  for select to anon, authenticated using (true);

create policy "places are visible to signed-in users" on public.places
  for select to authenticated using (true);

-- Profiles hold only a display name, initials, campus and building – no contact details.
create policy "profiles are visible to signed-in users" on public.profiles
  for select to authenticated using (true);
create policy "users edit their own profile" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy "members and campus neighbors see groups" on public.groups
  for select to authenticated using (
    public.is_group_member(id)
    or (kind = 'building' and campus_id = public.my_campus_id())
  );
create policy "admins edit groups" on public.groups
  for update to authenticated using (public.is_group_admin(id)) with check (public.is_group_admin(id));

create policy "members see the roster" on public.group_members
  for select to authenticated using (public.is_group_member(group_id));
create policy "members leave, admins remove" on public.group_members
  for delete to authenticated using (user_id = auth.uid() or public.is_group_admin(group_id));

-- Visibility predicates are inlined (not can_see_run(id)) so INSERT ... RETURNING can see the new row.
create policy "audience sees runs" on public.runs
  for select to authenticated using (
    runner_id = auth.uid()
    or (group_id is not null and public.is_group_member(group_id))
    or (audience = 'campus' and campus_id = public.my_campus_id())
  );
create policy "runners create runs for their groups or campus" on public.runs
  for insert to authenticated with check (
    runner_id = auth.uid()
    and (group_id is null or public.is_group_member(group_id))
    and (audience = 'campus' or group_id is not null)
  );
create policy "runners update their runs" on public.runs
  for update to authenticated using (runner_id = auth.uid()) with check (runner_id = auth.uid());
create policy "runners delete their runs" on public.runs
  for delete to authenticated using (runner_id = auth.uid());

create policy "members see the list" on public.list_items
  for select to authenticated using (public.is_group_member(group_id));
create policy "members add to the list" on public.list_items
  for insert to authenticated with check (added_by = auth.uid() and public.is_group_member(group_id));
create policy "members check off items" on public.list_items
  for update to authenticated using (public.is_group_member(group_id))
  with check (public.is_group_member(group_id));
create policy "authors and admins remove items" on public.list_items
  for delete to authenticated using (added_by = auth.uid() or public.is_group_admin(group_id));

create policy "audience sees requests" on public.requests
  for select to authenticated using (
    requester_id = auth.uid()
    or helper_id = auth.uid()
    or (run_id is not null and exists (select 1 from public.runs r where r.id = run_id and r.runner_id = auth.uid()))
    or (
      status = 'open' and (
        (group_id is not null and public.is_group_member(group_id))
        or (group_id is null and campus_id = public.my_campus_id())
      )
    )
  );
create policy "requesters post requests" on public.requests
  for insert to authenticated with check (
    requester_id = auth.uid()
    and status = 'open'
    and helper_id is null
    and run_id is null
    and (group_id is null or public.is_group_member(group_id))
  );
create policy "requesters edit open requests" on public.requests
  for update to authenticated using (requester_id = auth.uid() and status = 'open')
  with check (requester_id = auth.uid() and status = 'open');

create policy "participants see the timeline" on public.request_events
  for select to authenticated using (public.can_see_request(request_id));

create policy "members read chat" on public.messages
  for select to authenticated using (public.is_group_member(group_id));
create policy "members post as themselves" on public.messages
  for insert to authenticated with check (sender_id = auth.uid() and public.is_group_member(group_id));
create policy "senders delete their messages" on public.messages
  for delete to authenticated using (sender_id = auth.uid());
