# Migration notes: 20261024000016–17

`20261024000016_safety_and_abuse_controls.sql` is additive and must be deployed after the Stripe migration.

It adds:

- `profiles.age_band`, `profiles.account_status`, and `profiles.safety_rules_accepted_at`.
- One-time `set_my_age_band` and `accept_safety_rules` RPCs.
- Private `user_blocks` and write-only `safety_reports` tables.
- Private rate-limit counters and server-side write throttles.
- A private prohibited-term list and guards for requests, runs, chats, and shopping lists.
- Request/run safety triggers that enforce account status, blocks, and adult eligibility for money-bearing activity.
- Same-campus RLS for profiles and places, plus blocked-user filtering for request/run discovery.

Deployment order:

1. Back up the staging database and record the migration version.
2. Apply to a new staging database restored from production-like data.
3. Confirm existing profiles receive `not_set`, `active`, and null safety acceptance.
4. Exercise onboarding and verify existing users cannot use paid features until they attest.
5. Run `node supabase/tests/pglite/run.mjs` and the two-account manual suite.
6. Deploy during a monitored window. Roll back application traffic, not the migration; the new columns/tables are additive.

The seed marks only local/staging fixture users as adults and safety-accepted. Production must never apply `supabase/seed.sql`.

`20261024000017_dart_naming.sql` is a small compatibility migration. It replaces the active user
bootstrap fallback name with `Dart member` and moves the Web Push dispatcher to `dart_push_url`,
`dart_push_secret`, and `x-dart-push-secret`. Historical migrations and existing pg_cron job names are
left intact because already-applied migrations must not be rewritten.

Before deploying migration 17, create the two Dart-named Vault secrets. Keep the previous secrets until
the new dispatcher has successfully sent a staging notification, then revoke them through the normal
secret-rotation process.

