# iOS push notifications, Live Activities, and App Clip

Grab now has the native and backend pieces for a DoorDash-style delivery tracker:

- `Grab` registers an APNs device token after notification permission and stores it under the signed-in user.
- Accepted requests start a Live Activity. Supabase realtime updates it immediately while Grab is open.
- `GrabLiveActivity` renders the Lock Screen, Dynamic Island expanded/compact/minimal, progress, route, and latest status.
- `GrabClip` can start the same tracker from a capability-secured request URL and registers both its ephemeral-alert and Live Activity tokens.
- `push_events` queues request/message events; `send-grab-push` delivers standard alerts and ActivityKit update/end payloads through APNs.

The public web app remains live at <https://grab-product-preview-nv.vaddeynikhil.chatgpt.site>. The iOS
associated-domain entitlements already point at that host. The site is not a replacement for the native
App Clip: it is the public entry surface that can invoke the App Clip after Apple association is activated.

## Required production activation

These steps need the Apple Developer account and cannot be completed with an unsigned simulator build:

1. Set the Apple Development Team on all four targets and register these identifiers (or replace them with the final identifiers):
   - `com.grab.preview.restart`
   - `com.grab.preview.restart.LiveActivity`
   - `com.grab.preview.restart.Clip`
   - `com.grab.preview.restart.Clip.LiveActivity`
2. Enable Push Notifications, Associated Domains, App Clips, and Live Activities in the identifiers/profiles.
3. Create an APNs `.p8` key and save these Supabase Edge Function secrets:
   - `APNS_TEAM_ID`
   - `APNS_KEY_ID`
   - `APNS_PRIVATE_KEY` (the full PEM value)
   - `PUSH_WEBHOOK_SECRET` (a new random secret)
4. Apply `20261013000012_push_live_activity.sql`, then deploy:

   ```sh
   supabase db push
   supabase functions deploy register-clip-push --no-verify-jwt
   supabase functions deploy send-grab-push --no-verify-jwt
   supabase secrets set APNS_TEAM_ID=... APNS_KEY_ID=... APNS_PRIVATE_KEY=... PUSH_WEBHOOK_SECRET=...
   ```

5. In Supabase Database Webhooks, invoke `send-grab-push` on `INSERT` to `public.push_events` and add
   `x-grab-webhook-secret: <PUSH_WEBHOOK_SECRET>`.
6. Host `/.well-known/apple-app-site-association` on the final website with the real Apple Team ID and
   app identifiers, then configure the default/advanced App Clip experience in App Store Connect.

Do not publish a placeholder association file. Apple requires the real Team ID, and the App Clip must be
signed and uploaded before an invocation URL can launch it on an iPhone. Until then, the existing website
continues to work as the installable PWA and the App Clip/Live Activity can be built and previewed locally.

Apple references: [App Clip notifications](https://developer.apple.com/documentation/AppClip/enabling-notifications-in-app-clips),
[Live Activities in an App Clip](https://developer.apple.com/documentation/appclip/offering-live-activities-with-your-app-clip),
[ActivityKit push updates](https://developer.apple.com/documentation/ActivityKit/starting-and-updating-live-activities-with-activitykit-push-notifications),
and [website association](https://developer.apple.com/documentation/appclip/associating-your-app-clip-with-your-website).
