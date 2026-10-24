-- Student safety, minor money restrictions, blocking/reporting, content guardrails, and
-- server-side action throttles. These controls are additive and default to the safest state.

create type public.age_band as enum ('not_set', 'under_18', '18_or_over');
create type public.account_status as enum ('active', 'suspended');

alter table public.profiles
  add column age_band public.age_band not null default 'not_set',
  add column account_status public.account_status not null default 'active',
  add column safety_rules_accepted_at timestamptz;

create function public.set_my_age_band(p_age_band public.age_band)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
begin
  if auth.uid() is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  if p_age_band = 'not_set' then
    raise exception 'choose an age band' using errcode = 'P0001';
  end if;

  select * into v_profile from public.profiles where id = auth.uid() for update;
  if v_profile.age_band <> 'not_set' then
    raise exception 'contact support to change your age band' using errcode = 'P0001';
  end if;
  update public.profiles set age_band = p_age_band where id = auth.uid() returning * into v_profile;
  return v_profile;
end;
$$;

create function public.accept_safety_rules()
returns public.profiles
language sql
security definer
set search_path = ''
as $$
  update public.profiles set safety_rules_accepted_at = now()
  where id = auth.uid() and account_status = 'active'
  returning *;
$$;

create table public.user_blocks (
  blocker_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table public.safety_reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  reported_user_id uuid references public.profiles (id) on delete set null,
  request_id uuid references public.requests (id) on delete set null,
  group_id uuid references public.groups (id) on delete set null,
  category text not null check (category in ('harassment', 'unsafe_handoff', 'prohibited_item', 'fraud', 'minor_safety', 'other')),
  details text not null check (char_length(btrim(details)) between 1 and 2000),
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index safety_reports_open_idx on public.safety_reports (status, created_at) where status in ('open', 'reviewing');

create function public.users_are_blocked(p_left uuid, p_right uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_blocks
    where (blocker_id = p_left and blocked_id = p_right)
       or (blocker_id = p_right and blocked_id = p_left)
  );
$$;

-- Caller-scoped wrapper used by RLS. It cannot be used to enumerate blocks between third parties.
create function public.is_blocked_with(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.users_are_blocked(auth.uid(), p_other);
$$;

-- Append-only, private counters. Product actions call this from BEFORE INSERT triggers.
create table public.rate_limit_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  action text not null,
  created_at timestamptz not null default now()
);
create index rate_limit_events_lookup_idx on public.rate_limit_events (user_id, action, created_at desc);

create function public.consume_rate_limit(p_action text, p_limit integer, p_window interval)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then return; end if;
  if (select account_status from public.profiles where id = v_uid) <> 'active' then
    raise exception 'this account is not permitted to perform that action' using errcode = '42501';
  end if;
  if (select count(*) from public.rate_limit_events
      where user_id = v_uid and action = p_action and created_at > now() - p_window) >= p_limit then
    raise exception 'too many attempts; wait and try again' using errcode = 'P0001';
  end if;
  insert into public.rate_limit_events (user_id, action) values (v_uid, p_action);
end;
$$;

create function public.rate_limit_product_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  case tg_table_name
    when 'requests' then perform public.consume_rate_limit('request_create', 20, interval '1 hour');
    when 'runs' then perform public.consume_rate_limit('run_create', 20, interval '1 hour');
    when 'messages' then perform public.consume_rate_limit('group_message', 120, interval '10 minutes');
    when 'request_messages' then perform public.consume_rate_limit('request_message', 120, interval '10 minutes');
    when 'launch_feedback' then perform public.consume_rate_limit('feedback', 10, interval '1 day');
    when 'safety_reports' then perform public.consume_rate_limit('safety_report', 10, interval '1 day');
    else null;
  end case;
  return new;
end;
$$;

create trigger requests_rate_limit before insert on public.requests for each row execute function public.rate_limit_product_write();
create trigger runs_rate_limit before insert on public.runs for each row execute function public.rate_limit_product_write();
create trigger messages_rate_limit before insert on public.messages for each row execute function public.rate_limit_product_write();
create trigger request_messages_rate_limit before insert on public.request_messages for each row execute function public.rate_limit_product_write();
create trigger launch_feedback_rate_limit before insert on public.launch_feedback for each row execute function public.rate_limit_product_write();
create trigger safety_reports_rate_limit before insert on public.safety_reports for each row execute function public.rate_limit_product_write();

create table public.prohibited_terms (
  term text primary key check (char_length(term) between 2 and 80),
  created_at timestamptz not null default now()
);
insert into public.prohibited_terms (term) values
  ('ammunition'), ('cocaine'), ('fentanyl'), ('firearm'), ('fake id'), ('methamphetamine');

create function public.contains_prohibited_content(p_value text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.prohibited_terms
    where lower(coalesce(p_value, '')) like '%' || lower(term) || '%'
  );
$$;

create function public.guard_prohibited_content()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_text text := concat_ws(' ', to_jsonb(new)->>'title', to_jsonb(new)->>'details',
    to_jsonb(new)->>'note', to_jsonb(new)->>'body');
begin
  if public.contains_prohibited_content(v_text) then
    raise exception 'this item is not allowed on Dart' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger requests_prohibited_content before insert or update of title, details on public.requests
  for each row execute function public.guard_prohibited_content();
create trigger runs_prohibited_content before insert or update of note on public.runs
  for each row execute function public.guard_prohibited_content();
create trigger messages_prohibited_content before insert or update of body on public.messages
  for each row execute function public.guard_prohibited_content();
create trigger request_messages_prohibited_content before insert or update of body on public.request_messages
  for each row execute function public.guard_prohibited_content();
create trigger list_items_prohibited_content before insert or update of body on public.list_items
  for each row execute function public.guard_prohibited_content();

create function public.guard_request_safety()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_requester public.profiles;
  v_helper public.profiles;
  v_has_money boolean;
begin
  select * into v_requester from public.profiles where id = new.requester_id;
  if v_requester.account_status <> 'active' then
    raise exception 'this account cannot create or manage requests' using errcode = '42501';
  end if;
  v_has_money := new.payment_intent_id is not null or new.reward_cents > 0
    or coalesce(new.merchandise_budget_cents, 0) > 0;
  if v_has_money and v_requester.age_band <> '18_or_over' then
    raise exception 'paid requests are available only to eligible adults' using errcode = 'P0001';
  end if;
  if new.helper_id is not null then
    select * into v_helper from public.profiles where id = new.helper_id;
    if v_helper.account_status <> 'active' or public.users_are_blocked(new.requester_id, new.helper_id) then
      raise exception 'these accounts cannot interact' using errcode = 'P0001';
    end if;
    if v_has_money and v_helper.age_band <> '18_or_over' then
      raise exception 'paid helping is available only to eligible adults' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger requests_safety before insert or update on public.requests
  for each row execute function public.guard_request_safety();

create function public.guard_run_safety()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
begin
  select * into v_profile from public.profiles where id = new.runner_id;
  if v_profile.account_status <> 'active' then
    raise exception 'this account cannot create or manage runs' using errcode = '42501';
  end if;
  if new.fee_cents > 0 and v_profile.age_band <> '18_or_over' then
    raise exception 'paid runs are available only to eligible adults' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger runs_safety before insert or update on public.runs
  for each row execute function public.guard_run_safety();

alter table public.user_blocks enable row level security;
alter table public.safety_reports enable row level security;
alter table public.rate_limit_events enable row level security;
alter table public.prohibited_terms enable row level security;

create policy "users manage their own blocks" on public.user_blocks
  for all to authenticated using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());
create policy "users submit their own reports" on public.safety_reports
  for insert to authenticated with check (reporter_id = auth.uid());

revoke all on public.user_blocks, public.safety_reports, public.rate_limit_events, public.prohibited_terms from anon, authenticated;
grant select, insert, delete on public.user_blocks to authenticated;
grant insert (reported_user_id, request_id, group_id, category, details) on public.safety_reports to authenticated;
grant usage, select on sequence public.safety_reports_id_seq to authenticated;

revoke execute on function public.set_my_age_band(public.age_band) from public, anon;
grant execute on function public.set_my_age_band(public.age_band) to authenticated;
revoke execute on function public.accept_safety_rules() from public, anon;
grant execute on function public.accept_safety_rules() to authenticated;
revoke execute on function public.users_are_blocked(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.is_blocked_with(uuid) from public, anon;
grant execute on function public.is_blocked_with(uuid) to authenticated;
revoke execute on function public.consume_rate_limit(text, integer, interval) from public, anon, authenticated;
revoke execute on function public.rate_limit_product_write() from public, anon, authenticated;
revoke execute on function public.contains_prohibited_content(text) from public, anon, authenticated;
revoke execute on function public.guard_prohibited_content() from public, anon, authenticated;
revoke execute on function public.guard_request_safety() from public, anon, authenticated;
revoke execute on function public.guard_run_safety() from public, anon, authenticated;

-- Reduce profile/place discovery to the signed-in account's campus. This also makes the
-- multi-campus default safe before additional schools are enabled.
drop policy "places are visible to signed-in users" on public.places;
create policy "campus places are visible to signed-in users" on public.places
  for select to authenticated using (campus_id = public.my_campus_id());
drop policy "profiles are visible to signed-in users" on public.profiles;
create policy "campus profiles are visible to signed-in users" on public.profiles
  for select to authenticated using (id = auth.uid() or campus_id = public.my_campus_id());

drop policy "audience sees runs" on public.runs;
create policy "audience sees unblocked runs" on public.runs
  for select to authenticated using (
    not public.is_blocked_with(runner_id)
    and (
      runner_id = auth.uid()
      or (group_id is not null and public.is_group_member(group_id))
      or (audience = 'campus' and campus_id = public.my_campus_id())
    )
  );

drop policy "audience sees requests" on public.requests;
create policy "audience sees unblocked requests" on public.requests
  for select to authenticated using (
    not public.is_blocked_with(requester_id)
    and (helper_id is null or not public.is_blocked_with(helper_id))
    and (
      requester_id = auth.uid()
      or helper_id = auth.uid()
      or (run_id is not null and exists (select 1 from public.runs r where r.id = run_id and r.runner_id = auth.uid()))
      or (
        status = 'open' and (
          (group_id is not null and public.is_group_member(group_id))
          or (group_id is null and campus_id = public.my_campus_id())
        )
      )
    )
  );

