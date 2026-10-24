# Dart native architecture

## Runtime shape

SwiftUI owns presentation and main-actor view state. `DartStore` currently coordinates typed Supabase reads/writes, realtime refreshes, location, notifications, and Live Activities. Wire records in `BackendRows.swift` are decoded into view-facing domain models; views do not receive raw dictionaries.

```text
SwiftUI features
      |
      v
DartStore (@MainActor)
  |       |        |          |
  v       v        v          v
DartBackend  LocationProvider  Notifier  LiveActivityCoordinator
  |
  v
Supabase Auth / PostgREST / Realtime / RPCs
  |
  v
RLS + lifecycle RPCs + outbox jobs + Edge Functions
```

Request lifecycle columns are server-authoritative. The client uses `accept_request`, `advance_request`, `release_request`, and `cancel_request`; it does not directly mutate protected request state. Payments use server-created holds and idempotent queued settlement jobs.

## Configuration

`DartApp/Configuration/Base.xcconfig` defines non-secret keys and derives bundle identifiers from `DART_BUNDLE_PREFIX`. Debug uses `Development.xcconfig`. Release uses the intentionally empty `Production.xcconfig`, which causes a clear configuration screen instead of demo data.

The required final service boundaries are:

- `AuthService`: account creation, confirmation, sign-in, recovery, session restoration, sign-out, deletion.
- `DartRepository`: typed paginated reads and RPC-backed writes.
- `RealtimeService`: scoped subscriptions and reconnect/backoff behavior.
- `LocationService`: permission state, approximate origin, MapKit search, routes, fallbacks.
- `NotificationService`: permission education, token rotation, badge state, deep links.
- `LiveActivityService`: one active request tracker and token registration.
- `PaymentService`: eligibility, intents, reimbursements, rewards, refunds, disputes, payouts.
- `FeatureFlagService`: server-controlled payment and rollout gates.
- `AnalyticsService`: privacy-safe product events and crash/performance breadcrumbs.

`DartStore` is still the compatibility composition root. Extracting those protocols, adding injected implementations, and introducing a safe local read cache are tracked as release-blocking work rather than being falsely labeled complete.

## Deep-link contract

- `dart://auth/recovery`: Supabase password recovery callback.
- `dart://request/<uuid>`: request details/tracking.
- HTTPS `/request/<uuid>?capability=<secret>`: App Clip tracking invocation.
- HTTPS request, run, group, and notification URLs: universal links after the production domain and AASA file exist.

All UUIDs and capability tokens must be validated server-side. A route never grants data access by itself.

