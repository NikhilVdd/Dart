# Dart native iOS app

This directory contains the canonical SwiftUI client, App Clip, and Live Activity extensions for Dart. It targets iPhone on iOS 17+ and connects to the Supabase backend in `../supabase`.

## Open and run

1. Install an iOS runtime compatible with the installed Xcode.
2. Open `DartApp/Dart.xcodeproj`.
3. Select the shared `Dart` scheme and an iPhone simulator.
4. Run with `⌘R`.

Command-line verification:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project DartApp/Dart.xcodeproj \
  -scheme Dart \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO build
```

The optional `MacRun` package compiles the shared SwiftUI surface as a development harness when a compatible iOS platform is unavailable:

```sh
cd DartApp/MacRun
swift build -c debug --disable-automatic-resolution
```

## Configuration

Configuration is centralized in `Configuration/`:

- `Base.xcconfig` contains non-secret defaults and derives every identifier from `DART_BUNDLE_PREFIX`.
- `Development.xcconfig` points at the current non-production Supabase project.
- `Staging.xcconfig.example` documents required staging values.
- `Production.xcconfig` is intentionally unusable until the owner supplies production values.

The app, App Clip, and Live Activity identifiers use these suffixes:

```text
$(DART_BUNDLE_PREFIX)
$(DART_BUNDLE_PREFIX).LiveActivity
$(DART_BUNDLE_PREFIX).Clip
$(DART_BUNDLE_PREFIX).Clip.LiveActivity
```

Never put a service-role key, Stripe secret, APNs key, webhook secret, signing certificate, or Team ID in the repository. A Supabase publishable key is a client identifier and remains constrained by RLS.

Debug builds may show deterministic preview fixtures when no backend is configured. Release builds never fall back to preview data; they show a configuration error instead.

## Authentication and onboarding

Dart uses standard Supabase email/password accounts with any valid email address. The app supports sign-up, hosted email confirmation, sign-in, session restoration, password recovery through `dart://auth/recovery`, sign-out, and in-app account deletion.

New accounts complete native onboarding for display name, Berkeley campus context, age-band attestation, home residence, notification education, and safety rules. The backend—not the view—enforces under-18 money restrictions.

## Targets

- `Dart`: full SwiftUI app.
- `DartLiveActivity`: Lock Screen and Dynamic Island UI.
- `DartClip`: capability-secured request tracking and full-app handoff.
- `DartClipLiveActivity`: App Clip Live Activity extension.

The final bundle prefix, Apple Team ID, owned associated domain, signing profiles, and production service projects are external release gates. See `../docs/app-clip-apns-activation.md` and `../docs/release-readiness.md`.

## Verification

Current evidence and known limitations are recorded in `../docs/native-gap-report.md` and
`../docs/test-results-20261024.md`. Do not infer TestFlight or App Store readiness from a successful
local compile.
