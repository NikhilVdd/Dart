# Grab

Ask for a physical outcome ("a blender under $50 in 15 minutes") and the network works out where
it comes from and who is already heading that way.

- `DartApp/`: native SwiftUI iOS app. See `DartApp/README.md`.
- `supabase/`: backend (Postgres schema, row level security, matching engine, auth, realtime). See `supabase/README.md`.
- `web-preview/`: production installable web app (PWA) using the same Supabase accounts and data.
  See `web-preview/README.md`.
- `matching/`: batch matching prototype (shared detour contract, simulated and real OSM routing
  providers, assignment and explanations; no dependencies). A dev-only map page lives at
  `web-preview/matching.html`. See `matching/README.md` and `matching/HANDOFF.md`.
