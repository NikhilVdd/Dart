# Production-readiness matrix

This branch is an engineering checkpoint, not a production-ready declaration.

| Area | Status | Evidence or exact next action | Owner |
|---|---|---|---|
| Conflict-free baseline | Complete | No conflict markers; synced from `6b6f348` | Engineering |
| Standard email/password auth | Implemented | Native sign-up/sign-in/session/recovery/update/delete paths | Engineering |
| Black/lime native system | In progress | Global tokens/surfaces and account/onboarding migrated; finish screen-by-screen parity | Design + iOS |
| Backend lifecycle/RLS | Passing locally | PGlite full suite passes | Backend |
| Minor safety | Backend foundation complete | Age band, money restrictions, block/report, prohibited items | Safety + Legal |
| Native blocking/reporting | Implemented | Report and block from request details; review and unblock from Profile | iOS + Safety |
| Payments | Disabled architecture | Stripe holds/jobs/webhooks exist; keep `payment_settings.required=false` | Payments |
| Native payment UI | Not complete | Implement eligibility, PaymentSheet, receipt, refund, payout states | iOS + Payments |
| Environment separation | Scaffolded | Create distinct staging/production Supabase projects and fill xcconfig | Platform owner |
| Bundle IDs/signing | Blocked externally | Supply final prefix, Apple Team ID, certificates/profiles | Apple account owner |
| Universal links/App Clip | Blocked externally | Supply owned domain; publish AASA; configure App Store Connect | Domain + Apple owner |
| APNs/Live Activities | Needs devices | Validate sandbox and TestFlight production paths | iOS QA |
| iOS build on this machine | Environment blocked | Install matching iOS platform/runtime in Xcode | Local machine owner |
| Comparison screenshots | Environment blocked | Capture every major native screen after installing an eligible simulator runtime | Design + QA |
| Unit/UI tests | Not complete | Add test targets and automate required flows | QA + iOS |
| Accessibility | Not audited | VoiceOver, Dynamic Type, contrast, Reduce Motion/Transparency | Accessibility QA |
| Observability | Not complete | Create Sentry projects; install SDK; configure privacy scrubbing | Platform |
| Load/SLOs | Not complete | Define and measure auth/feed/realtime/push budgets | Backend/SRE |
| Backups/PITR | External | Enable Supabase PITR and perform timed restore exercise | Platform owner |
| Legal policies | External blocker | Counsel-approved Terms, Privacy, minors, retention, community standards | Legal |
| Moderation/support | External blocker | Staff queue, escalation SLA, appeals, emergency/support copy | Operations |
| App Store metadata | Not complete | Privacy labels, screenshots, support URL, deletion instructions | Product |

## Archive gate

Do not create a TestFlight archive until the production configuration is non-placeholder, Release has no demo fallback, all four targets build with valid profiles, automated suites pass, and the archive is scanned for development endpoints and credentials.

## Rollback gate

Before public rollout: record the prior App Store build, maintain the server payment kill switch, retain backwards-compatible migrations, document Edge Function rollback, test database restore, and assign an incident commander/support channel.

