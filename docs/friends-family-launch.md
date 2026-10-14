# Grab Friends & Family launch

## Public app

The public PWA is hosted at:

https://grab-product-preview-nv.vaddeynikhil.chatgpt.site

It is responsive, installable from Safari or Chrome, and backed by the production Supabase project.

## What is live

- Email/password signup, sign-in, sign-out, account deletion, and password-reset initiation
- Guided first-run onboarding and mobile Home Screen installation
- Campus, building, and private-friend groups with realtime messages and shared lists
- Requests, store runs, matching, accepting, delivery progress, private request chat, and completion
- Search across requests, runs, and groups; Earn sorting by time, proximity, or reward
- In-app Friends & Family feedback and privacy-preserving product event capture
- Row-level security, append-only telemetry, and authenticated-only feedback writes

## Launch operations

1. Keep the production origin in Supabase Auth URL Configuration.
2. Configure custom SMTP before relying on password-reset email for external testers. Supabase's
   default mailer is rate-limited and intended for project-team testing.
3. Review `launch_feedback` and aggregated `product_events` in Supabase. Clients cannot read either
   table and cannot spoof another user as the author.
4. Keep payments disabled. Budgets and rewards are coordination amounts only; no card is charged
   and no payout is sent.
5. Run the checks below before each release.

```sh
cd web-preview
npm install
npm run check
npm run build

cd ../supabase/tests/pglite
npm install
npm test
```

## Release checklist

- Test signup and sign-in with a fresh account.
- Complete onboarding and visit Home, Groups, Request, Earn, Activity, and Profile.
- Verify global search, updates, feedback, and mobile navigation.
- Exercise the request lifecycle with two accounts before widening the audience.
- Confirm the production deployment status and test both desktop and 390-pixel mobile layouts.
- Check Supabase Auth, database, and realtime health; review RLS tests for failures.

## Known boundary

Payment processing and payouts are intentionally out of scope for Friends & Family. Custom SMTP is
the only remaining external service configuration needed for reliable password-reset email delivery.
