# Grab backend (Supabase)

Postgres + Auth + Realtime on Supabase. Everything is SQL in `migrations/`: no server to run.

## Data model

| Table | What it is |
| --- | --- |
| `campuses`, `places` | Where things happen. Places have lat/lng and a kind (`store`, `residence`, `library`, …). Users add places from Apple Maps search via `create_place()`. |
| `profiles` | One per auth user: display name, initials, assigned campus, home building. |
| `groups`, `group_members` | Free **friend groups** and paid **building communities**. Join by invite code; campus buildings are discoverable. |
| `runs` | **Supply:** a trip that is already happening ("Devon is in Target, heading back to Unit 2"). Has an audience (friends / building / campus), a per-request fee, a max detour and a capacity. |
| `requests` | **Demand:** a person asking for a physical outcome. Pickup may be a specific place or *any store*. Reward and item budget are separate. |
| `request_events` | Status timeline, written by trigger. |
| `messages`, `list_items` | Group chat and shared shopping lists. |
| `request_messages` | Private chat between a requester and their helper, open while a delivery is in progress. |
| `push_tokens`, `live_activity_tokens` | Per-user APNs destinations for alerts and ActivityKit updates. |
| `request_tracking_links`, `clip_push_tokens` | Capability-secured App Clip tracking links and private APNs destinations. |
| `push_events` | Durable notification outbox populated by request and message triggers. |

Money is integer cents. Requests are paid through Stripe Connect when payments are switched on (see **Payments** below).

### The matching engine

The core rule is to use movement that is already happening before creating a new trip.

`detour_minutes()` estimates the extra walking time for a runner to go
store → pickup → drop-off → their own destination, compared with going store → destination directly.
It uses a 1.3× street-grid factor, 80 m/min, and fixed handling time per stop. A request fits a run when
that detour is within the runner's `max_added_minutes`.

- `match_requests_for_run(run_id)`: requests a runner could carry, smallest detour first.
- `match_runs_for_request(request_id)`: trips already underway that could carry your request.
- `open_requests_nearby(lat, lng)`: the Earn feed, nearest first.

Haversine distance is plenty at campus scale, so PostGIS isn't required. Swap in routing-engine
travel times later without changing the API.

### Request lifecycle (enforced server-side)

```
open ─accept─▶ accepted ─▶ picking_up ─▶ on_the_way ─▶ delivered ─▶ completed
 │ │              │            │             └───────────┴── requester confirms receipt
 │ │              └────────────┴─ release (helper) ──▶ back to open
 │ └─ cancel (requester, while open or accepted) ──▶ cancelled
 └─ deadline passes with nobody on it ──▶ expired
```

- Helpers can move a request as far as **delivered**. Only the requester marks it **completed**,
  from *on the way* or *delivered*. Unconfirmed deliveries auto-complete after 24 hours.
- Clients can't write `status` directly (no column privilege). They call `accept_request`,
  `advance_request`, `release_request`, `cancel_request`, or `request_from_run`.

### Adding places

`create_place(name, kind, lat, lng, detail, address)` is called by the app's place picker after an
Apple Maps (MapKit) search:

- Requires an assigned campus. The point must be within 15 km of that campus.
- **De-duplicates:** a place within 150 m whose name matches, contains or is contained in the new name
  is returned instead. So Apple's "CVS Pharmacy" resolves to the seeded "CVS".
- Each user can add up to 25 places a day. `created_by` records who added each one.

The ten launch places are aligned to Apple Maps coordinates (migration 8).

### Home buildings, leaving groups, request chat

- `set_home_place(place_id)` sets where you live. For a residence it also puts you in that building's
  group, creating the group the first time anyone from that building picks it, and leaves any other
  building group. `join_building_group` now goes through it, so joining a building makes it home.
- `leave_group(group_id)`: leaving a building clears it as your home. When a friend group's owner leaves,
  the longest-standing member becomes owner; the last member out closes the group.
- `request_messages` can be read by the requester and current helper only, and written while the request
  is accepted, picking up, on the way or delivered.

### Housekeeping and account deletion

- `expire_stale()` runs every minute via **pg_cron** (job `grab-expire-stale`). It expires overdue open
  requests, auto-completes deliveries unconfirmed for 24 hours, and closes runs an hour after their cutoff
  once nothing is in flight (three hours at most). Clients can't call it.
- `delete_my_account()` (the App Store requires in-app deletion) hands back deliveries you were making,
  completes ones you already delivered, passes your groups to the longest-standing member, deletes
  friend groups where you were the last member, then deletes your auth user. Your profile, requests,
  runs and memberships cascade; messages and list items stay with the author cleared.

### Push notifications (Web Push, migration 12)

The installed PWA gets real push notifications through Web Push with our own VAPID keys. No Apple
Developer account or APNs is involved; iPhone (iOS 16.4+) delivers them once Grab is opened from the
Home Screen and the person taps **Turn on notifications**.

```
trigger ─▶ enqueue_push() ─▶ notification_outbox ─pg_net─▶ send-push Edge Function ─▶ Apple / Google / Mozilla push service
                                     ▲                                                    
                         grab-push-retry (pg_cron, every minute)
```

- `push_subscriptions`: one row per browser/device, registered with `save_push_subscription()` and removed
  with `delete_push_subscription()` (or automatically when the push service says it's gone). Only real
  push-service endpoints are accepted. Clients can't read the table.
- `notification_prefs`: per-person switches (no settings screen yet; defaults apply). On by default: order progress, private chat, group store
  runs. Opt-in: campus-wide runs, new requests nearby, group chat.
- What sends what:

| Event | Who hears | Category |
| --- | --- | --- |
| Request accepted → picking up → on the way → delivered | Requester (one tag per request, so it updates in place with a `▰▰▰▱▱` meter) | `request_updates` |
| Requester confirms / housekeeping auto-completes | Helper (and requester when automatic) | `request_updates` |
| Cancelled; released back to open; expired | Helper / requester | `request_updates` |
| Someone asks a runner for something (`request_from_run`) | Runner | `request_updates` |
| Store run announced to a friend or building group | Group members | `run_announcements` |
| Store run announced to the campus | Everyone on the campus who opted in | `campus_runs` |
| Private request chat message | The other participant | `chat` |
| New open request | Its group, or its campus (opt-in) | `nearby_requests` |
| Group chat message | Group members (opt-in) | `group_chat` |

The person who caused an event is never notified about it. Unsent updates that share a tag collapse to
the newest one, and the push `Topic` header does the same at the push service for a phone that's offline.

#### Turning it on for a hosted project

1. Generate a VAPID key pair (`npx web-push generate-vapid-keys`) and a long random webhook secret.
   Put the **public** key in `web-preview/src/config.js` (`VAPID_PUBLIC_KEY`). Never commit the private key.
2. Apply the migration: `npx supabase db push`.
3. Set the function secrets and deploy it:
   ```sh
   npx supabase secrets set VAPID_PUBLIC_KEY=<public> VAPID_PRIVATE_KEY=<private> \
     VAPID_SUBJECT=mailto:<contact email> PUSH_WEBHOOK_SECRET=<webhook secret>
   npx supabase functions deploy send-push --no-verify-jwt
   ```
4. Tell Postgres where to send (SQL editor):
   ```sql
   select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/send-push', 'grab_push_url');
   select vault.create_secret('<webhook secret>', 'grab_push_secret');
   ```
5. Deploy the web app, open it from the Home Screen and tap Profile → Account → **Turn on
   notifications**. (`send_test_push()` queues a test for the signed-in user.) `select * from notification_outbox order by id desc` shows what was
   queued, sent, superseded, or why it failed (`last_error`).

Rotating the VAPID keys invalidates every device; each one re-registers the next time Grab is opened.

### Payments (Stripe Connect, migration 15)

Dart is a Connect **marketplace** using **separate charges and transfers**: Dart is the merchant of
record, runners are connected accounts (Accounts v2, `recipient` configuration, Express Dashboard), and
the requester's card is only held until they confirm delivery. Dart keeps nothing: the requester pays
the receipt total + the delivery fee (`payment_settings.delivery_fee_cents`, $2.50) + Stripe's card fee
(grossed up: 2.9% + 30¢ for US cards, 4.4% + 30¢ for international ones; the hold assumes the higher
rate), and the runner receives receipt total + delivery fee.

```
post ─▶ payments{start} ─▶ Payment Element (manual capture hold) ─▶ payments{confirm} ─▶ insert request (payment_intent_id)
accept ─▶ needs payout_accounts.transfers_active (embedded onboarding: payments{onboard})
on the way ─▶ set_item_cost(receipt total ≤ budget) ─▶ delivered ─▶ requester confirms (or 24 h auto-complete)
completed ─▶ payment_jobs 'capture' ─pg_net─▶ payments{settle}: capture, then transfer to the runner
cancelled / expired / requester account deleted / hold never used (30 min) ─▶ 'cancel' ─▶ hold released
```

- `payment_holds` (no client access) is the source of truth for each card hold; amounts on a paid request
  come from its hold and can't be changed by the client. `requests.payment_status` mirrors it for the UI.
- `payout_accounts` maps a runner to their Stripe account; readable only by that runner.
- Card holds last 7 days (`payment_holds.capture_before` records Stripe's exact deadline), so paid requests
  must be due within 4 days of posting and 2 days before that deadline. A delivered paid request
  auto-completes once its hold has under 12 hours left, and runners can't start shopping on a lapsed hold.
- `payments{start}` refuses when payments are off and allows 5 holds per person per hour (15 per day)
  to blunt card testing. Add Radar rules for card testing too.
- Stripe calls only happen in `functions/payments` (the secret key never reaches the browser).
  `functions/stripe-webhook` backs up hold confirmation and records holds Stripe cancels or expires.
- Dart pays Connect's own fees (per active account per month, per payout) and dispute fees ($15 each,
  plus the disputed amount if lost); those aren't covered by the requester's card fee.

#### Turning it on

Use a Stripe **sandbox** (test keys) until the whole flow has been tried end to end.

1. Stripe Dashboard: Connect → finish the platform profile and **accept loss liability** (the platform is
   responsible for negative balances). Set onboarding branding under Connect settings. Turn on Radar.
2. Apply the migration (`npx supabase db push`). Payments stay **off** until step 6.
3. Pick a long random job secret, then set secrets and deploy:
   ```sh
   npx supabase secrets set STRIPE_SECRET_KEY=sk_test_… STRIPE_PUBLISHABLE_KEY=pk_test_… \
     PAYMENTS_WEBHOOK_SECRET=<job secret>
   npx supabase functions deploy payments --no-verify-jwt
   ```
   A restricted key (`rk_…`) works if it has: PaymentIntents **write**, Charges **read**, Transfers
   **write**, and under Connect: Accounts, Account Sessions and Login Links **write**. A missing
   permission shows up as a Stripe permission error in the PWA or in `payment_jobs.last_error`.
4. Tell Postgres where to send settlement jobs (SQL editor):
   ```sql
   select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/payments', 'dart_payments_url');
   select vault.create_secret('<job secret>', 'dart_payments_secret');
   ```
5. Stripe Dashboard → Developers → Webhooks: add `https://<project-ref>.supabase.co/functions/v1/stripe-webhook`
   for `payment_intent.amount_capturable_updated`, `payment_intent.canceled` and `charge.dispute.created`, then
   ```sh
   npx supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_…
   npx supabase functions deploy stripe-webhook --no-verify-jwt
   ```
   For Apple Pay, register the web app's domain under Settings → Payment method domains.
6. Switch payments on: `update public.payment_settings set required = true;`

`select * from payment_jobs order by id desc` shows queued captures/releases and why any failed
(`last_error`; failed jobs retry every minute, up to 20 attempts). A capture whose money was already
taken but couldn't be transferred keeps retrying hourly after that; check for these with
`select * from payment_jobs where done_at is null and attempts >= 20`.

### Security

Row level security is on for every table:

- Groups, chat and lists are visible only to members.
- Runs and requests are visible to their audience (group or campus). Once a request is accepted, only the requester, the helper and the run's runner can see it.
- Users can edit only their own profile name and building. A matching email domain selects a campus;
  all other standard accounts are assigned to the first configured campus.
- Signed-out clients can read only the campus list.

## Setup

### Option A: hosted project (no Docker needed)

1. Create a free project at [supabase.com](https://supabase.com/dashboard).
2. Link it and apply the schema:
   ```sh
   npx supabase login
   npx supabase link --project-ref <your-project-ref>
   npx supabase db push              # add --include-seed for the demo users/data
   ```
3. The iOS app uses standard email/password accounts. For immediate sign-up without relying on email
   delivery, turn off **Confirm email** under Authentication → Providers → Email. If confirmation stays
   on, configure custom SMTP so new users reliably receive the confirmation message.
4. Copy **Project URL** and the **anon / publishable key** from *Project Settings → API* into
   `DartApp/Dart/Resources/Supabase.plist`.
5. For remote notifications, deploy `send-dart-push` and `register-clip-push`, add the APNs secrets,
   and point a Database Webhook for `push_events` inserts at `send-dart-push`. Exact values and Apple
   setup are in [`docs/ios-live-status.md`](../docs/ios-live-status.md).

Supabase's built-in email sender is heavily rate-limited. If confirmation or password recovery is
enabled, set up custom SMTP under *Authentication → SMTP Settings*, for example Resend or Postmark.

### Option B: local stack (needs Docker Desktop)

```sh
npx supabase start      # prints the API URL and anon key
npx supabase db reset   # applies migrations + seed.sql
```

Put `http://127.0.0.1:54321` and the printed anon key in `Supabase.plist`, or set the `SUPABASE_URL` and
`SUPABASE_ANON_KEY` environment variables in the Xcode scheme. Sign in as `nikhil@berkeley.edu` with
password `grab-demo`. Studio is at http://127.0.0.1:54323.

## Tests (no Docker needed)

```sh
cd supabase/tests/pglite && npm install && npm test
```

This applies every migration and the seed to an in-memory Postgres 17 (PGlite), using a small stand-in
for Supabase's `auth` schema and roles. It then checks RLS, the lifecycle RPCs and matching while acting as each demo user.

## Manual testing with test accounts

`supabase/dev/accounts.mjs` mints sign-in codes for any email (no email is sent), creates a building
group to test with, and lists and deletes users. See [`docs/manual-testing.md`](../docs/manual-testing.md)
for the full two-account test plan.

`supabase/dev/demo.mjs setup` builds a live demo scene (background people, runs, requests, chat, history)
and prints sign-in codes for two presenter accounts. `reset` removes it. See [`docs/demo.md`](../docs/demo.md)
for the recording script.

## Adding a migration

```sh
npx supabase migration new <name>   # write SQL, then:
npm --prefix supabase/tests/pglite test && npx supabase db push
```
