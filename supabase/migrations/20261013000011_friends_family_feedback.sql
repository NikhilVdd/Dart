-- Friends & Family launch telemetry. Both tables are append-only from the client.
-- Contact details remain in auth; feedback only stores the authenticated profile id.

create table public.launch_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete set null default auth.uid(),
  category text not null check (category in ('idea', 'bug', 'confusing', 'love')),
  message text not null check (char_length(btrim(message)) between 3 and 2000),
  contact_ok boolean not null default false,
  page text check (page in ('home', 'groups', 'request', 'earn', 'activity', 'profile')),
  created_at timestamptz not null default now()
);

create table public.product_events (
  id bigint generated always as identity primary key,
  user_id uuid references public.profiles (id) on delete set null default auth.uid(),
  event_name text not null check (event_name ~ '^[a-z][a-z0-9_]{1,63}$'),
  context jsonb not null default '{}'::jsonb check (jsonb_typeof(context) = 'object'),
  created_at timestamptz not null default now()
);

create index launch_feedback_created_idx on public.launch_feedback (created_at desc);
create index product_events_created_idx on public.product_events (created_at desc);
create index product_events_name_created_idx on public.product_events (event_name, created_at desc);

alter table public.launch_feedback enable row level security;
alter table public.product_events enable row level security;

create policy "members submit launch feedback" on public.launch_feedback
  for insert to authenticated with check (user_id = auth.uid());

create policy "members record their product events" on public.product_events
  for insert to authenticated with check (user_id = auth.uid());

revoke all on public.launch_feedback from anon, authenticated;
revoke all on public.product_events from anon, authenticated;

grant insert (category, message, contact_ok, page) on public.launch_feedback to authenticated;
grant insert (event_name, context) on public.product_events to authenticated;

alter publication supabase_realtime add table public.launch_feedback;
