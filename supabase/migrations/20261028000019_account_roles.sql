-- Requester and darter are separate roles. Signup picks one (auth metadata "role"), and the
-- other can be added later from Account. The server enforces them: only requesters post
-- requests; only darters take requests or share trips.

alter table public.profiles
  add column is_requester boolean not null default false,
  add column is_darter boolean not null default false;

-- Accounts made before roles existed keep doing both.
update public.profiles set is_requester = true, is_darter = true;

-- Same as 20261024000017, plus the role flags. Metadata without a role (seed data, dashboard
-- invites, older clients) gets both roles.
create or replace function public.handle_new_user()
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
    'Dart member'
  );
  v_role text := new.raw_user_meta_data ->> 'role';
  v_campus_id uuid;
begin
  select c.id into v_campus_id
  from public.campuses c
  where v_domain = any (c.email_domains)
     or exists (select 1 from unnest(c.email_domains) d where v_domain like '%.' || d)
  order by c.created_at
  limit 1;

  if v_campus_id is null then
    select c.id into v_campus_id from public.campuses c order by c.created_at limit 1;
  end if;

  insert into public.profiles (id, display_name, campus_id, is_requester, is_darter)
  values (new.id, left(v_name, 60), v_campus_id,
          v_role is distinct from 'darter', v_role is distinct from 'requester');
  return new;
end;
$$;

create function public.profile_has_role(p_user uuid, p_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case p_role when 'requester' then p.is_requester when 'darter' then p.is_darter end
    from public.profiles p
    where p.id = p_user
  ), false);
$$;

revoke execute on function public.profile_has_role(uuid, text) from public, anon, authenticated;

-- Runs as a trigger so it also covers security-definer paths (accept_request, request_from_run).
create function public.enforce_account_roles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'runs' then
    if not public.profile_has_role(new.runner_id, 'darter') then
      raise exception 'Only darter accounts can share trips' using errcode = '42501';
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' and not public.profile_has_role(new.requester_id, 'requester') then
    raise exception 'Only requester accounts can request deliveries' using errcode = '42501';
  end if;
  if new.helper_id is not null
     and (tg_op = 'INSERT' or new.helper_id is distinct from old.helper_id)
     and not public.profile_has_role(new.helper_id, 'darter') then
    raise exception 'Only darter accounts can deliver orders' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_account_roles() from public, anon, authenticated;

create trigger requests_enforce_account_roles
  before insert or update of helper_id on public.requests
  for each row execute function public.enforce_account_roles();

create trigger runs_enforce_account_roles
  before insert on public.runs
  for each row execute function public.enforce_account_roles();

-- Adds the other role to your own account (Account → switch). Darter eligibility checks
-- (Berkeley email, age) will gate this once they exist.
create function public.add_my_role(p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  case p_role
    when 'requester' then update public.profiles set is_requester = true where id = auth.uid();
    when 'darter' then update public.profiles set is_darter = true where id = auth.uid();
    else raise exception 'Unknown role %', p_role using errcode = '22023';
  end case;
end;
$$;

revoke execute on function public.add_my_role(text) from public, anon;
grant execute on function public.add_my_role(text) to authenticated;
