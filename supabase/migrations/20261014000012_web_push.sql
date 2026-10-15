-- Web Push for the installed PWA (no Apple Developer account: browsers deliver through their own
-- push services, authenticated with our VAPID key).
--
-- Triggers decide who hears about what and write rows to notification_outbox. Each insert pokes the
-- send-push Edge Function through pg_net; the function claims unsent rows, encrypts them for every
-- device the person has subscribed, and records the result. A minute-ly cron job retries leftovers.
--
-- Request-status pushes share one tag per request, so each step replaces the previous notification
-- and reads like a progress bar moving: ▰▰▰▱▱ On the way.

-- ---------------------------------------------------------------------------
-- Devices and preferences
-- ---------------------------------------------------------------------------

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  -- Only real browser push services, so the sender can never be pointed at arbitrary URLs.
  endpoint text not null unique check (
    char_length(endpoint) <= 1000 and
    endpoint ~ '^https://([a-z0-9-]+\.)*(push\.apple\.com|fcm\.googleapis\.com|push\.services\.mozilla\.com|notify\.windows\.com)(:443)?/'
  ),
  p256dh text not null check (char_length(p256dh) between 40 and 200),
  auth text not null check (char_length(auth) between 8 and 100),
  user_agent text check (char_length(user_agent) <= 300),
  created_at timestamptz not null default now(),
  last_success_at timestamptz,
  failure_count integer not null default 0
);

create index push_subscriptions_user_idx on public.push_subscriptions (user_id);

create table public.notification_prefs (
  user_id uuid primary key default auth.uid() references public.profiles (id) on delete cascade,
  request_updates boolean not null default true,    -- your requests, deliveries and runs moving along
  chat boolean not null default true,               -- private requester ↔ helper chat
  run_announcements boolean not null default true,  -- runs announced to your friend and building groups
  campus_runs boolean not null default false,       -- runs announced to your whole campus
  nearby_requests boolean not null default false,   -- new requests you could help with
  group_chat boolean not null default false,        -- group conversations
  updated_at timestamptz not null default now()
);

create trigger notification_prefs_updated_at before update on public.notification_prefs
  for each row execute function public.set_updated_at();

create table public.notification_outbox (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  category text not null,
  title text not null,
  body text not null,
  tag text,
  url text not null default './',
  badge integer,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  attempts integer not null default 0,
  sent_at timestamptz,
  last_error text
);

create index notification_outbox_unsent_idx on public.notification_outbox (id) where sent_at is null;
create index notification_outbox_user_tag_idx on public.notification_outbox (user_id, tag) where sent_at is null;

alter table public.push_subscriptions enable row level security;
alter table public.notification_prefs enable row level security;
alter table public.notification_outbox enable row level security;

-- Devices are managed through the RPCs below; the outbox is server-only.
revoke all on public.push_subscriptions from anon, authenticated;
revoke all on public.notification_outbox from anon, authenticated;

create policy "members read their notification prefs" on public.notification_prefs
  for select to authenticated using (user_id = auth.uid());
create policy "members create their notification prefs" on public.notification_prefs
  for insert to authenticated with check (user_id = auth.uid());
create policy "members update their notification prefs" on public.notification_prefs
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.notification_prefs from anon, authenticated;
grant select on public.notification_prefs to authenticated;
grant insert (request_updates, chat, run_announcements, campus_runs, nearby_requests, group_chat)
  on public.notification_prefs to authenticated;
grant update (request_updates, chat, run_announcements, campus_runs, nearby_requests, group_chat)
  on public.notification_prefs to authenticated;

-- Register this browser for the signed-in user. A device that changes hands (sign out, sign in as
-- someone else) moves to the new account.
create function public.save_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_user_agent text default null
)
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

  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
  values (v_uid, p_endpoint, p_p256dh, p_auth, left(p_user_agent, 300))
  on conflict (endpoint) do update
    set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
        user_agent = excluded.user_agent, failure_count = 0;

  -- Ten devices is plenty; drop the oldest beyond that.
  delete from public.push_subscriptions
  where id in (
    select id from public.push_subscriptions where user_id = v_uid
    order by created_at desc offset 10
  );
end;
$$;

create function public.delete_push_subscription(p_endpoint text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Enqueue and dispatch
-- ---------------------------------------------------------------------------

-- Queue one notification for one person, respecting their preferences. The person who caused the
-- event is never notified about it, and people without a subscribed device are skipped.
create function public.enqueue_push(
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
end;
$$;

-- Ask the send-push Edge Function to drain the outbox. Needs pg_net plus two Vault secrets
-- (grab_push_url, grab_push_secret); without them (tests, local) it quietly does nothing.
create function public.dispatch_push()
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
end;
$$;

create function public.dispatch_push_after_enqueue()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.dispatch_push();
  return null;
end;
$$;

create trigger notification_outbox_dispatch after insert on public.notification_outbox
  for each statement execute function public.dispatch_push_after_enqueue();

-- Called by the Edge Function (service role). Older unsent updates that share a tag are superseded
-- by the newest one, so a burst of status changes sends only the latest step.
create function public.claim_push_batch(p_limit integer default 100)
returns table (id bigint, user_id uuid, category text, title text, body text, tag text, url text, badge integer)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update public.notification_outbox o
  set sent_at = now(), last_error = 'superseded'
  where o.sent_at is null and o.tag is not null
    and exists (
      select 1 from public.notification_outbox n
      where n.user_id = o.user_id and n.tag = o.tag and n.id > o.id and n.sent_at is null
    );

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

-- Called by the Edge Function when a device keeps failing; after 20 in a row it is forgotten.
create function public.note_push_failure(p_subscription_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.push_subscriptions set failure_count = failure_count + 1 where id = p_subscription_id;
  delete from public.push_subscriptions where id = p_subscription_id and failure_count >= 20;
end;
$$;

-- Cron safety net: retry anything still waiting, and keep the outbox small.
create function public.retry_push()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.notification_outbox where created_at < now() - interval '7 days';
  if exists (
    select 1 from public.notification_outbox
    where sent_at is null and attempts < 5 and created_at > now() - interval '1 hour'
      and (claimed_at is null or claimed_at < now() - interval '1 minute')
  ) then
    perform public.dispatch_push();
  end if;
end;
$$;

-- A test notification to the caller's own devices, from Profile.
create function public.send_test_push()
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
  if not exists (select 1 from public.push_subscriptions where user_id = v_uid) then
    raise exception 'turn on notifications on this device first' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.notification_outbox
    where user_id = v_uid and category = 'test' and created_at > now() - interval '20 seconds'
  ) then
    raise exception 'a test notification was just sent' using errcode = 'P0001';
  end if;
  insert into public.notification_outbox (user_id, category, title, body, tag, url)
  values (v_uid, 'test', 'Grab notifications are on', '▰▰▰▱▱  This is how your order updates will look.', 'test', './?tab=profile');
end;
$$;

-- ---------------------------------------------------------------------------
-- What triggers a notification
-- ---------------------------------------------------------------------------

create function public.push_meter(p_status public.request_status)
returns text
language sql
immutable
set search_path = ''
as $$
  select repeat('▰', n) || repeat('▱', 5 - n)
  from (select case p_status
    when 'accepted' then 1 when 'picking_up' then 2 when 'on_the_way' then 3
    when 'delivered' then 4 when 'completed' then 5 else 0 end as n) s
$$;

create function public.push_first_name(p_user_id uuid, p_fallback text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select nullif(split_part(btrim(display_name), ' ', 1), '') from public.profiles where id = p_user_id),
    p_fallback
  )
$$;

-- Request lifecycle: the requester follows every step; the helper hears about cancellations and
-- confirmations. Everyone else is excluded by the actor check in enqueue_push.
create function public.push_request_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item text := left(new.title, 60);
  v_tag text := 'request-' || new.id;
  v_url text := './?request=' || new.id;
  v_helper text := public.push_first_name(coalesce(new.helper_id, old.helper_id), 'Your helper');
  v_requester text := public.push_first_name(new.requester_id, 'The requester');
  v_meter text := public.push_meter(new.status);
begin
  if new.status is not distinct from old.status then
    return null;
  end if;

  case new.status
    when 'accepted' then
      perform public.enqueue_push(new.requester_id, 'request_updates', v_item || ' — Accepted',
        v_meter || '  ' || v_helper || ' is on it and will head out soon', v_tag, v_url);
    when 'picking_up' then
      perform public.enqueue_push(new.requester_id, 'request_updates', v_item || ' — Picking up',
        v_meter || '  ' || v_helper || ' is picking it up at ' || new.pickup_label, v_tag, v_url);
    when 'on_the_way' then
      perform public.enqueue_push(new.requester_id, 'request_updates', v_item || ' — On the way',
        v_meter || '  ' || v_helper || ' is on the way to ' || new.destination_label, v_tag, v_url);
    when 'delivered' then
      perform public.enqueue_push(new.requester_id, 'request_updates', v_item || ' — Delivered',
        v_meter || '  ' || v_helper || ' dropped it at ' || new.destination_label || '. Tap to confirm you got it.', v_tag, v_url);
    when 'completed' then
      -- Requester-confirmed: only the helper hears. Auto-completed by housekeeping: both do.
      perform public.enqueue_push(new.helper_id, 'request_updates', v_item || ' — Confirmed',
        v_requester || ' confirmed they got it. Thanks for helping!', v_tag, v_url);
      perform public.enqueue_push(new.requester_id, 'request_updates', v_item || ' — Done',
        v_meter || '  Delivery complete', v_tag, v_url);
    when 'cancelled' then
      perform public.enqueue_push(old.helper_id, 'request_updates', v_item || ' — Cancelled',
        v_requester || ' cancelled this request. No need to pick it up.', v_tag, v_url);
    when 'open' then
      if old.helper_id is not null then
        perform public.enqueue_push(new.requester_id, 'request_updates', v_item || ' — Back to open',
          v_helper || ' can’t make it, so it’s open for someone else now.', v_tag, v_url);
      end if;
    when 'expired' then
      perform public.enqueue_push(new.requester_id, 'request_updates', v_item || ' — Expired',
        'Nobody could make it in time. Ask again whenever you like.', v_tag, v_url);
    else
      null;
  end case;
  return null;
end;
$$;

create trigger requests_push_status after update of status on public.requests
  for each row execute function public.push_request_status();

-- New request: opt-in heads-up for people who could help (its group, or its campus).
create function public.push_new_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_body text := public.push_first_name(new.requester_id, 'Someone') || ' needs ' || left(new.title, 60)
    || ' · ' || new.pickup_label || ' → ' || new.destination_label;
begin
  if new.status <> 'open' then
    return null;
  end if;
  for v_user in
    select m.user_id from public.group_members m where new.group_id is not null and m.group_id = new.group_id
    union
    select p.id from public.profiles p where new.group_id is null and p.campus_id = new.campus_id
  loop
    perform public.enqueue_push(v_user, 'nearby_requests', 'New request you could help with',
      v_body, 'request-' || new.id, './?request=' || new.id);
  end loop;
  return null;
end;
$$;

create trigger requests_push_new after insert on public.requests
  for each row execute function public.push_new_request();

-- Store run announced: the group it was announced to, or (opt-in) the whole campus.
create function public.push_new_run()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_minutes integer := greatest(1, ceil(extract(epoch from new.closes_at - now()) / 60)::integer);
  v_window text := case when v_minutes < 90 then v_minutes || ' min' else round(v_minutes / 60.0) || ' hr' end;
  v_title text := public.push_first_name(new.runner_id, 'Someone') || ' is heading to ' || new.store_label;
  v_body text := 'Back to ' || new.destination_label || ' · taking requests for the next ' || v_window
    || '. Tap to add something.';
begin
  if new.status <> 'open' then
    return null;
  end if;
  for v_user in
    select m.user_id from public.group_members m where new.group_id is not null and m.group_id = new.group_id
    union
    select p.id from public.profiles p where new.audience = 'campus' and p.campus_id = new.campus_id
  loop
    perform public.enqueue_push(v_user,
      case when new.audience = 'campus' then 'campus_runs' else 'run_announcements' end,
      v_title, v_body, 'run-' || new.id, './?run=' || new.id);
  end loop;
  return null;
end;
$$;

create trigger runs_push_new after insert on public.runs
  for each row execute function public.push_new_run();

-- Private request chat: the other participant.
create function public.push_request_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.requests;
begin
  select * into v_request from public.requests where id = new.request_id;
  perform public.enqueue_push(
    case when new.sender_id = v_request.requester_id then v_request.helper_id else v_request.requester_id end,
    'chat',
    public.push_first_name(new.sender_id, 'Grab') || ' · ' || left(v_request.title, 60),
    left(new.body, 200),
    'chat-' || new.request_id,
    './?request=' || new.request_id || '&chat=1'
  );
  return null;
end;
$$;

create trigger request_messages_push after insert on public.request_messages
  for each row execute function public.push_request_message();

-- Group chat: opt-in, everyone in the group but the sender.
create function public.push_group_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_group text := (select name from public.groups where id = new.group_id);
  v_body text := public.push_first_name(new.sender_id, 'Someone') || ': ' || left(new.body, 180);
begin
  for v_user in select user_id from public.group_members where group_id = new.group_id loop
    if v_user is distinct from new.sender_id then
      perform public.enqueue_push(v_user, 'group_chat', coalesce(v_group, 'Grab group'), v_body,
        'group-' || new.group_id, './?tab=groups&group=' || new.group_id);
    end if;
  end loop;
  return null;
end;
$$;

create trigger messages_push after insert on public.messages
  for each row execute function public.push_group_message();

-- Asking a runner for something tells the runner (unchanged otherwise from migration 3).
create or replace function public.request_from_run(
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

  perform public.enqueue_push(v_run.runner_id, 'request_updates',
    public.push_first_name(v_uid, 'Someone') || ' added to your ' || v_run.store_label || ' run',
    left(v_request.title, 120) || '. Tap to accept it.',
    'request-' || v_request.id, './?request=' || v_request.id);
  return v_request;
end;
$$;

-- ---------------------------------------------------------------------------
-- Privileges and scheduling
-- ---------------------------------------------------------------------------

revoke execute on function public.save_push_subscription(text, text, text, text) from public, anon;
revoke execute on function public.delete_push_subscription(text) from public, anon;
revoke execute on function public.send_test_push() from public, anon;
grant execute on function public.save_push_subscription(text, text, text, text) to authenticated;
grant execute on function public.delete_push_subscription(text) to authenticated;
grant execute on function public.send_test_push() to authenticated;

revoke execute on function public.enqueue_push(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.dispatch_push() from public, anon, authenticated;
revoke execute on function public.dispatch_push_after_enqueue() from public, anon, authenticated;
revoke execute on function public.claim_push_batch(integer) from public, anon, authenticated;
revoke execute on function public.retry_push() from public, anon, authenticated;
revoke execute on function public.note_push_failure(uuid) from public, anon, authenticated;
revoke execute on function public.push_meter(public.request_status) from public, anon, authenticated;
revoke execute on function public.push_first_name(uuid, text) from public, anon, authenticated;
revoke execute on function public.push_request_status() from public, anon, authenticated;
revoke execute on function public.push_new_request() from public, anon, authenticated;
revoke execute on function public.push_new_run() from public, anon, authenticated;
revoke execute on function public.push_request_message() from public, anon, authenticated;
revoke execute on function public.push_group_message() from public, anon, authenticated;
grant execute on function public.claim_push_batch(integer) to service_role;
grant execute on function public.note_push_failure(uuid) to service_role;

-- pg_net and pg_cron ship with hosted Supabase; skip where they aren't available (e.g. tests).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('grab-push-retry', '* * * * *', 'select public.retry_push()');
  end if;
end;
$$;
