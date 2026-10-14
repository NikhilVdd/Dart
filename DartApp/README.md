# Grab — clean Section 1 restart

This directory contains the new native SwiftUI project. It is deliberately
separate from the earlier repository-root project so that the previous work is
preserved and the restart is easy to identify.

## Requirements

- macOS with full Xcode 15.4 or newer
- An iPhone simulator running iOS 17 or newer
- Swift Package Manager resolves one dependency, `supabase-swift`, automatically on first open
- A Supabase project is optional: without one the app runs on built-in preview data

The minimum deployment target is iOS 17.0. The interface uses supported
SwiftUI `Material` glass surfaces and provides an opaque fallback when Reduce
Transparency is enabled.

## Open and run

1. Open `DartApp/Dart.xcodeproj` in Xcode.
2. Select the shared `Dart` scheme.
3. Choose any iPhone simulator running iOS 17 or newer.
4. Press **Run** (`⌘R`).

Command-line verification with a simulator already installed:

```sh
xcodebuild \
  -project DartApp/Dart.xcodeproj \
  -scheme Dart \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

If that device name is unavailable, replace it with an installed simulator
from `xcrun simctl list devices available`.

## Connecting the backend

The backend lives in `/supabase` (schema, security, matching engine, seed). See
`supabase/README.md` for setup. To point the app at it, fill in
`Dart/Resources/Supabase.plist`:

```xml
<key>SUPABASE_URL</key>      <string>https://<project-ref>.supabase.co</string>
<key>SUPABASE_ANON_KEY</key> <string><anon or publishable key></string>
```

For local development you can also set `SUPABASE_URL` and `SUPABASE_ANON_KEY` as environment
variables in the scheme (Edit Scheme → Run → Arguments). They take precedence over the plist.

The app has three modes:

| Mode | When | What you see |
| --- | --- | --- |
| Preview | Placeholders in `Supabase.plist` | The Section 1 sample data; actions explain what they would do |
| Signed out | Backend configured, no session | Main app with sample data and an in-app sign-in/account creation prompt |
| Live | Signed in with email and password | Real requests, runs, groups, chat, shopping lists and earnings, refreshed in realtime |

What works when live:

- **Request**: post a request (specific pickup or *any store*), then see which trips already underway can carry it.
- **Earn**: open requests nearest your building. Accept one, optionally onto one of your runs. Advance it through picking up → on the way → delivered.
- **Runs**: announce a store run to friends, your building or campus. See the requests that fit within your max detour, then accept them.
- **Groups**: create a group or join by invite code, join your building, chat, and edit the shared list.
- **Activity**: timelines for everything you requested or helped with. Requesters confirm receipt.
- **Live status**: accepted deliveries automatically open a Lock Screen/Dynamic Island Live Activity
  and follow picking up → on the way → delivered → completed. APNs keeps it current when the app is closed
  after the production credentials described in [`docs/ios-live-status.md`](../docs/ios-live-status.md) are installed.

Authentication uses standard email/password accounts and accepts any valid email address. The backend
assigns accounts to the launch campus when their email does not match a configured campus domain.
Signing out or deleting an account returns to the launch screen; an existing session enters the app directly.

## What to try

- Switch among Home, Groups, Activity, and Profile using the floating tab bar.
- Switch Request / Earn and compare the relevant Home feeds.
- Open the create sheet and both introductory flows.
- Open task and store-run cards to inspect the detail sheet.
- Enter each group, inspect sample chat and shopping-list previews, and open its
  interactive run card.
- Switch Requesting / Helping and open status timelines.
- Change System / Light / Dark appearance and relaunch to confirm persistence.
- Use Reset demo and confirm the local success state.
- Open the development component gallery from Profile.

All people, messages, tasks, status, rewards, earnings, and budgets are clearly
sample data. Buttons for later work explain their future section; they do not
fabricate acceptance, payment, purchasing, delivery, chat, or notifications.

## Project structure

- `Dart/App`: app entry point, shared observable state, and four-tab shell
- `Dart/Backend`: Supabase config, wire types, typed API wrapper, and `GrabStore` (live data
  mapped onto the view models, preview fallback, realtime refresh)
- `Dart/Features/Account`: email/password sign-in and account creation
- `Dart/Domain`: local models and deterministic preview fixtures
- `Dart/DesignSystem`: adaptive tokens, glass, controls, cards, chips, avatars
- `Dart/Features`: Home, Groups, Activity, Profile, shared flows, and gallery
- `Dart/Resources`: asset catalog
- `DartLiveActivity`: Lock Screen and Dynamic Island widget extension for the full app
- `DartClip`: lightweight tracking experience launched from the public website
- `DartClipLiveActivity`: separate Live Activity extension embedded in the App Clip

The shared state persists appearance and ordinary navigation choices with
`UserDefaults`. Views read from `GrabStore`, which serves either the preview
fixtures or live Supabase data through the same domain models.

## Current verification

All Swift files passed parser validation, SwiftUI type checking, and a native
arm64 iOS Simulator build with Xcode 26.6. The app was installed, launched, and
visually confirmed on an iPhone 15 Pro simulator running iOS 17.5.

This Mac has older iOS 17 runtimes but not Xcode's matching iOS 26.5 runtime.
Until that runtime is installed, the working local path is a direct target
build followed by `simctl install`; ordinary scheme-based Xcode launching
reports the runtime mismatch. Hands-on VoiceOver and full interaction-matrix
checks remain outstanding.
