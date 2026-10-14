-- Native iOS push destinations, ActivityKit destinations, and a durable notification outbox.
-- APNs credentials stay server-side in the send-grab-push Edge Function.

create table public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade default auth.uid(),
  token text not null check (char_length(token) between 32 and 512 and token ~ '^[0-9a-f]+$'),
  bundle_id text not null check (char_length(bundle_id) between 3 and 255),
  app_variant text not null check (app_variant in ('full', 'clip')),
  environment text not null check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

create table public.live_activity_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade default auth.uid(),
  request_id uuid not null references public.requests (id) on delete cascade,
  token text not null check (char_length(token) between 32 and 512 and token ~ '^[0-9a-f]+$'),
  bundle_id text not null check (char_length(bundle_id) between 3 and 255),
  app_variant text not null check (app_variant in ('full', 'clip')),
  environment text not null check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now(),
  unique (user_id, request_id, token)
);

create table public.push_events (
  id bigint generated always as identity primary key,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  event_type text not null check (event_type in ('request_status', 'request_message', 'group_message')),
  request_id uuid references public.requests (id) on delete cascade,
  title text not null,
  body text not null,
  status text,
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  last_error text
);

-- A capability URL lets an App Clip follow one request without creating an account. The UUID
-- secret is only exposed to the requester/helper and is validated server-side before any token is
-- accepted. APNs tokens remain unreadable from the public API.
create table public.request_tracking_links (
  request_id uuid primary key references public.requests (id) on delete cascade,
  secret uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table public.clip_push_tokens (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests (id) on delete cascade,
  token text not null check (char_length(token) between 32 and 512 and token ~ '^[0-9a-f]+$'),
  token_kind text not null check (token_kind in ('alert', 'liveactivity')),
  bundle_id text not null check (char_length(bundle_id) between 3 and 255),
  environment text not null check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now(),
  unique (request_id, token, token_kind)
);

create index push_tokens_user_idx on public.push_tokens (user_id);
create index live_activity_tokens_request_idx on public.live_activity_tokens (request_id, user_id);
create index push_events_pending_idx on public.push_events (created_at) where delivered_at is null;
create index clip_push_tokens_request_idx on public.clip_push_tokens (request_id, token_kind);

alter table public.push_tokens enable row level security;
alter table public.live_activity_tokens enable row level security;
alter table public.push_events enable row level security;
alter table public.request_tracking_links enable row level security;
alter table public.clip_push_tokens enable row level security;

create policy "members manage their push tokens" on public.push_tokens
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "participants manage their live activity tokens" on public.live_activity_tokens
  for all to authenticated
  using (
    user_id = auth.uid() and exists (
      select 1 from public.requests r
      where r.id = request_id and auth.uid() in (r.requester_id, r.helper_id)
    )
  )
  with check (
    user_id = auth.uid() and exists (
      select 1 from public.requests r
      where r.id = request_id and auth.uid() in (r.requester_id, r.helper_id)
    )
  );

create policy "participants read request tracking links" on public.request_tracking_links
  for select to authenticated
  using (
    exists (
      select 1 from public.requests r
      where r.id = request_id and auth.uid() in (r.requester_id, r.helper_id)
    )
  );

revoke all on public.push_tokens, public.live_activity_tokens, public.push_events,
  public.request_tracking_links, public.clip_push_tokens from anon, authenticated;
grant select, insert, update, delete on public.push_tokens, public.live_activity_tokens to authenticated;
grant select on public.request_tracking_links to authenticated;

create or replace function public.ensure_request_tracking_link()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.request_tracking_links (request_id) values (new.id)
  on conflict (request_id) do nothing;
  return new;
end;
$$;

insert into public.request_tracking_links (request_id)
select id from public.requests
on conflict (request_id) do nothing;

create trigger ensure_request_tracking_link
after insert on public.requests
for each row execute function public.ensure_request_tracking_link();

create or replace function public.queue_request_status_push()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  recipient uuid;
  actor uuid := auth.uid();
  headline text;
begin
  if old.status is not distinct from new.status then return new; end if;
  headline := case new.status
    when 'accepted' then 'Your request was accepted'
    when 'picking_up' then 'Your helper is picking it up'
    when 'on_the_way' then 'Your Grab is on the way'
    when 'delivered' then 'Your Grab was delivered'
    when 'completed' then 'Grab complete'
    when 'cancelled' then 'Request cancelled'
    when 'expired' then 'Request expired'
    else 'Grab status updated'
  end;

  for recipient in
    select distinct value from unnest(array[new.requester_id, new.helper_id]) value
    where value is not null and (actor is null or value <> actor)
  loop
    insert into public.push_events (recipient_id, event_type, request_id, title, body, status)
    values (recipient, 'request_status', new.id, headline, new.title, new.status);
  end loop;
  return new;
end;
$$;

create or replace function public.queue_request_message_push()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  req public.requests;
  recipient uuid;
begin
  select * into req from public.requests where id = new.request_id;
  for recipient in
    select distinct value from unnest(array[req.requester_id, req.helper_id]) value
    where value is not null and value is distinct from new.sender_id
  loop
    insert into public.push_events (recipient_id, event_type, request_id, title, body, status)
    values (recipient, 'request_message', req.id, req.title, new.body, req.status);
  end loop;
  return new;
end;
$$;

create or replace function public.queue_group_message_push()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  recipient uuid;
  group_name text;
begin
  select name into group_name from public.groups where id = new.group_id;
  for recipient in
    select user_id from public.group_members
    where group_id = new.group_id and user_id is distinct from new.sender_id
  loop
    insert into public.push_events (recipient_id, event_type, title, body)
    values (recipient, 'group_message', coalesce(group_name, 'Your Grab group'), new.body);
  end loop;
  return new;
end;
$$;

revoke all on function public.queue_request_status_push() from public;
revoke all on function public.queue_request_message_push() from public;
revoke all on function public.queue_group_message_push() from public;
revoke all on function public.ensure_request_tracking_link() from public;

create trigger queue_request_status_push
after update of status on public.requests
for each row execute function public.queue_request_status_push();

create trigger queue_request_message_push
after insert on public.request_messages
for each row execute function public.queue_request_message_push();

create trigger queue_group_message_push
after insert on public.messages
for each row execute function public.queue_group_message_push();
