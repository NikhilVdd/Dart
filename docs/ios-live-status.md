# iOS push notifications, Live Activities, and App Clip

Dart contains native support for a DoorDash-style status tracker:

- The full app registers APNs tokens after permission and upserts them for the signed-in account.
- Accepted requests start a Live Activity; foreground Supabase realtime updates its status.
- `DartLiveActivity` renders Lock Screen and Dynamic Island expanded, compact, and minimal states.
- `DartClip` tracks one capability-secured request, can request ephemeral notifications, starts the same Live Activity, and links into the full app.
- `push_events` and the durable outbox drive standard and ActivityKit APNs payloads through `send-dart-push`.

All identifiers are derived from `DART_BUNDLE_PREFIX`; associated domains use `DART_ASSOCIATED_DOMAIN`; APNs entitlement selection uses `DART_APNS_ENVIRONMENT`. The committed production values are intentionally invalid placeholders, so they cannot accidentally claim a domain or Apple identity.

Production activation requires the real Apple Team ID, final bundle prefix, owned HTTPS domain, signing/provisioning, APNs key, App Store Connect App Clip experience, and physical-device validation. Follow [app-clip-apns-activation.md](app-clip-apns-activation.md).

Do not publish a placeholder AASA file and do not store APNs, service-role, Stripe, or webhook secrets in the app.
