# Grab web app

Production PWA for Grab. It uses the same hosted Supabase Auth, Postgres, realtime subscriptions,
row-level security policies, and lifecycle RPCs as the native iOS app.

The Friends & Family build uses a black-and-lime responsive design system and includes guided
onboarding, global search, request sorting, live activity updates, install prompts, and an in-app
feedback channel. Every product surface reads and writes real Supabase data; there is no mock mode
in the production web bundle.

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

The hosted project currently permits immediate email/password signup. Password-reset delivery to
arbitrary Friends & Family addresses requires custom SMTP in Supabase; the default mail service is
only suitable for project-team testing.

## Push notifications

Grab uses standard Web Push (VAPID), so it works without an Apple Developer account:

- **iPhone / iPad (iOS 16.4+):** only after Grab is added to the Home Screen and opened from there.
  The permission prompt only appears from a tap: Profile → Account → **Turn on notifications**.
- **Android, desktop Chrome, Edge, Firefox, macOS Safari:** works in the browser or installed.

Each request has one notification that is replaced at every step (`▰▰▰▱▱ On the way`), which is the
closest the web gets to a Live Activity. A true Live Activity / Dynamic Island progress bar needs a
native app with ActivityKit and therefore an Apple Developer account.

`src/push.js` handles permission, subscription and badge; `public/sw.js` shows notifications and opens
the right screen when one is tapped (`./?request=<id>`, `./?run=<id>`, `./?tab=groups&group=<id>`).
The backend side (outbox, triggers, `send-push` Edge Function, setup steps) is in `supabase/README.md`.

## Matching lab (dev only)

`matching.html` and `prototype/` are a development-only map page for the matching prototype in
`../matching` (one runner's detour on real streets, and full batch matching with explanations).
Open it at `http://127.0.0.1:5173/matching.html` while `npm run dev` is running.

It is not built or deployed: `vite build` only builds `index.html`, and Leaflet is a dev dependency.
`vite.config.js` lets the dev server read `../matching`. Details are in `../matching/README.md`.

## Current product boundary

Rewards and merchandise budgets are recorded by the backend, but payments are not charged. A
payment provider, payout onboarding, dispute handling, and production push notification provider
must be completed before enabling real-money transactions.
