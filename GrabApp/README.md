# Grab — clean Section 1 restart

This directory contains the new native SwiftUI project. It is deliberately
separate from the earlier repository-root project so that the previous work is
preserved and the restart is easy to identify.

## Requirements

- macOS with full Xcode 15.4 or newer
- An iPhone simulator running iOS 17 or newer
- No credentials, backend, package install, or third-party dependency

The minimum deployment target is iOS 17.0. The interface uses supported
SwiftUI `Material` glass surfaces and provides an opaque fallback when Reduce
Transparency is enabled.

## Open and run

1. Open `GrabApp/Grab.xcodeproj` in Xcode.
2. Select the shared `Grab` scheme.
3. Choose any iPhone simulator running iOS 17 or newer.
4. Press **Run** (`⌘R`).

Command-line verification with a simulator already installed:

```sh
xcodebuild \
  -project GrabApp/Grab.xcodeproj \
  -scheme Grab \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

If that device name is unavailable, replace it with an installed simulator
from `xcrun simctl list devices available`.

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

- `Grab/App`: app entry point, shared observable state, and four-tab shell
- `Grab/Domain`: local models and deterministic preview fixtures
- `Grab/DesignSystem`: adaptive tokens, glass, controls, cards, chips, avatars
- `Grab/Features`: Home, Groups, Activity, Profile, shared flows, and gallery
- `Grab/Resources`: asset catalog

The shared state persists appearance and ordinary navigation choices with
`UserDefaults`. Domain models are transport-neutral so local fixtures can be
replaced by service-backed data in later sections.

## Current verification

All Swift files passed parser validation, SwiftUI type checking, and a native
arm64 iOS Simulator build with Xcode 26.6. The app was installed, launched, and
visually confirmed on an iPhone 15 Pro simulator running iOS 17.5.

This Mac has older iOS 17 runtimes but not Xcode's matching iOS 26.5 runtime.
Until that runtime is installed, the working local path is a direct target
build followed by `simctl install`; ordinary scheme-based Xcode launching
reports the runtime mismatch. Hands-on VoiceOver and full interaction-matrix
checks remain outstanding.
