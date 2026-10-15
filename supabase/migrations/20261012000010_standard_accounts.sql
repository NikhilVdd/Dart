-- Standard accounts use any email address. Domain matches still select a specific campus when one
-- exists; otherwise the first configured campus is used so requests, runs, places, and groups work.

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
    'Grab member'
  );
  v_campus_id uuid;
begin
  select c.id into v_campus_id
  from public.campuses c
  where v_domain = any (c.email_domains)
     or exists (select 1 from unnest(c.email_domains) d where v_domain like '%.' || d)
  order by c.created_at
  limit 1;

  if v_campus_id is null then
    select c.id into v_campus_id
    from public.campuses c
    order by c.created_at
    limit 1;
  end if;

  insert into public.profiles (id, display_name, campus_id)
  values (new.id, left(v_name, 60), v_campus_id);
  return new;
end;
$$;

-- Repair accounts created before this migration so they can use campus-scoped backend features.
update public.profiles p
set campus_id = (
  select c.id from public.campuses c order by c.created_at limit 1
)
where p.campus_id is null;
