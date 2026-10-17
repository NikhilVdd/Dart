-- Stripe payments (Connect marketplace, separate charges and transfers).
--
-- The requester pays the item cost plus a flat delivery fee, grossed up to cover Stripe's
-- processing fee; the runner receives item cost + delivery fee. Dart keeps nothing.
--
--   post     payments Edge Function puts a hold on the requester's card (manual capture) and
--            records it in payment_holds; the request is inserted with that payment_intent_id.
--   accept   only runners whose connected account can receive transfers may accept.
--   deliver  the runner enters the receipt total (set_item_cost) before marking delivered.
--   complete a 'capture' job captures the receipt total + fee and transfers it to the runner.
--   cancel / expire / account deletion: a 'cancel' job releases the hold.
--
-- Stripe calls happen in the payments Edge Function; Postgres queues jobs in payment_jobs and
-- wakes it through pg_net (same pattern as push). Payments are off until
-- payment_settings.required is set, so this migration can ship before Stripe keys exist.

create table public.payment_settings (
  id boolean primary key default true check (id),
  required boolean not null default false,
  delivery_fee_cents integer not null default 250 check (delivery_fee_cents >= 0),
  max_budget_cents integer not null default 20000 check (max_budget_cents > 0)
);
insert into public.payment_settings default values;

-- A runner's Stripe connected account. Separate from profiles, which every member can read.
create table public.payout_accounts (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  stripe_account_id text not null unique,
  transfers_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger payout_accounts_updated_at before update on public.payout_accounts
  for each row execute function public.set_updated_at();

-- One card hold per request. Survives the request (and either account) being deleted so the
-- money can still be captured or released.
create table public.payment_holds (
  payment_intent_id text primary key,
  user_id uuid references public.profiles (id) on delete set null,
  request_id uuid unique references public.requests (id) on delete set null,
  budget_cents integer not null check (budget_cents > 0),
  fee_cents integer not null check (fee_cents >= 0),
  authorized_cents integer not null check (authorized_cents > 0),
  status text not null default 'pending'
    check (status in ('pending', 'authorized', 'captured', 'paid_out', 'canceled', 'failed')),
  item_cost_cents integer check (item_cost_cents >= 0),
  charged_cents integer,
  destination_account text,
  transfer_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index payment_holds_unused_idx on public.payment_holds (created_at) where request_id is null;

create trigger payment_holds_updated_at before update on public.payment_holds
  for each row execute function public.set_updated_at();

create table public.payment_jobs (
  id bigint generated always as identity primary key,
  payment_intent_id text not null references public.payment_holds (payment_intent_id) on delete cascade,
  kind text not null check (kind in ('capture', 'cancel')),
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  done_at timestamptz,
  unique (payment_intent_id, kind)
);

create index payment_jobs_pending_idx on public.payment_jobs (id) where done_at is null;

alter table public.requests
  add column payment_intent_id text unique,
  add column payment_status text not null default 'none'
    check (payment_status in ('none', 'authorized', 'captured', 'paid_out', 'canceled', 'failed')),
  add column item_cost_cents integer check (item_cost_cents >= 0);

-- ---------------------------------------------------------------------------
-- Wake the payments Edge Function (needs pg_net and two Vault secrets:
-- dart_payments_url and dart_payments_secret). Never blocks the caller.
-- ---------------------------------------------------------------------------

create function public.dispatch_payments()
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
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'dart_payments_url'$q$ into v_url;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'dart_payments_secret'$q$ into v_secret;
  if v_url is null or v_secret is null then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 20000)'
    using v_url, '{"action":"settle"}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-dart-payments-secret', v_secret);
exception when others then
  -- Jobs stay pending; retry_payment_jobs picks them up.
  raise warning 'payments dispatch failed: %', sqlerrm;
end;
$$;

create function public.queue_payment_job(p_payment_intent_id text, p_kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.payment_jobs (payment_intent_id, kind)
  values (p_payment_intent_id, p_kind)
  on conflict (payment_intent_id, kind) do nothing;
  perform public.dispatch_payments();
end;
$$;

-- ---------------------------------------------------------------------------
-- Request triggers
-- ---------------------------------------------------------------------------

-- Attach a card hold to a new request. Amounts come from the hold, never from the client.
create function public.attach_payment_hold()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hold public.payment_holds;
begin
  new.payment_status := 'none';
  new.item_cost_cents := null;
  if new.payment_intent_id is null then
    if auth.uid() is not null and (select required from public.payment_settings) then
      raise exception 'add a payment method to post this request' using errcode = 'P0001';
    end if;
    return new;
  end if;

  select * into v_hold from public.payment_holds
  where payment_intent_id = new.payment_intent_id
  for update;
  if not found or v_hold.user_id is distinct from new.requester_id
     or v_hold.status <> 'authorized' or v_hold.request_id is not null then
    raise exception 'payment not found or already used' using errcode = 'P0001';
  end if;
  if new.deliver_by > v_hold.created_at + interval '6 days' then
    raise exception 'paid requests must be delivered within 6 days' using errcode = 'P0001';
  end if;

  new.merchandise_budget_cents := v_hold.budget_cents;
  new.reward_cents := v_hold.fee_cents;
  new.payment_status := 'authorized';
  return new;
end;
$$;

create trigger requests_attach_payment before insert on public.requests
  for each row execute function public.attach_payment_hold();

create function public.link_payment_hold()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.payment_holds set request_id = new.id where payment_intent_id = new.payment_intent_id;
  return null;
end;
$$;

create trigger requests_link_payment after insert on public.requests
  for each row when (new.payment_intent_id is not null)
  execute function public.link_payment_hold();

-- Keep paid requests consistent with their hold, and gate accept/deliver/complete on payment.
create function public.guard_paid_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hold public.payment_holds;
  v_payout public.payout_accounts;
begin
  if new.payment_intent_id is distinct from old.payment_intent_id then
    raise exception 'payment cannot be changed' using errcode = '42501';
  end if;
  if new.reward_cents is distinct from old.reward_cents
     or new.merchandise_budget_cents is distinct from old.merchandise_budget_cents then
    raise exception 'the amount on a paid request cannot be changed' using errcode = 'P0001';
  end if;

  select * into v_hold from public.payment_holds where payment_intent_id = new.payment_intent_id;
  if new.deliver_by is distinct from old.deliver_by and new.deliver_by > v_hold.created_at + interval '6 days' then
    raise exception 'paid requests must be delivered within 6 days' using errcode = 'P0001';
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'accepted' and old.status = 'open' then
    if v_hold.status <> 'authorized' then
      raise exception 'this request’s payment is no longer valid' using errcode = 'P0001';
    end if;
    select * into v_payout from public.payout_accounts where user_id = new.helper_id;
    if not found or not v_payout.transfers_active then
      raise exception 'set up payouts in your profile before accepting paid requests' using errcode = 'P0001';
    end if;
    update public.payment_holds set destination_account = v_payout.stripe_account_id
    where payment_intent_id = new.payment_intent_id;
  elsif new.status = 'delivered' and new.item_cost_cents is null then
    raise exception 'enter the receipt total before marking it delivered' using errcode = 'P0001';
  elsif new.status = 'completed' and new.item_cost_cents is null then
    raise exception 'waiting for your helper to enter the receipt total' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger requests_guard_payment before update on public.requests
  for each row when (old.payment_intent_id is not null)
  execute function public.guard_paid_request();

create function public.queue_request_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'completed' then
    update public.payment_holds set item_cost_cents = new.item_cost_cents
    where payment_intent_id = new.payment_intent_id;
    perform public.queue_payment_job(new.payment_intent_id, 'capture');
  elsif new.status in ('cancelled', 'expired') then
    perform public.queue_payment_job(new.payment_intent_id, 'cancel');
  end if;
  return null;
exception when others then
  raise warning 'payment job not queued: %', sqlerrm;
  return null;
end;
$$;

create trigger requests_queue_payment after update of status on public.requests
  for each row when (new.payment_intent_id is not null and new.status is distinct from old.status)
  execute function public.queue_request_payment();

-- A paid request deleted mid-flight (the requester deleted their account) releases its hold.
create function public.release_deleted_request_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status not in ('completed', 'cancelled', 'expired') then
    perform public.queue_payment_job(old.payment_intent_id, 'cancel');
  end if;
  return old;
end;
$$;

create trigger requests_release_payment before delete on public.requests
  for each row when (old.payment_intent_id is not null)
  execute function public.release_deleted_request_payment();

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- The runner records what the items actually cost (at most the requester's budget).
create function public.set_item_cost(p_request_id uuid, p_item_cents integer)
returns public.requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.requests;
begin
  select * into v_request from public.requests where id = p_request_id for update;
  if not found or v_request.helper_id is distinct from auth.uid() then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if v_request.payment_intent_id is null then
    raise exception 'this request has no payment' using errcode = 'P0001';
  end if;
  if v_request.status not in ('accepted', 'picking_up', 'on_the_way') then
    raise exception 'the receipt total can only be set before delivery' using errcode = 'P0001';
  end if;
  if p_item_cents is null or p_item_cents < 0 or p_item_cents > v_request.merchandise_budget_cents then
    raise exception 'the receipt total must be between $0 and the $% budget',
      to_char(v_request.merchandise_budget_cents / 100.0, 'FM999990.00') using errcode = 'P0001';
  end if;

  update public.requests set item_cost_cents = p_item_cents where id = p_request_id
  returning * into v_request;
  return v_request;
end;
$$;

-- Asking a run's shopper for something now carries the card hold (otherwise unchanged).
drop function public.request_from_run(uuid, text, text, integer);
create function public.request_from_run(
  p_run_id uuid,
  p_title text,
  p_details text default '',
  p_merchandise_budget_cents integer default null,
  p_payment_intent_id text default null
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
    deliver_by, reward_cents, merchandise_budget_cents, payment_intent_id
  )
  values (
    v_uid, v_run.campus_id, v_run.group_id, btrim(p_title), coalesce(p_details, ''),
    v_run.store_place_id, v_run.store_label, v_run.destination_place_id, v_run.destination_label,
    v_run.closes_at + interval '1 hour', v_run.fee_cents, p_merchandise_budget_cents, p_payment_intent_id
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
-- Job queue for the Edge Function, and the minute-ly sweep
-- ---------------------------------------------------------------------------

create function public.claim_payment_jobs(p_limit integer default 20)
returns setof public.payment_jobs
language sql
security definer
set search_path = ''
as $$
  update public.payment_jobs j
  set claimed_at = now(), attempts = j.attempts + 1
  where j.id in (
    select id from public.payment_jobs
    where done_at is null and attempts < 20
      and (claimed_at is null or claimed_at < now() - interval '2 minutes')
    order by id
    limit p_limit
    for update skip locked
  )
  returning j.*;
$$;

create function public.finish_payment_job(p_id bigint, p_error text default null)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.payment_jobs
  set done_at = case when p_error is null then now() end,
      claimed_at = case when p_error is null then claimed_at end,
      last_error = p_error
  where id = p_id;
$$;

create function public.retry_payment_jobs()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pi text;
begin
  -- Holds placed but never turned into a request (the requester backed out) are released.
  for v_pi in
    select payment_intent_id from public.payment_holds
    where request_id is null and status in ('pending', 'authorized') and created_at < now() - interval '30 minutes'
  loop
    insert into public.payment_jobs (payment_intent_id, kind) values (v_pi, 'cancel')
    on conflict (payment_intent_id, kind) do nothing;
  end loop;

  if exists (
    select 1 from public.payment_jobs
    where done_at is null and attempts < 20
      and (claimed_at is null or claimed_at < now() - interval '2 minutes')
  ) then
    perform public.dispatch_payments();
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Privileges and scheduling
-- ---------------------------------------------------------------------------

alter table public.payment_settings enable row level security;
alter table public.payout_accounts enable row level security;
alter table public.payment_holds enable row level security;
alter table public.payment_jobs enable row level security;

create policy "anyone signed in reads payment settings" on public.payment_settings
  for select to authenticated using (true);
create policy "runners read their own payout account" on public.payout_accounts
  for select to authenticated using (user_id = auth.uid());

revoke all on public.payment_settings, public.payout_accounts, public.payment_holds, public.payment_jobs
  from anon, authenticated;
grant select on public.payment_settings, public.payout_accounts to authenticated;

grant insert (payment_intent_id) on public.requests to authenticated;

revoke execute on function public.dispatch_payments() from public, anon, authenticated;
revoke execute on function public.queue_payment_job(text, text) from public, anon, authenticated;
revoke execute on function public.attach_payment_hold() from public, anon, authenticated;
revoke execute on function public.link_payment_hold() from public, anon, authenticated;
revoke execute on function public.guard_paid_request() from public, anon, authenticated;
revoke execute on function public.queue_request_payment() from public, anon, authenticated;
revoke execute on function public.release_deleted_request_payment() from public, anon, authenticated;
revoke execute on function public.claim_payment_jobs(integer) from public, anon, authenticated;
revoke execute on function public.finish_payment_job(bigint, text) from public, anon, authenticated;
revoke execute on function public.retry_payment_jobs() from public, anon, authenticated;
revoke execute on function public.set_item_cost(uuid, integer) from public, anon;
revoke execute on function public.request_from_run(uuid, text, text, integer, text) from public, anon;
grant execute on function public.claim_payment_jobs(integer) to service_role;
grant execute on function public.finish_payment_job(bigint, text) to service_role;
grant execute on function public.set_item_cost(uuid, integer) to authenticated;
grant execute on function public.request_from_run(uuid, text, text, integer, text) to authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('dart-payments-retry', '* * * * *', 'select public.retry_payment_jobs()');
  end if;
end;
$$;
