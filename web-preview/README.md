# Grab web app

Production PWA for Grab. It uses the same hosted Supabase Auth, Postgres, realtime subscriptions,
row-level security policies, and lifecycle RPCs as the native iOS app.

## Local development

```sh
npm install
npm run dev
```

## Verification

```sh
npm run check
npm run build
```

The publishable Supabase key in `src/config.js` is intentionally public. Authorization is enforced
by Supabase row-level security. Never add a service-role key to this project.

## Deployment

The built static app is emitted to `dist/`. `.openai/hosting.json` connects that directory to the
existing Grab Site. The production origin must be added to Supabase Auth's allowed redirect URLs if
email confirmation or password recovery is enabled.

## Current product boundary

Rewards and merchandise budgets are recorded by the backend, but payments are not charged. A
payment provider, payout onboarding, dispute handling, and production push notification provider
must be completed before enabling real-money transactions.
