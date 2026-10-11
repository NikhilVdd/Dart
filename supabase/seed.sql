-- Demo seed. Applied locally by `supabase db reset`; reaches a hosted project only with
-- `supabase db push --include-seed` (useful for a shared staging/demo project, not production).
-- Mirrors the iOS app's PreviewData so the signed-in app looks like the preview build.
-- Campus and places come from migration 20261011000004 (they ship to production too).
--
-- Demo accounts (sign in with the email code from Mailpit at http://127.0.0.1:54324):
--   nikhil@berkeley.edu   – the app's default persona
--   maya@berkeley.edu, jordan@berkeley.edu, devon@berkeley.edu
-- Each also has the password "grab-demo" for quick API testing.

-- ---------------------------------------------------------------------------
-- Demo users (the on_auth_user_created trigger creates their profiles)
-- ---------------------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
  extensions.crypt('grab-demo', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', jsonb_build_object('display_name', u.name), now(), now(),
  '', '', '', ''
from (values
  ('00000000-0000-0000-0000-000000000001'::uuid, 'maya@berkeley.edu', 'Maya Chen'),
  ('00000000-0000-0000-0000-000000000002'::uuid, 'jordan@berkeley.edu', 'Jordan Lee'),
  ('00000000-0000-0000-0000-000000000003'::uuid, 'devon@berkeley.edu', 'Devon Park'),
  ('00000000-0000-0000-0000-000000000004'::uuid, 'nikhil@berkeley.edu', 'Nikhil Varma')
) as u (id, email, name);

insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text,
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       'email', now(), now(), now()
from auth.users u
where u.email like '%@berkeley.edu';

update public.profiles set home_place_id = 'a0000000-0000-0000-0000-000000000007'
where id in ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004');
update public.profiles set home_place_id = 'a0000000-0000-0000-0000-000000000008'
where id in ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003');

-- ---------------------------------------------------------------------------
-- Groups
-- ---------------------------------------------------------------------------

insert into public.groups (id, name, kind, campus_id, place_id, invite_code, created_by) values
  ('20000000-0000-0000-0000-000000000001', 'Sunday Dinner', 'friends', 'c0000000-0000-0000-0000-000000000001', null, 'SUNDAY01', '00000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002', 'Design Studio', 'friends', 'c0000000-0000-0000-0000-000000000001', null, 'STUDIO02', '00000000-0000-0000-0000-000000000003'),
  ('20000000-0000-0000-0000-000000000003', 'The Durant', 'building', 'c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000007', 'DURANT03', '00000000-0000-0000-0000-000000000001');

insert into public.group_members (group_id, user_id, role) values
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'owner'),
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'member'),
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'member'),
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', 'owner'),
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000004', 'member'),
  ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'owner'),
  ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000003', 'member'),
  ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004', 'member');

-- ---------------------------------------------------------------------------
-- Runs: movement that is already happening
-- ---------------------------------------------------------------------------

insert into public.runs (id, runner_id, campus_id, group_id, audience, store_place_id, store_label, destination_place_id, destination_label, note, status, closes_at, fee_cents, max_added_minutes, capacity) values
  -- Maya's free Trader Joe's run for Sunday Dinner.
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001',
   '20000000-0000-0000-0000-000000000001', 'friends', 'a0000000-0000-0000-0000-000000000002', 'Trader Joe''s · University Avenue',
   'a0000000-0000-0000-0000-000000000007', 'Friends: Sunday Dinner', 'Add something before I check out.', 'shopping',
   now() + interval '18 minutes', 0, 15, 6),
  -- Maya's paid building run back to The Durant.
  ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001',
   '20000000-0000-0000-0000-000000000003', 'building', 'a0000000-0000-0000-0000-000000000001', 'Target · Shattuck Avenue',
   'a0000000-0000-0000-0000-000000000007', 'The Durant · Lobby', 'A paid building run approved by the shopper.', 'open',
   now() + interval '75 minutes', 500, 10, 2),
  -- Devon is inside Target heading back to Unit 2 – open to the whole campus.
  ('30000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001',
   null, 'campus', 'a0000000-0000-0000-0000-000000000001', 'Target · Shattuck Avenue',
   'a0000000-0000-0000-0000-000000000008', 'Unit 2', 'In Target now, walking back to Unit 2.', 'shopping',
   now() + interval '25 minutes', 600, 8, 3);

-- ---------------------------------------------------------------------------
-- Requests (inserted open, then moved through the lifecycle so the timeline is populated)
-- ---------------------------------------------------------------------------

insert into public.requests (id, requester_id, campus_id, group_id, title, details, pickup_place_id, pickup_label, destination_place_id, destination_label, deliver_by, reward_cents, merchandise_budget_cents, est_minutes) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', null,
   'Grab my charger from the library', 'Labeled USB-C charger at the Moffitt front desk. Show the request name when you arrive.',
   'a0000000-0000-0000-0000-000000000004', 'Moffitt Library · Front desk', 'a0000000-0000-0000-0000-000000000005', 'Ida Sproul Hall · Unit 3',
   now() + interval '2 hours', 1000, null, 15),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000001', null,
   'Pick up shampoo from Target', 'Any unscented everyday shampoo.',
   'a0000000-0000-0000-0000-000000000001', 'Target · Shattuck Avenue', 'a0000000-0000-0000-0000-000000000006', 'Blackwell Hall',
   now() + interval '3 hours', 600, 1400, 10),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', null,
   'Blender under $50', 'Any store is fine – personal-size blender, under $50.',
   null, 'Any store', 'a0000000-0000-0000-0000-000000000008', 'Unit 2 · Cunningham Hall',
   now() + interval '45 minutes', 800, 5000, null),
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000003',
   'Paper towels for the apartment', 'Two-roll pack is fine.',
   'a0000000-0000-0000-0000-000000000001', 'Target · Shattuck Avenue', 'a0000000-0000-0000-0000-000000000007', 'The Durant · Lobby',
   now() + interval '2 hours', 500, 900, null),
  ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001', null,
   'Return a book to Moffitt', 'Drop it in the return slot.',
   'a0000000-0000-0000-0000-000000000008', 'Unit 2 · Cunningham Hall', 'a0000000-0000-0000-0000-000000000004', 'Moffitt Library',
   now() - interval '1 day', 400, null, 12);

-- Shampoo: accepted by Maya on her building run.
update public.requests set status = 'accepted', helper_id = '00000000-0000-0000-0000-000000000001',
  run_id = '30000000-0000-0000-0000-000000000002', accepted_at = now() - interval '6 minutes'
where id = '10000000-0000-0000-0000-000000000002';

-- Paper towels: Maya's building run, already on the way back.
update public.requests set status = 'accepted', helper_id = '00000000-0000-0000-0000-000000000001',
  run_id = '30000000-0000-0000-0000-000000000002', accepted_at = now() - interval '20 minutes'
where id = '10000000-0000-0000-0000-000000000004';
update public.requests set status = 'picking_up' where id = '10000000-0000-0000-0000-000000000004';
update public.requests set status = 'on_the_way' where id = '10000000-0000-0000-0000-000000000004';

-- Book return: Nikhil helped Devon yesterday.
update public.requests set status = 'accepted', helper_id = '00000000-0000-0000-0000-000000000004', accepted_at = now() - interval '1 day 1 hour'
where id = '10000000-0000-0000-0000-000000000005';
update public.requests set status = 'picking_up' where id = '10000000-0000-0000-0000-000000000005';
update public.requests set status = 'on_the_way' where id = '10000000-0000-0000-0000-000000000005';
update public.requests set status = 'completed', completed_at = now() - interval '1 day' where id = '10000000-0000-0000-0000-000000000005';

-- ---------------------------------------------------------------------------
-- Chat and shopping lists
-- ---------------------------------------------------------------------------

insert into public.messages (group_id, sender_id, run_id, body, created_at) values
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Heading to Trader Joe''s — add anything you need.', now() - interval '12 minutes'),
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', null, 'Perfect timing. I''ll add sparkling water later!', now() - interval '10 minutes'),
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', null, 'Anyone going near the art store tonight?', now() - interval '90 minutes'),
  ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002', 'I approved a Target run for the building.', now() - interval '25 minutes');

insert into public.list_items (group_id, run_id, added_by, body, quantity, status) values
  ('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'Sparkling water', 2, 'needed'),
  ('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'Pasta', 1, 'picked'),
  ('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Basil', 1, 'needed'),
  ('20000000-0000-0000-0000-000000000002', null, '00000000-0000-0000-0000-000000000003', 'Tracing paper', 1, 'needed'),
  ('20000000-0000-0000-0000-000000000002', null, '00000000-0000-0000-0000-000000000004', 'Black markers', 3, 'needed'),
  ('20000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', 'Laundry detergent', 1, 'needed');
