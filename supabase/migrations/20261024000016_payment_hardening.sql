-- Payment hardening after a pressure test of migration 15.
--
--   hold window  Online card holds last 7 days (Stripe's capture_before on the charge says exactly).
--                Paid requests must now be due within 4 days of the hold and 2 days before it lapses,
--                so delivery plus the 24 h confirmation window still captures in time. Delivered paid
--                requests auto-complete early when their hold is about to lapse, and a runner can't
--                start shopping on a hold that is no longer valid.
--   reopen       A request handed back to 'open' forgets the previous runner's receipt total and payout
--                destination.
--   stuck money  A capture whose transfer keeps failing (the money is already captured) retries hourly
--                after the 20 fast attempts instead of stopping.

alter table public.payment_holds add column capture_before timestamptz;

alter table public.payment_jobs add column retry_after timestamptz;

-- Latest a paid request may be due for this hold.
create function public.paid_due_limit(p_hold public.payment_holds)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select least(p_hold.created_at + interval '4 days',
               coalesce(p_hold.capture_before - interval '2 days', 'infinity'::timestamptz));
$$;

create or replace function public.attach_payment_hold()
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
  if new.deliver_by > public.paid_due_limit(v_hold) then
    raise exception 'paid requests must be delivered within 4 days' using errcode = 'P0001';
  end if;

  new.merchandise_budget_cents := v_hold.budget_cents;
  new.reward_cents := v_hold.fee_cents;
  new.payment_status := 'authorized';
  return new;
end;
$$;

create or replace function public.guard_paid_request()
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
  if new.deliver_by is distinct from old.deliver_by and new.deliver_by > public.paid_due_limit(v_hold) then
    raise exception 'paid requests must be delivered within 4 days' using errcode = 'P0001';
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
  elsif new.status = 'open' then
    -- Handed back (runner released it or deleted their account): the next runner starts fresh.
    new.item_cost_cents := null;
    update public.payment_holds set destination_account = null
    where payment_intent_id = new.payment_intent_id;
  elsif new.status = 'picking_up' and v_hold.status <> 'authorized' then
    raise exception 'this request’s payment is no longer valid, so don’t buy anything yet' using errcode = 'P0001';
  elsif new.status = 'delivered' and new.item_cost_cents is null then
    raise exception 'enter the receipt total before marking it delivered' using errcode = 'P0001';
  elsif new.status = 'completed' and new.item_cost_cents is null then
    raise exception 'waiting for your helper to enter the receipt total' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Job queue: hourly retries for captured money that hasn't reached the runner
-- ---------------------------------------------------------------------------

create function public.payment_job_due(p_job public.payment_jobs)
returns boolean
language sql
stable
set search_path = ''
as $$
  select p_job.done_at is null
    and (p_job.retry_after is null or p_job.retry_after <= now())
    and (p_job.claimed_at is null or p_job.claimed_at < now() - interval '2 minutes')
    and (p_job.attempts < 20 or (p_job.kind = 'capture' and exists (
      select 1 from public.payment_holds h
      where h.payment_intent_id = p_job.payment_intent_id and h.status = 'captured')));
$$;

create or replace function public.claim_payment_jobs(p_limit integer default 20)
returns setof public.payment_jobs
language sql
security definer
set search_path = ''
as $$
  update public.payment_jobs j
  set claimed_at = now(), attempts = j.attempts + 1
  where j.id in (
    select q.id from public.payment_jobs q
    where public.payment_job_due(q)
    order by q.id
    limit p_limit
    for update skip locked
  )
  returning j.*;
$$;

create or replace function public.finish_payment_job(p_id bigint, p_error text default null)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.payment_jobs
  set done_at = case when p_error is null then now() end,
      claimed_at = case when p_error is null then claimed_at end,
      retry_after = case when p_error is not null and attempts >= 20 then now() + interval '1 hour' end,
      last_error = p_error
  where id = p_id;
$$;

create or replace function public.retry_payment_jobs()
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

  -- Delivered but unconfirmed, with the hold about to lapse: complete now so the runner is paid.
  update public.requests q
  set status = 'completed', completed_at = now()
  from public.payment_holds h
  where h.request_id = q.id and q.status = 'delivered' and h.status = 'authorized'
    and h.capture_before < now() + interval '12 hours';

  if exists (select 1 from public.payment_jobs j where public.payment_job_due(j)) then
    perform public.dispatch_payments();
  end if;
end;
$$;

revoke execute on function public.paid_due_limit(public.payment_holds) from public, anon, authenticated;
revoke execute on function public.payment_job_due(public.payment_jobs) from public, anon, authenticated;
