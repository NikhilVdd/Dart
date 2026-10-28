-- Postgres runs same-event triggers in name order. Rename the role checks so they run before
-- the payment hold check: a darter-only account trying to post should hear "only requester
-- accounts can request deliveries", not "add a payment method".

alter trigger requests_enforce_account_roles on public.requests rename to requests_account_roles;
alter trigger runs_enforce_account_roles on public.runs rename to runs_account_roles;
