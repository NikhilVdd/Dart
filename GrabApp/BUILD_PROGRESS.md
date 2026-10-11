# Grab restart build progress

Updated: 2026-10-11

## Section 1 — Visual foundation and interactive product preview

- [x] New native iOS project preserved separately from previous work
- [x] Four-tab floating glass shell: Home, Groups, Activity, Profile
- [x] Request / Earn Home modes with distinct local feeds
- [x] Campus request, free friend run, and paid building run previews
- [x] Detail sheets with reward and merchandise budget separated
- [x] Compact create chooser and both introductory flows
- [x] Friend and building sections with navigable group previews
- [x] Sample conversation, store-run card, and shopping list
- [x] Requesting / Helping activity segments and status timelines
- [x] Persisted System / Light / Dark appearance
- [x] Reset demo confirmation and animated local success checkmark
- [x] Reusable colors, spacing, glass, buttons, chips, avatars, and states
- [x] Dynamic Type, VoiceOver labels, large targets, Reduce Motion, and Reduce
  Transparency considerations
- [x] Development-only component gallery
- [x] Development-preview disclosure throughout the app
- [x] No authentication, payments, external service, or background location
- [x] Swift parser validation
- [x] macOS SwiftUI type checking
- [x] Xcode project property-list validation
- [x] Native arm64 iOS Simulator build with Xcode 26.6
- [x] Install and launch on iPhone 15 Pro simulator running iOS 17.5
- [x] Visual render check from an actual simulator screenshot
- [ ] Simulator interaction and small-screen checks
- [ ] VoiceOver and largest Dynamic Type hands-on audit

## Backend foundation (Supabase), pulled forward from Section 5

- [x] Schema: campuses, places, profiles, friend/building groups, runs, requests, status events, chat, shopping lists
- [x] Row level security on every table; status changes only via lifecycle RPCs
- [x] Matching engine: detour-based fit between requests and trips already happening
- [x] Email-code (OTP) auth; campus linked from email domain
- [x] Realtime for requests, runs, chat and lists
- [x] Berkeley reference data migration and demo seed mirroring the preview fixtures
- [x] Database test suite (PGlite, no Docker): RLS, lifecycle, matching
- [x] iOS: `supabase-swift` package, `GrabStore`, sign-in, live Home/Groups/Activity/Profile, create forms
- [x] macOS SwiftUI type check of the full app with the Supabase package
- [x] Requester confirms delivery (helpers stop at "delivered"; auto-complete after 24 h)
- [x] Expiry of overdue requests and finished runs via pg_cron (every minute)
- [x] In-app account deletion (App Store requirement)
- [ ] iOS Simulator build and hands-on run against a live project (no Xcode on the build machine)
- [ ] Wrap `auth.uid()` as `(select auth.uid())` in RLS policies (Supabase performance advisor)
- [ ] Custom SMTP for sign-in emails before inviting real users

## Later build order

2. Campus request creation, acceptance, and fulfillment using local data.
3. Friend groups, chat, shopping lists, and manual store runs.
4. Paid building runs using local data.
5. Location detection and push notifications (accounts and backend data are done).
6. Payments, final testing, and iPhone release preparation.

Section 1 intentionally stops before any action can accept a request, create a
transaction, send a message, edit a list, complete a delivery, or imply a real
notification or payment.
