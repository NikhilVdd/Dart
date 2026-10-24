# Native production gap report

Date: 2026-10-24  
Branch: `codex/native-production`  
Baseline: `6b6f348`

## Repository audit

The canonical native client is `DartApp/`, the database and Edge Functions are in `supabase/`, and the black/lime interaction reference is `web-preview/`. The unrelated untracked directories present at the start of this work were not added, removed, or modified.

The latest canonical commit already resolved the four previously reported conflict-marker files. A repository scan found no remaining merge markers.

## Completed in this checkpoint

- Renamed Xcode products and legacy Swift type names from Grab to Dart.
- Replaced the stale `com.grab.preview.restart` identifiers with `DART_BUNDLE_PREFIX` plus per-target suffixes.
- Replaced the `grab://` scheme with `dart://` and parameterized associated domains and APNs environment.
- Added development, staging-template, and production `.xcconfig` files. Production remains deliberately unconfigured until owner-supplied values exist.
- Moved the existing development Supabase publishable configuration into build settings; no service-role, Stripe secret, APNs key, or signing credential is present.
- Changed Release behavior to fail closed when backend configuration is absent. Preview fixtures remain Debug-only.
- Added native password-reset request, recovery callback handling, password update, restored-session launch gating, and a non-dismissible signed-out gate.
- Added native onboarding for display name, age band, home residence, notification education, and safety-rule acceptance.
- Replaced the native visual tokens and surfaces with the PWA's black/lime system.
- Added a privacy manifest, ATS lockdown, and export-compliance declaration.
- Added additive migrations `20261024000016_safety_and_abuse_controls.sql` and `20261024000017_dart_naming.sql` with age-band attestation, server-enforced minor money restrictions, suspension checks, block/report models and native controls, prohibited-item filtering, rate limits, cross-campus profile/place isolation, and Dart-named push dispatch configuration.
- Preserved the existing Stripe kill switch and payment job/hold architecture. Live payment activation remains off.

## Verified

- PGlite applies every migration from an empty database plus seed and passes the complete RLS/RPC/payment/safety suite.
- The Swift parser accepts the full app, App Clip, and Live Activity source sets.
- The native macOS development harness compiles and links after iOS-only APIs are isolated.
- Xcode resolves the package graph and enumerates `Dart`, `DartClip`, `DartLiveActivity`, and `DartClipLiveActivity` targets.

Exact commands, outcomes, and unexecuted checks are recorded in `test-results-20261024.md`.

## Still required before TestFlight

- Install a compatible iOS simulator/device platform for the installed Xcode. This machine has the iOS 26.5 SDK but only iOS 17.x simulator runtimes, so Xcode currently reports no eligible iOS destination.
- Finish pixel-level SwiftUI parity for all PWA states; only the global visual system and account/onboarding surfaces were migrated in this checkpoint.
- Split the remaining `DartStore` orchestration into injected service protocols and add local cache/offline queues.
- Add native global search, notifications inbox, feedback, feature-flag, and payment eligibility/payout UI. Native report/block/unblock controls are implemented.
- Add pagination cursors to feeds, history, places, and chat.
- Add an iOS unit/UI test target and the required two-account automation.
- Run physical-device APNs, App Clip invocation, universal-link, Dynamic Island, and accessibility audits.
- Capture the required PWA/native comparison screenshots after an eligible simulator or signed device is available.
- Supply and validate production Apple, domain, Supabase, Sentry, Stripe, legal, and support configuration listed in `release-readiness.md`.

