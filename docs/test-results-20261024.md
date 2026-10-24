# Test results — 2026-10-24

These are local engineering results for branch `codex/native-production` at baseline `6b6f348` plus
the unpushed checkpoint changes. They are not TestFlight, production, legal, or physical-device
validation.

## Passed

### Supabase schema, RLS, RPCs, payments, and safety

```sh
/Users/nikhilvaddey/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node \
  supabase/tests/pglite/run.mjs
```

Result: all migrations `20261011000001` through `20261024000017` applied to an empty PGlite database,
the development seed applied, and the full suite ended with `ALL PASSED`. Coverage includes account
bootstrap, campus/group/request visibility, protected lifecycle transitions, chat, place creation,
account deletion, Web Push, APNs token tables, Live Activity token authorization, payment holds/jobs,
age restrictions, blocks, write-only reports, prohibited-item guards, and cross-campus place isolation.

### Swift source parsing

```sh
find DartApp/Dart DartApp/DartClip DartApp/DartLiveActivity -name '*.swift' -print0 \
  | xargs -0 swiftc -frontend -parse
```

Result: exit 0 for the full app, App Clip, and both Live Activity source sets.

### Semantic compile and link harness

```sh
cd DartApp/MacRun
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build -c debug --disable-automatic-resolution
```

Result: `Build complete!`. The harness uses the resolved Supabase package and conditionally isolates
iOS-only APIs so SwiftUI and backend integration receive semantic type checking on this machine.

### Xcode project and platform metadata

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project DartApp/Dart.xcodeproj -list
plutil -lint DartApp/Dart/Resources/PrivacyInfo.xcprivacy \
  DartApp/Dart/Resources/Info.plist DartApp/DartClip/Info.plist \
  DartApp/Dart/Resources/Dart.entitlements DartApp/DartClip/DartClip.entitlements
git diff --check
```

Result: Xcode resolved Supabase `2.55.3` and listed the `Dart`, `DartClip`, `DartLiveActivity`, and
`DartClipLiveActivity` targets and schemes. Every plist/entitlement passed lint and the diff has no
whitespace errors.

## Environment-blocked

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project DartApp/Dart.xcodeproj -scheme Dart -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/DartDerived \
  CODE_SIGNING_ALLOWED=NO build
```

Xcode resolved every package, then stopped before compiling with:

```text
Unable to find a destination matching generic/platform=iOS Simulator
iOS 26.5 is not installed. Please download and install the platform from Xcode > Settings > Components.
```

The active Xcode contains the iPhoneOS 26.5 SDK while CoreSimulator lists only iOS 17.0, 17.2, and
17.5 runtimes. Install a compatible Xcode platform/runtime, rerun all four target builds in Debug and
Release, then execute the UI and two-account suites.

## Not yet executed

- iOS unit and UI automation (test targets still need to be added).
- Two-account hosted end-to-end scenarios in `docs/manual-testing.md`.
- Simulator/device screenshot comparisons against `web-preview/`.
- VoiceOver, largest Dynamic Type, Reduce Motion, Reduce Transparency, contrast, and keyboard audits.
- Physical-device APNs sandbox, TestFlight production APNs, App Clip invocation, universal links, and
  Dynamic Island validation.
- Stripe test-mode and webhook end-to-end testing against an owner-configured staging project.
- Load, soak, backup/PITR restore, incident-response, and rollback exercises.
