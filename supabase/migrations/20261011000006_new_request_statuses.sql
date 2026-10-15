-- New request states. Kept in their own migration: Postgres can't use an enum value in the same
-- transaction that adds it.
--   delivered – the helper says it was handed over; the requester confirms (or it auto-completes).
--   expired   – nobody took it before its deadline.

alter type public.request_status add value if not exists 'delivered' before 'completed';
alter type public.request_status add value if not exists 'expired';
