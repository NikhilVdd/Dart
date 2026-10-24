-- Replace remaining runtime Grab-era identifiers without rewriting applied migrations.

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

  insert into public.profiles (id, display_name, campus_id)
  values (new.id, left(v_name, 60), v_campus_id);
  return new;
end;
$$;

create or replace function public.dispatch_push()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  if to_regnamespace('net') is null or to_regclass('vault.decrypted_secrets') is null then return; end if;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'dart_push_url'$q$ into v_url;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'dart_push_secret'$q$ into v_secret;
  if v_url is null or v_secret is null then return; end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 10000)'
    using v_url, '{}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-dart-push-secret', v_secret);
exception when others then
  raise warning 'push dispatch failed: %', sqlerrm;
end;
$$;

revoke execute on function public.dispatch_push() from public, anon, authenticated;

