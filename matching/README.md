# Dart matching prototype

Given delivery requests and runners who are already making a trip, decide which runner carries
each request with the least disruption to their trip, and say why in plain English.

Plain JavaScript (ES modules), no dependencies, no network. Matching only ever talks to a
**detour provider** through one interface. This stage ships a deterministic simulated provider;
the real routing provider plugs into the same interface (see [`HANDOFF.md`](HANDOFF.md)).

The Supabase matching in `supabase/migrations/20261011000003_rpc_and_matching.sql`
(`detour_minutes`, `match_runs_for_request`) is unchanged. This prototype uses the same walking
model and extends it with batch assignment, deadlines, availability, multi-store requests,
declines and explanations.

## Commands

Requires Node 20+ (or Bun). From `matching/`:

```sh
npm test                                   # all tests (node --test)
node --test --test-name-pattern "decline" test/*.test.js   # tests whose name matches
npm run match                              # match scenarios/berkeley.json and print the result
node bin/run-matching.mjs --decline Q1:R5 --offline R8     # then R5 declines Q1, then R8 goes offline
node bin/run-matching.mjs --scenario my.json --json        # another scenario, JSON output
```

With Bun: `bun test`, `bun test -t decline`, `bun bin/run-matching.mjs`.

## Layout

| File | What it is |
| --- | --- |
| `src/contract.js` | The shared contract: `Runner`, `DeliveryRequest`, `Store`, `DetourEstimate`, `DetourProvider` (JSDoc), `REASON` codes, validators |
| `src/detour.js` | Shared store selection and feasibility rules, and `createDetourProvider({ route })`, which every provider is built with |
| `src/providers/simulated.js` | Straight-line provider for development and tests |
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

## Assumptions

- Runners walk. Cycling is a config change (`travel.metersPerMinute`).
- The runner shops at the store; the item price and budget aren't modelled here.
- A trip carries at most one request. Requests in a batch never share a runner.
- `now` is passed in, which keeps scenarios and tests deterministic. Times in explanations are shown in `America/Los_Angeles`.
- An overlap check compares pickup-to-drop-off windows only. It doesn't re-route the runner around
  their existing commitment.

## Known limitations

- The straight-line estimate runs 10–17% faster than Apple walking routes (see
  `DartApp/BUILD_PROGRESS.md`). The real routing provider replaces it.
- No capacity above one per trip (Supabase `runs.capacity` allows up to 20).
- Not wired to Supabase or the apps yet. It runs on scenario files.
- Pair estimates are requested all at once (`Promise.all`). A rate-limited routing service may
  need a concurrency limit in the provider.
- Cost arithmetic is exact integer maths up to roughly 100 requests × 200 runners per batch.
