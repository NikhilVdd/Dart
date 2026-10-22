# Hand-off to Rijul (Stage 2)

Stage 1 is done: the shared contract, the shared store selection and feasibility rules, a simulated
provider, batch matching, the Berkeley scenario and 59 tests. All of it is in `matching/`.
[`README.md`](README.md) covers how ranking and assignment work. This file covers what you need to
build on it.

## Commands

From `matching/`:

```sh
npm test                                                   # 59 tests, offline, ~0.2 s
node --test --test-name-pattern "multi-store" test/*.test.js   # tests whose name matches
npm run match                                              # Berkeley scenario, simulated provider
node bin/run-matching.mjs --decline Q1:R5 --offline R8 --json
```

> **This Mac's Node is broken.** `/usr/local/bin/node` is an x86_64 build on an arm64 Mac without
> Rosetta ("bad CPU type"). Either install Rosetta (`softwareupdate --install-rosetta --agree-to-license`)
> or an arm64 Node, or use Bun: `bun test`, `bun bin/run-matching.mjs`. Stage 1 was verified with both
> Bun 1.3.14 and an arm64 Node 20.18.1.

## Where things live

| What | Where |
| --- | --- |
| Contract types (`Runner`, `DeliveryRequest`, `Store`, `RouteLeg`, `DetourEstimate`, `DetourProvider`) | `src/contract.js` (JSDoc) |
| Reason codes | `REASON` in `src/contract.js` |
| Store selection, feasibility, building a provider | `src/detour.js` |
| Simulated provider (the reference implementation) | `src/providers/simulated.js` |
| Matching entry points | `src/match.js`, all re-exported from `src/index.js` |
| Tunables (walking model, handling time, weights) | `src/config.js` |
| Scenario loader (pure, works in the browser) | `src/scenario.js` + `scenarios/berkeley.json` |
| CLI | `bin/run-matching.mjs` |

## Writing the real provider: you only write `route()`

Don't re-implement store selection or feasibility. `createDetourProvider()` takes one function:

```js
// route(from, to) → Promise<{ distanceM, durationMin, geometry: [{ lat, lng }, …] }>
//   durationMin is travel time only; detour.js adds the 3 + 2 min of handling.
import { createDetourProvider } from "./src/detour.js";

export function createRoutingProvider({ route, config }) {
  return createDetourProvider({ name: "routing", description: "OSRM foot profile", route, config });
}
```

For each runner/request pair it calls `route()` for the original trip (start → destination) and
for three legs per store option (start → store, store → drop-off, drop-off → destination). It then
fills in every `DetourEstimate` field: chosen store, original/modified, added, pickup/drop-off/trip-end
times, feasible + reason, geometry and per-store candidates. Store choice and the feasibility rules
are the shared code in `chooseStore` / `checkFeasibility` / `estimateForStore`. That's the Step 4
"reuse, don't duplicate" requirement.

Things your `route()` needs to handle:
- **Validation:** `createDetourProvider` checks every leg you return. A missing, negative or non-finite
  `distanceM`/`durationMin` throws "route() returned an invalid leg" and is handled as below, so a
  partial routing response can't become a fake estimate.
- **Errors:** throw. Never return a guessed leg. Matching catches the error per pair, rejects that runner with
  `ROUTING_ERROR` and the message, lists it in `result.errors`, and keeps matching everyone else.
  Test: `"a routing failure rejects only that runner…"` in `test/match.test.js`.
- **Caching:** there is none yet. One batch calls `route()` for the same start → destination once per
  request, and the same store → drop-off once per runner. Memoising by
  `${from.lat},${from.lng}→${to.lat},${to.lng}` inside the provider covers "avoid repeat calls within a run".
- **Concurrency:** matching estimates all pairs with `Promise.all`. With a rate-limited service, put a
  limiter inside `route()`.
- **Geometry:** `[{ lat, lng }]` arrays. The simulated provider returns only the endpoints of each leg;
  `estimate.geometry.modified` is the legs joined with duplicate points removed.
- **Walking vs cycling:** the simulated provider reads `config.travel` (`roadFactor`,
  `metersPerMinute`). A mode switch on your provider can follow the same idea.
- **Offline tests:** follow `test/helpers.js`. `planarRoute` is a fake `route()` with exact numbers,
  and `planarProvider()` counts calls and can make a runner fail. Recorded route responses can be
  served the same way.

## Running matching with any provider

Matching never imports a provider; it takes one as an argument:

```js
import { matchRequests, declineAssignment, markRunnerOffline, resolveScenario } from "./src/index.js";

const scenario = resolveScenario(json);           // { now, runners, requests, stores }
const result = await matchRequests({ ...scenario, provider });   // any DetourProvider
const next = declineAssignment(result, "Q1", "R5"); // re-solve; uses cached estimates, no new routing
```

The CLI hard-codes `createSimulatedProvider()` near the top of `bin/run-matching.mjs`. That's where a
`--provider simulated|routing` option should go (Stage 2, Step 2). Nothing in `src/match.js` should
need to change.

For the frontend: everything in `src/` is plain ESM with no Node imports, so `web-preview` (Vite) can
import it directly. Since it's outside the Vite root, you'll need `server.fs.allow: [".."]` in
`web-preview/vite.config.js`, or a copy step. `bin/` and `test/` use `node:fs`.

## Where Stage 1 went beyond CLAUDE.MD's contract

Check these against your plans:

- `estimateDetour(runner, request, { now })` is **async**, so a network-backed provider fits.
- `DetourEstimate` also has `tripEndAt` (needed for the availability rule), `reasonDetail` (numbers
  for explanations), `storeName`, and `storeCandidates` (every store option, best first).
- `REASON.ROUTING_ERROR` exists so a provider failure is never a fake success. A request becomes
  unmatched with `ROUTING_ERROR` when every runner's routing failed.
- The commitment overlap check is a shared feasibility rule in `checkFeasibility`, applied per
  store. So store selection skips a store whose window clashes, and your provider gets this for free.
- `Runner.status` is `available | busy | offline`. `Runner.commitments` holds existing pickup-to-drop-off windows.
- `DeliveryRequest.storeOptions` holds resolved `Store` objects, not ids. `resolveScenario()` resolves ids from JSON.

## Unfinished or uncertain

- The simulated provider's geometry is straight lines, good enough for a map placeholder only.
- The CLI has no `--provider` flag yet (yours).
- Overlap checks compare time windows only. They don't route a runner around a delivery they already hold.
- Capacity is one request per trip; Supabase allows `runs.capacity` up to 20.
- Not connected to Supabase. Mapping a `runs` row to a `Runner` needs a departure time (the table has
  only `created_at`) and the store list for "any store" requests.
- The weights in `src/config.js` are reasoned defaults, not tuned against real data.
- Unrelated to this work: the iOS app currently has unresolved merge-conflict markers from commit
  `077d289` (`DartApp/Dart/Backend/DartStore.swift`, `DartBackend.swift`).
