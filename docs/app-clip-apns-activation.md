# App Clip, universal link, APNs, and Live Activity activation

Engineering is parameterized but activation requires owner-controlled Apple and domain values.

1. Choose an owned HTTPS domain and final reverse-domain `DART_BUNDLE_PREFIX`.
2. Register four identifiers in the Apple Developer portal: full app, full-app Live Activity extension, App Clip, and App Clip Live Activity extension.
3. Enable Associated Domains, App Clips, Push Notifications, and Live Activities on the appropriate identifiers.
4. Put the real domain and bundle prefix in staging/production xcconfig files. Set the App Clip as a child of the full app in App Store Connect.
5. After the Team ID exists, publish `/.well-known/apple-app-site-association` with `applinks` and `appclips` entries for the real application identifiers. Do not use redirects or a file extension.
6. Configure the App Clip experience URL to a capability-secured tracking route. The route must reject missing, expired, rotated, or mismatched capabilities.
7. Store APNs `.p8`, Key ID, Team ID, service-role key, and webhook secrets only in the Edge Function secret store. Never add them to the app or repository.
8. Validate APNs sandbox using a development-signed physical device, then production APNs using TestFlight. Confirm token rotation after reinstall/account change.
9. Validate Lock Screen and every Dynamic Island presentation with foreground realtime and remote Live Activity pushes.
10. Validate App Clip size using the Release archive and test invocation through an App Clip Code/NFC/universal link before submission.

The placeholder `dart.example.invalid` intentionally prevents accidental association until an owned domain is supplied.

