# Dart matching prototype

Given delivery requests and runners who are already making a trip, decide which runner carries
each request with the least disruption to their trip, and say why in plain English.

Plain JavaScript (ES modules), no dependencies. Matching only ever talks to a **detour provider**
through one interface, and there are two:
- **simulated:** straight lines, deterministic, no network. Used for tests and development.
- **osrm:** real walking or cycling routes from the free OpenStreetMap routing servers.

A dev-only map page in `web-preview/matching.html` shows both (see [Map page](#map-page)).
[`HANDOFF.md`](HANDOFF.md) summarises the current state and what's left.

The Supabase matching in `supabase/migrations/20261011000003_rpc_and_matching.sql`
(`detour_minutes`, `match_runs_for_request`) is unchanged. This prototype uses the same walking
model and extends it with batch assignment, deadlines, availability, multi-store requests,
declines and explanations.

## How it meets the two project briefs

**Matching prototype**

| Requirement | Where |
| --- | --- |
| Inputs: requests (store, drop-off, delivery time); runners (start, destination, availability) | `DeliveryRequest` and `Runner` in `src/contract.js`; `scenarios/berkeley.json` |
| Runner eligibility (availability, timing, feasibility) | `evaluatePair()` in `src/match.js`, `checkFeasibility()` in `src/detour.js`; each rejection has a reason code |
| Ranking by detour and other factors, choosing the best runner | `src/scoring.js` (formula under [Ranking](#ranking)) |
| Many requests at once, not one at a time | Optimal assignment over all pairs, `src/assignment.js` ([Many requests at once](#many-requests-at-once)) |
| No suitable runner | Unmatched requests carry a reason (`NO_ELIGIBLE_RUNNER`, `RUNNERS_ASSIGNED_ELSEWHERE`, …) and a per-runner explanation |
| Reassignment after a decline | `declineAssignment()`; `--decline Q1:R5` in the CLI; "declines" button on the map page |
| No overlapping or conflicting assignments | One request per trip, plus the `OVERLAPPING_ASSIGNMENT` rule against existing commitments |
| ≥ 10 runners, ≥ 5 requests | 11 runners, 6 requests, 7 stores |
| Automated tests, normal and edge cases | 87 tests in `test/` (list under [Tests](#tests)) |
| Run it and see who's selected and why | `npm run match` prints each choice with a plain-English explanation of every runner |

**Routing and detour prototype**

| Requirement | Where |
| --- | --- |
| Browser location with permission; enter or simulate a start instead | Map page: **Use my location**; if denied, preset, **Pick on map**, or typed `lat, lng` |
| Original route from start to destination | `createDetourProvider()` routes start → destination with the chosen provider |
| Modified route through the store and drop-off | start → store → drop-off → destination, with shopping and hand-off time |
| Added time and distance | `addedDurationMin`, `addedDistanceM` (modified − original) |
| Smallest-detour store when several sell the item | `chooseStore()`; every option is listed in `storeCandidates` |
| Configurable max detour and a feasibility verdict | `Runner.maxDetourMinutes` (a field on the map page); `feasible` + `reasonCode` |
| Structured output usable by matching | `DetourEstimate` — the same object matching consumes (shown under **Show the structured output** on the map page) |
| Map or route visualisation | `web-preview/matching.html` (Leaflet + OpenStreetMap) |
| ≥ 5 test scenarios | 26 in `test/osrm.test.js` plus 14 in `test/detour.test.js`, all offline |
| Free mapping, no subscriptions; no live tracking | Free OSRM servers and OSM tiles; location is read once, on request |

**"Use Dart's existing backend language where practical."** Dart's backend is Supabase:
Postgres SQL plus Edge Functions on Deno. The matching logic needs optimal assignment,
decline/re-solve state, and HTTP routing calls, and those don't fit well in SQL. So it's plain
JavaScript with no dependencies, which runs unchanged in a Supabase Edge Function, the
browser (the map page imports it directly) and Node/Bun. Deno 2.1, the runtime Edge Functions
use, was checked to import it and produce the same matches. The walking model is the same as
the existing SQL `detour_minutes()`, and the data model maps onto the existing tables (see
[Data model](#data-model)).

## Commands

Requires Node 20+ (or Bun). From `matching/`:

```sh
npm test                                   # all tests (node --test)
node --test --test-name-pattern "decline" test/*.test.js   # tests whose name matches
npm run match                              # match scenarios/berkeley.json and print the result
node bin/run-matching.mjs --decline Q1:R5 --offline R8     # then R5 declines Q1, then R8 goes offline
node bin/run-matching.mjs --scenario my.json --json        # another scenario, JSON output

# Real routes (OSRM)
node bin/run-matching.mjs --provider osrm                  # live walking routes, ≈ 4 min (1 request/s)
node bin/run-matching.mjs --provider osrm --mode bike      # live cycling routes
node bin/run-matching.mjs --provider osrm --replay test/fixtures/osrm-berkeley-foot.json   # recorded, offline, instant
node bin/run-matching.mjs --mode bike                      # simulated cycling (250 m/min)
node bin/record-routes.mjs                                 # re-record the fixture (network, ≈ 4 min)
```

With Bun: `bun test`, `bun test -t decline`, `bun bin/run-matching.mjs`. Bun also runs the map
page: `cd web-preview && bun --bun run dev`. That's useful on a Mac whose Node is an Intel build
without Rosetta ("bad CPU type in executable").

## Layout

| File | What it is |
| --- | --- |
| `src/contract.js` | The shared contract: `Runner`, `DeliveryRequest`, `Store`, `DetourEstimate`, `DetourProvider` (JSDoc), `REASON` codes, validators |
| `src/detour.js` | Shared store selection and feasibility rules, and `createDetourProvider({ route })`, which every provider is built with |
| `src/providers/simulated.js` | Straight-line provider for development and tests |
| `src/providers/osrm.js` | Real provider: OSRM route function with caching, rate limiting, retries and clear errors |
| `src/providers/recording.js` | Record live routing responses and replay them offline |
| `test/fixtures/osrm-berkeley-foot.json` | Recorded real walking routes for every leg of the Berkeley scenario |
| `bin/run-matching.mjs`, `bin/record-routes.mjs` | CLI for matching, and the fixture recorder |
| `src/scoring.js` | Ranking score and tie-breaks |
| `src/assignment.js` | Optimal assignment (Hungarian algorithm) |
| `src/match.js` | `matchRequests()`, `declineAssignment()`, `markRunnerOffline()` |
| `src/explain.js` | Plain-English explanations |
| `src/config.js` | Every tunable number |
| `scenarios/berkeley.json` | 11 runners, 6 requests, 7 stores around campus (coordinates from the places migrations) |

## Data model

| Contract | Supabase today | Notes |
| --- | --- | --- |
| `Runner.start`, `.destination` | `runs.store_place_id`, `.destination_place_id` | Start can be anywhere, not only a store |
| `Runner.departsAt` | none | New |
| `Runner.availableUntil` | `runs.closes_at` | |
| `Runner.maxDetourMinutes` | `runs.max_added_minutes` | |
| `Runner.status` | `runs.status` | `available` / `busy` / `offline` |
| `Runner.commitments` | accepted `requests` with `helper_id` | Pickup-to-drop-off windows the runner already holds |
| `DeliveryRequest.storeOptions` | `requests.pickup_place_id` (null = any store) | A list of stores that sell the item |
| `DeliveryRequest.dropoff`, `.deliverBy` | `requests.destination_place_id`, `.deliver_by` | |
| `Store` | `places` with `kind = 'store'` | |

Times are ISO strings; durations are minutes; distances are metres.

## Detour model (simulated provider)

- Original route: start → destination. Modified route: start → store → drop-off → destination.
- Each leg is the straight-line (haversine) distance × **1.3** at **80 m/min**, the same as `walk_minutes()` in SQL.
- Handling: **3 min** shopping at the store and **2 min** hand-off at the drop-off, the same as `detour_minutes()`.
- `pickupAt = max(departsAt, now) + leg 1 + 3`, `dropoffAt = pickupAt + leg 2 + 2`, `tripEndAt = dropoffAt + leg 3`.
- Added time and distance = modified − original. Values are reported, and compared, at 0.1 precision.
- `--mode bike` uses 250 m/min (≈ 15 km/h) with the same road factor.

## Real routes (OSRM provider)

`createOsrmProvider({ mode: "foot" | "bike" })` routes each leg with
[OSRM](https://project-osrm.org/) on the free FOSSGIS servers at `routing.openstreetmap.de`
(`routed-foot` / `routed-bike`, no API key). It supplies only the route function; store selection,
feasibility and the estimate shape are the same shared code the simulated provider uses. So
matching runs unchanged with either provider.

- **Caching:** each distinct leg (from → to, by mode) is requested once per provider. Concurrent
  identical requests share one call. A leg OSRM says it can't route (`NoRoute`) stays cached as
  a failure for the run. A failure caused by service trouble isn't cached, so a later run can
  retry it. Reuse one provider across runs to keep the cache. Cached legs are frozen, so no
  caller can change them for everyone else.
- **Being a good citizen:** a burst during development got this machine's IP blocked for a few
  minutes. These limits keep that from happening again:
  - One request at a time, at least 1 s apart (`minIntervalMs`), retries included.
  - HTTP 429/502/503/504 are retried twice with backoff, honouring `Retry-After`. If the server asks
    for more than 30 s, the leg fails instead of stalling the run.
  - After **3 refusals in a row** (403, 429, 5xx, network errors, timeouts), all routing pauses
    for 60 s. Every leg then fails fast with "routing paused…" instead of hammering a server that
    is refusing us.
  - Throttling settings are validated, so a typo can't switch throttling off.
- **Failures:** any failure throws a `RoutingError` with the reason. That covers HTTP errors, `NoRoute`,
  missing numbers, invalid JSON, network errors, and timeouts (15 s, covering the whole response,
  not just its start). Matching turns it into `ROUTING_ERROR` for that pair only and lists it in
  `result.errors`. A failure is never turned into a guessed route.
- **Zero-length legs** (a runner who starts at the store) need no request.
- **Geometry** is the full street polyline (`overview=full`) as `[{ lat, lng }]`.
- **Offline tests:** `test/osrm.test.js` uses fake responses for every failure case, and the
  recorded Berkeley routes for end-to-end matching. A replayed fetch throws for any URL that isn't
  in the recording, so the tests can't reach the network.

A full Berkeley run needs about 150 distinct legs, which takes about 4 minutes live and is instant
replayed. On campus, real walking routes come out longer than the straight-line estimate. For
example, Moffitt → Ida Sproul is 1,030 m and 13.7 min by OSRM, against 12.6 min simulated.

## Map page

`web-preview/matching.html` is a dev-only page served by web-preview's Vite dev server. It is not
part of the production build (only `index.html` is built), and it never reaches the live site.

```sh
cd web-preview && npm install && npm run dev    # then open http://127.0.0.1:5173/matching.html
```

- **One detour:** set the runner's start with **Use my location**. If permission is denied, use a
  preset, **Pick on map**, or typed `lat, lng`. Then set the destination and drop-off the same way,
  tick the stores that sell the item, and pick walking or cycling and real or simulated routing.
  - The map draws the original route (blue, dashed) and the route with the delivery (orange), with
    markers for start, chosen store, other store options, drop-off and destination.
  - The panel shows original, modified and added distance and time, the chosen store, every store
    option, and feasible yes/no with the reason.
- **Full matching:** runs `matchRequests()` on the Berkeley scenario with recorded real routes
  (instant), live routes, or simulated routes. It shows which runner got which request, each with
  its explanation. **Declines** and **goes offline** re-solve in place and highlight what changed.
  Click a card or a route to see that delivery's routes in detail.

The recorded routes are picked up when the dev server starts. After re-recording, restart
`npm run dev`.

Leaflet 1.9.4 draws the map, a dev dependency of web-preview, with tiles from
`tile.openstreetmap.org`. The page has its own CSP, which allows only those tiles and the routing server.

## Store selection and feasibility

For each store option the provider builds the detour, then picks the one with the smallest added
time (ties: added distance, then store id; feasible options before infeasible ones). The chosen
detour is checked in this order, and the first rule broken is the reason:

| Reason | Rule |
| --- | --- |
| `DETOUR_EXCEEDS_MAX` | Added time > the runner's max detour (equal is allowed) |
| `MISSES_DEADLINE` | Drop-off after deliver-by |
| `EXCEEDS_AVAILABILITY` | Runner reaches their destination after their availability ends |
| `OVERLAPPING_ASSIGNMENT` | The pickup-to-drop-off window overlaps one of the runner's `commitments` (back-to-back is fine) |
| `NO_STORE_OPTIONS` | The request lists no store |

Because feasible stores win, a store whose window would overlap a commitment loses to one that
doesn't. The runner is rejected only if no store works.

Matching adds eligibility checks of its own, giving these reasons:
- `DEADLINE_PASSED`, `RUNNER_OFFLINE`, `RUNNER_BUSY` and `DECLINED`
- `DEPARTS_TOO_LATE`: the runner leaves after the deadline
- `ROUTING_ERROR`: the provider threw for that pair or returned non-numeric values. The pair is skipped, never guessed.

## Ranking

Lower is better:

```
score = 1.0 × added minutes
      + 10  × (added minutes ÷ original trip minutes)
      + 0.5 × max(0, 15 − minutes of slack before the deadline)
```

| Weight (`config.scoring`) | Value | Why |
| --- | --- | --- |
| `addedMinutes` | 1.0 | Main factor: one point per extra minute of the runner's time |
| `relativeDetour` | 10 | The same 5 minutes is a bigger ask on a 10-minute walk than on a 30-minute one. Doubling a trip costs 10 points |
| `slackPenalty` | 0.5 | Arriving with little time to spare is risky. Each minute under the target costs half a point |
| `slackTargetMinutes` | 15 | 15+ minutes early carries no risk penalty |

Ties break on added distance, then runner id (numeric-aware: R2 before R10). Each result carries
the score breakdown.

## Many requests at once

All requests are assigned together. Every eligible runner/request pair is scored, and the whole
assignment is solved exactly with the Hungarian algorithm (`src/assignment.js`):

1. **Serve as many requests as possible.** Leaving a request unassigned costs more than any total
   of real scores, so the solver never trades a served request for a better score elsewhere. A
   request whose only eligible runner is also wanted elsewhere keeps that runner whenever the
   other request can be covered by someone else.
2. **Then minimise the total score.**
3. **Then break ties** by each pair's rank (added distance, then runner id). When two requests
   have exactly the same candidates and scores, the earlier request in the input gets the
   lower-id runner.

A greedy "best pair first" pass fails rule 1. In the Berkeley scenario, Jordan (R2) is the
best-scoring runner for the Tylenol (Q2), so greedy gives him Q2. But he is the only runner who can
take the snacks (Q5), so Q5 would go unserved. The solver gives Jordan to Q5 and covers Q1 and Q2
with Sam and Devon. Exact assignment is cheap at campus scale (6 × 11 here).

One runner holds at most one request per trip. Existing `commitments` are handled by the
`OVERLAPPING_ASSIGNMENT` rule above.

The explanation for a runner who is carrying another request gives one of three reasons, matching
how the solver actually decided:
- the other request had no other option
- it is an existing assignment that was kept
- the combined assignment scores better

### Declines and runners going offline

`declineAssignment(result, requestId, runnerId)` excludes that runner for that request and
re-solves. `markRunnerOffline(result, runnerId)` does the same for everything the runner held.
The re-solve uses the cached estimates (no new routing) and adds a bonus for keeping each existing
pair. The bonus is larger than any score improvement but smaller than covering another request.
So other assignments move only when that is the only way to cover the affected request.
`result.changes` lists what moved.

### Output

`matchRequests()` returns, for each request:
- `status`
- the chosen runner and store
- the `estimate` and `score` (with its breakdown)
- `alternatives`: eligible runners ranked, then rejected runners with their reason codes
- an `explanation` that names every runner

For example:

```
R5 (Sam) chosen: adds 5.1 min via Target (Shattuck Ave), score 7.61; arrives 14 min before the 5:45 PM deadline.
R2 (Jordan) would fit (adds 7.7 min via Walgreens (Telegraph Ave), score 10.78) but is carrying Q5 (Late-night snacks), which had no other option.
R1 (Maya) rejected: 16.9 min detour via Target (Shattuck Ave) exceeds their 10 min limit.
R11 (Kai) rejected: already carrying Q0 … which overlaps this pickup-to-drop-off window (5:06 PM–5:14 PM).
```

Unmatched requests get `NO_ELIGIBLE_RUNNER`, `RUNNERS_ASSIGNED_ELSEWHERE`, `ALL_RUNNERS_DECLINED`,
`DEADLINE_PASSED`, `NO_STORE_OPTIONS`, or `ROUTING_ERROR` (every runner's routing failed, so it's
an outage rather than a "no").

## Tests

87 tests, none of which use the network (`npm test`, or `bun test`):

| File | Covers |
| --- | --- |
| `test/match.test.js` (28) | Simple match; several requests competing for one runner; no eligible runner; each rejection reason; decline → next runner; decline with no backup; a decline that moves another assignment only when needed; offline runner; overlapping commitments; multi-store; deadline already passed / too soon; ranking factors and tie-breaks; routing failures; every runner explained |
| `test/detour.test.js` (14) | Route maths and times, multi-store choice, each feasibility rule and its order, the max-detour boundary, no stores |
| `test/osrm.test.js` (26) | OSRM URLs and parsing, caching, retries, timeouts, the pause after repeated refusals, every failure type, the request limiter, and full matching on recorded real Berkeley routes. Also the CLI provider switch |
| `test/assignment.test.js` (8) | The assignment solver against brute force on 300 random cases, plus edge cases |
| `test/scenario.test.js` (11) | Scenario size and expected outcome, determinism, agreement with the SQL `detour_minutes()`, cycling mode, typed coordinates |

## Assumptions

- Runners walk by default; `--mode bike` (or `mode: "bike"`) switches either provider to cycling.
  Shopping and hand-off take the same time either way.
- OSRM durations are used as-is. They come from the foot/bike profiles' own speeds and aren't
  calibrated against real Berkeley walkers.
- The runner shops at the store; the item price and budget aren't modelled here.
- A trip carries at most one request. Requests in a batch never share a runner.
- `now` is passed in, which keeps scenarios and tests deterministic. Times in explanations are shown in `America/Los_Angeles`.
- An overlap check compares pickup-to-drop-off windows only. It doesn't re-route the runner around
  their existing commitment.

## Known limitations

- The straight-line estimate runs faster than real walking routes (10–17% against Apple routes per
  `DartApp/BUILD_PROGRESS.md`). Use `--provider osrm` when the numbers matter.
- Live OSRM is slow for big batches (1 request/s on the free servers; about 150 legs for Berkeley).
  Production would want its own OSRM instance or OSRM's `table` service for durations.
- The free OSRM servers have no uptime guarantee. When they're down, every pair is `ROUTING_ERROR`
  and nothing is matched; that's by design rather than a fallback to guesses.
- No capacity above one per trip (Supabase `runs.capacity` allows up to 20).
- Not wired to Supabase or the apps yet. It runs on scenario files.
- Cost arithmetic is exact integer maths up to roughly 100 requests × 200 runners per batch.
