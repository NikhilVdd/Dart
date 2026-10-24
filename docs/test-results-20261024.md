# Test results — 2026-10-24

These are engineering results for branch `codex/native-production` through the hosted smoke-test
checkpoint. They are not TestFlight, production, legal, or physical-device validation.

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

### Hosted two-account flow

```sh
DART_ENVIRONMENT=development \
SUPABASE_URL=<development-project-url> \
SUPABASE_ANON_KEY=<development-publishable-key> \
node supabase/tests/hosted/two-account.mjs
```

Result: `HOSTED TWO-ACCOUNT E2E PASSED (27 assertions)` against the configured Supabase development
project after applying migrations `20261024000016` and `20261024000017`. The run exercised ordinary
email/password signup and sign-in, onboarding, Berkeley places, friend-group creation and joining,
group chat, shared lists, request creation and discovery, a campus run, acceptance, private request
chat, the complete server-authoritative request lifecycle, earnings, and RLS denial cases. Three
disposable accounts were deleted successfully in the test's cleanup block.

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
17.5 runtimes. The matching iOS 26.5 simulator runtime is an 8.52 GB download; installation was not
continued with only about 12–13 GB free because expansion could exhaust the startup disk. Free space
or remove obsolete simulator data, install the runtime, rerun all four target builds in Debug and
Release, then execute the UI suites.

## Not yet executed

- iOS unit and UI automation (test targets still need to be added).
- The remaining manual scenarios in `docs/manual-testing.md` beyond the automated 27-assertion hosted
  two-account smoke test.
- Simulator/device screenshot comparisons against `web-preview/`.
- VoiceOver, largest Dynamic Type, Reduce Motion, Reduce Transparency, contrast, and keyboard audits.
- Physical-device APNs sandbox, TestFlight production APNs, App Clip invocation, universal links, and
  Dynamic Island validation.
- Stripe test-mode and webhook end-to-end testing against an owner-configured staging project.
- Load, soak, backup/PITR restore, incident-response, and rollback exercises.
