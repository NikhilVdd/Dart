# Dart security and privacy threat model

## Protected assets

Accounts and sessions; campus/group membership; private chat; approximate home/building information; request capability links; APNs and Live Activity tokens; payment holds, ledger/jobs, Stripe account identifiers; moderation reports; and operational credentials.

## Trust boundaries

The iOS app and App Clip are untrusted public clients. Supabase Auth establishes identity. Postgres RLS and security-definer RPCs authorize every read and state transition. Edge Functions hold service-role, APNs, webhook, and Stripe credentials. Apple/Stripe webhook payloads remain untrusted until signature and replay checks pass.

## Principal threats and controls

| Threat | Current control | Remaining release work |
|---|---|---|
| Cross-account/campus reads | RLS, same-campus profile/place policies, private group/request policies | Add a second-campus hosted integration suite |
| Lifecycle tampering | Protected columns and server RPC state machine | Fuzz invalid transitions in CI |
| Private chat leakage | Participant/group RLS | Add block-aware policies to every historical group-chat surface |
| Token theft | Token tables unreadable to clients; owner-bound inserts | Retention job and physical-device rotation test |
| App Clip link guessing | Random capability record with participant-only visibility | Final HTTPS route, TTL/rotation, abuse telemetry |
| Minor money use | Immutable age-band attestation path and server request/run guards | Counsel-approved eligibility and support process |
| Harassment/unsafe handoff | Server block/report model; block-filtered feeds | Native moderation UI and staffed review SLA |
| Prohibited goods | Server content guard | Human review/appeal and broader policy taxonomy |
| Spam/automation | Per-user server write counters | Auth CAPTCHA, IP/device limits, invite-code limits |
| Payment manipulation | Server-sourced amounts, holds/jobs, idempotent Stripe objects, kill switch | Immutable double-entry ledger and production webhook review |
| Secret disclosure | No service/APNs/Stripe secret in app configuration | Secret scanning CI and managed secret rotation |
| Sensitive analytics | Product events intended for non-sensitive metadata | Schema allowlist and Sentry scrubbing tests |

The app must never transmit passwords, auth tokens, message bodies, exact live locations, capability secrets, or sensitive request text to analytics/crash tooling.

