# Hand-off: matching and routing prototype

Both stages are built:
- **Stage 1:** the shared contract, store selection and feasibility, the simulated provider, batch
  matching, the Berkeley scenario and tests.
- **Stage 2:** the real OSRM routing provider, the provider switch in the CLI, and the dev-only map
  page in `web-preview/matching.html`.

[`README.md`](README.md) explains how everything works. This file is the state of play for whoever
picks it up next.

## Commands

From `matching/`:

```sh
npm test                                                     # all tests, offline
node --test --test-name-pattern "OSRM" test/*.test.js        # tests whose name matches
npm run match                                                # Berkeley, simulated provider
node bin/run-matching.mjs --provider osrm --replay test/fixtures/osrm-berkeley-foot.json   # real routes, offline
node bin/run-matching.mjs --provider osrm [--mode bike]      # real routes, live (≈ 4 min)
node bin/record-routes.mjs                                   # refresh the recorded routes (network)
```

Map page, from `web-preview/`: `npm install && npm run dev`, then open `http://127.0.0.1:5173/matching.html`.

> **This Mac's Node is broken.** `/usr/local/bin/node` is an x86_64 build on an arm64 Mac without
> Rosetta ("bad CPU type"). Either install Rosetta (`softwareupdate --install-rosetta --agree-to-license`)
> or an arm64 Node ≥ 20.19 (Vite 7 needs it), or use Bun: `bun test`, `bun bin/run-matching.mjs`.
> Everything was verified with Bun 1.3.14 and an arm64 Node 20.18.1.

## Where things live

| What | Where |
| --- | --- |
| Contract types and `REASON` codes | `src/contract.js` |
| Store selection, feasibility (incl. commitment overlap), `createDetourProvider({ route })` | `src/detour.js` |
| Simulated provider | `src/providers/simulated.js` |
| Real provider (OSRM) | `src/providers/osrm.js` |
| Record/replay of routing responses | `src/providers/recording.js`, `bin/record-routes.mjs`, `test/fixtures/` |
| Matching (`matchRequests`, `declineAssignment`, `markRunnerOffline`) | `src/match.js` |
| Tunables | `src/config.js` |
| Map page | `web-preview/matching.html`, `web-preview/prototype/` |

## Swapping providers

Matching takes the provider as an argument and never imports one:

```js
import { createOsrmProvider, createSimulatedProvider, matchRequests } from "./src/index.js";

const provider = live ? createOsrmProvider({ mode: "foot" }) : createSimulatedProvider();
const result = await matchRequests({ ...scenario, provider });
```

Any new provider should be built with `createDetourProvider({ name, route })` and supply only
`route(from, to) → { distanceM, durationMin, geometry }`. That way the store selection and
feasibility rules are reused, not copied.

## Contract changes

**Stage 2 changed nothing in the contract.** The OSRM provider fits the interface as it was. What
was added is additive only:
- Providers expose `mode`. The OSRM one also exposes `stats` and `cache`.
- `createSimulatedProvider({ mode })` and `config.travel.bikeMetersPerMinute` were added.

For the record, Stage 1 had already gone beyond CLAUDE.MD's minimum:
- `estimateDetour` is async.
- `DetourEstimate` adds `tripEndAt`, `reasonDetail`, `storeName` and `storeCandidates`.
- `REASON.ROUTING_ERROR` was added. A request is unmatched with `ROUTING_ERROR` when every runner's routing failed.
- `Runner.status` can be `busy`, and `Runner.commitments` was added. The commitment overlap check is a
  per-store feasibility rule, so store selection avoids a store whose window clashes.

## Unfinished or uncertain

- **Live OSRM is slow and fragile at batch scale.** The free servers allow about 1 request/s, and
  bursts get the IP blocked for a few minutes; that happened once during development. A real
  deployment needs its own OSRM instance (or the `table` service).
- **The recording is a snapshot.** Re-record it after changing the scenario. The replay test fails
  if a leg is missing.
- OSRM walking speeds are the profile defaults. They're not calibrated.
- Overlap checks compare time windows only. Capacity is one request per trip.
- Not connected to Supabase or the iOS app. A `runs` row has no departure time, and "any store"
  requests need a store list.
- The weights in `src/config.js` are reasoned defaults, not tuned against real data.
- Unrelated: the iOS app has unresolved merge-conflict markers from commit `077d289`.
