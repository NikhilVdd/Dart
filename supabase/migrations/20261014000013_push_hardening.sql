-- Hardening from the pressure test.
--
-- 1. A push problem (pg_net, Vault, outbox) must never block the action that caused it: posting a
--    request, accepting, chatting or announcing a run now succeeds and only logs a warning.
-- 2. claim_push_batch collapsed duplicate tags with a correlated scan that slowed to minutes on a
--    large backlog; it is now a single windowed pass over the last hour, and retry_push retires
--    anything older so the unsent set stays small.
-- 3. request_messages kept the hosted default table grants (including anon and TRUNCATE). RLS
--    already blocked access; the grants now match what the app uses.
-- 4. pg_net belongs in the extensions schema (Supabase security advisor).

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
  if to_regnamespace('net') is null or to_regclass('vault.decrypted_secrets') is null then
    return;
  end if;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'grab_push_url'$q$ into v_url;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'grab_push_secret'$q$ into v_secret;
  if v_url is null or v_secret is null then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 10000)'
    using v_url, '{}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-grab-push-secret', v_secret);
exception when others then
  -- Queued rows stay unsent; the minute-ly retry picks them up once the sender is reachable.
  raise warning 'push dispatch failed: %', sqlerrm;
end;
$$;

create or replace function public.dispatch_push_after_enqueue()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.dispatch_push();
  return null;
exception when others then
  raise warning 'push dispatch failed: %', sqlerrm;
  return null;
end;
$$;

create or replace function public.enqueue_push(
  p_user_id uuid,
  p_category text,
  p_title text,
  p_body text,
  p_tag text default null,
  p_url text default './'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enabled boolean;
begin
  if p_user_id is null or p_user_id is not distinct from auth.uid() then
    return;
  end if;
  if not exists (select 1 from public.push_subscriptions where user_id = p_user_id) then
    return;
  end if;

  select (to_jsonb(p) ->> p_category)::boolean into v_enabled
  from public.notification_prefs p where p.user_id = p_user_id;
  if not coalesce(v_enabled, p_category in ('request_updates', 'chat', 'run_announcements')) then
    return;
  end if;

  insert into public.notification_outbox (user_id, category, title, body, tag, url, badge)
  values (
    p_user_id, p_category, left(p_title, 120), left(p_body, 400), p_tag, p_url,
    (select count(*)::integer from public.requests r
     where (r.requester_id = p_user_id or r.helper_id = p_user_id)
       and r.status in ('open', 'accepted', 'picking_up', 'on_the_way', 'delivered'))
  );
exception when others then
  raise warning 'push enqueue failed for %: %', p_user_id, sqlerrm;
end;
$$;

create or replace function public.claim_push_batch(p_limit integer default 100)
returns table (id bigint, user_id uuid, category text, title text, body text, tag text, url text, badge integer)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update public.notification_outbox o
  set sent_at = now(), last_error = 'superseded'
  from (
    select c.id, row_number() over (partition by c.user_id, c.tag order by c.id desc) as newest
    from public.notification_outbox c
    where c.sent_at is null and c.tag is not null and c.created_at > now() - interval '1 hour'
  ) ranked
  where o.id = ranked.id and ranked.newest > 1;

  return query
  with claimed as (
    update public.notification_outbox o
    set claimed_at = now(), attempts = o.attempts + 1
    where o.id in (
      select c.id from public.notification_outbox c
      where c.sent_at is null and c.attempts < 5
        and c.created_at > now() - interval '1 hour'
        and (c.claimed_at is null or c.claimed_at < now() - interval '1 minute')
      order by c.id
      limit greatest(1, least(p_limit, 500))
      for update skip locked
    )
    returning o.id, o.user_id, o.category, o.title, o.body, o.tag, o.url, o.badge
  )
  select * from claimed order by claimed.id;
end;
$$;

create or replace function public.retry_push()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.notification_outbox where created_at < now() - interval '7 days';
  -- Too old to be useful, or out of attempts: retire so the unsent set stays small.
  update public.notification_outbox
  set sent_at = now(), last_error = coalesce(last_error, '') || ' [gave up]'
  where sent_at is null and (created_at < now() - interval '1 hour' or attempts >= 5);
  if exists (
    select 1 from public.notification_outbox
    where sent_at is null and (claimed_at is null or claimed_at < now() - interval '1 minute')
  ) then
    perform public.dispatch_push();
  end if;
end;
$$;

revoke execute on function public.enqueue_push(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.dispatch_push() from public, anon, authenticated;
revoke execute on function public.dispatch_push_after_enqueue() from public, anon, authenticated;
revoke execute on function public.claim_push_batch(integer) from public, anon, authenticated;
revoke execute on function public.retry_push() from public, anon, authenticated;
grant execute on function public.claim_push_batch(integer) to service_role;

revoke all on public.request_messages from anon, authenticated;
grant select on public.request_messages to authenticated;
grant insert (request_id, body) on public.request_messages to authenticated;

do $$
begin
  if exists (
    select 1 from pg_extension e join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'pg_net' and n.nspname = 'public'
  ) then
    begin
      drop extension pg_net;
      create extension pg_net schema extensions;
    exception when others then
      -- Something else depends on pg_net (e.g. a Database Webhook); leave it where it is.
      raise notice 'pg_net left in public: %', sqlerrm;
    end;
  end if;
end;
$$;
