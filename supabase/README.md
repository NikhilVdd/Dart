# Grab backend (Supabase)

Postgres + Auth + Realtime on Supabase. Everything is SQL in `migrations/`: no server to run.

## Data model

| Table | What it is |
| --- | --- |
| `campuses`, `places` | Where things happen. Places have lat/lng and a kind (`store`, `residence`, `library`, …). Users add places from Apple Maps search via `create_place()`. |
| `profiles` | One per auth user: display name, initials, campus (from email domain), home building. |
| `groups`, `group_members` | Free **friend groups** and paid **building communities**. Join by invite code; campus buildings are discoverable. |
| `runs` | **Supply:** a trip that is already happening ("Devon is in Target, heading back to Unit 2"). Has an audience (friends / building / campus), a per-request fee, a max detour and a capacity. |
| `requests` | **Demand:** a person asking for a physical outcome. Pickup may be a specific place or *any store*. Reward and item budget are separate. |
| `request_events` | Status timeline, written by trigger. |
| `messages`, `list_items` | Group chat and shared shopping lists. |

Money is integer cents. Payments are **recorded, not charged**: Stripe Connect is a later section.

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

- Requires a campus (campus email). The point must be within 15 km of that campus.
- **De-duplicates:** a place within 150 m whose name matches, contains or is contained in the new name
  is returned instead. So Apple's "CVS Pharmacy" resolves to the seeded "CVS".
- Each user can add up to 25 places a day. `created_by` records who added each one.

The ten launch places are aligned to Apple Maps coordinates (migration 8).

### Housekeeping and account deletion

- `expire_stale()` runs every minute via **pg_cron** (job `grab-expire-stale`). It expires overdue open
  requests, auto-completes deliveries unconfirmed for 24 hours, and closes runs an hour after their cutoff
  once nothing is in flight (three hours at most). Clients can't call it.
- `delete_my_account()` (the App Store requires in-app deletion) hands back deliveries you were making,
  completes ones you already delivered, passes your groups to the longest-standing member, deletes
  friend groups where you were the last member, then deletes your auth user. Your profile, requests,
  runs and memberships cascade; messages and list items stay with the author cleared.

### Security

Row level security is on for every table:

- Groups, chat and lists are visible only to members.
- Runs and requests are visible to their audience (group or campus). Once a request is accepted, only the requester, the helper and the run's runner can see it.
- Users can edit only their own profile name and building; campus comes from the verified email domain.
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
3. Make sign-in emails contain the 6-digit code: `npx supabase config push` uploads `config.toml`,
   including `templates/otp.html`. **Free-tier projects can't change email templates while using
   Supabase's built-in sender.** Configure custom SMTP first (step below), then push.
4. Copy **Project URL** and the **anon / publishable key** from *Project Settings → API* into
   `GrabApp/Grab/Resources/Supabase.plist`.

Supabase's built-in email sender is heavily rate-limited (a few emails per hour). Before inviting
real users, set up custom SMTP under *Authentication → SMTP Settings*, for example Resend or Postmark.

### Option B: local stack (needs Docker Desktop)

```sh
npx supabase start      # prints the API URL and anon key
npx supabase db reset   # applies migrations + seed.sql
```

Put `http://127.0.0.1:54321` and the printed anon key in `Supabase.plist`, or set the `SUPABASE_URL` and
`SUPABASE_ANON_KEY` environment variables in the Xcode scheme. Sign in as `nikhil@berkeley.edu`. The code
arrives in Mailpit at http://127.0.0.1:54324. Studio is at http://127.0.0.1:54323.

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

## Adding a migration

```sh
npx supabase migration new <name>   # write SQL, then:
npm --prefix supabase/tests/pglite test && npx supabase db push
```
