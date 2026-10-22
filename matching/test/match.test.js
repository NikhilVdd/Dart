import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { REASON } from "../src/contract.js";
import { declineAssignment, markRunnerOffline, matchRequests } from "../src/match.js";
import { compareCandidates, scorePair } from "../src/scoring.js";
import { at, NOW, planarProvider, request, runner, store } from "./helpers.js";

const match = (requests, runners, extra = {}) =>
  matchRequests({ requests, runners, provider: extra.provider ?? planarProvider(), now: NOW, ...extra });

const byRequest = (result, id) => result.results.find(r => r.requestId === id);
const alternative = (result, requestId, runnerId) => byRequest(result, requestId).alternatives.find(a => a.runnerId === runnerId);
const pairs = result => Object.fromEntries(result.results.map(r => [r.requestId, r.runnerId]));

// Default request: store (500,0), drop-off (500,100), +6.1 min for a runner walking (0,0) → (1000,0).
// On-path request: store (300,0), drop-off (600,0), +5 min (handling only).
const onPath = (id, overrides = {}) => request(id, { stores: [store("S", 300, 0)], dropoff: [600, 0], ...overrides });
// Separate "lanes" 1 km apart: a request on one lane is far too big a detour for runners on another.
const laneRunner = (id, lane, overrides = {}) => runner(id, { start: [0, lane * 1000], dest: [1000, lane * 1000], ...overrides });
const laneRequest = (id, lane, overrides = {}) =>
  request(id, { stores: [store(`S${lane}`, 300, lane * 1000)], dropoff: [600, lane * 1000], ...overrides });

describe("matching", () => {
  test("single simple match, with score breakdown and explanation", async () => {
    const result = await match([request("Q1")], [runner("R1", { name: "Maya" })]);
    const r = byRequest(result, "Q1");
    assert.equal(r.status, "assigned");
    assert.equal(r.runnerId, "R1");
    assert.equal(r.storeId, "S");
    assert.equal(r.estimate.addedDurationMin, 6.1);
    // 6.1 added + 10 × (6.1 / 10) relative + no deadline risk (49 min of slack)
    assert.equal(r.score.total, 12.2);
    assert.equal(r.score.breakdown.deadlineRisk.points, 0);
    assert.match(r.explanation, /^R1 \(Maya\) chosen: adds 6\.1 min via Store S, score 12\.20; arrives 49 min before the .* deadline\.$/);
    assert.deepEqual(result.assignments, [{ requestId: "Q1", runnerId: "R1", storeId: "S" }]);
    assert.deepEqual(result.unmatched, []);
  });

  test("several requests compete for one runner: the request with no other option keeps it", async () => {
    // R1 is the best runner for QB (score 10 vs R2's 10.56), so a greedy best-pair-first pass would
    // give R1 to QB and leave QA with nobody. R2 can't do QA (6.1 min > its 5.5 min limit).
    const runners = [runner("R1"), runner("R2", { dest: [900, 0], max: 5.5 })];
    const requests = [request("QA"), onPath("QB")];
    for (const order of [requests, [...requests].reverse()]) {
      const result = await match(order, runners);
      assert.deepEqual(pairs(result), { QA: "R1", QB: "R2" });
      assert.match(byRequest(result, "QB").explanation, /R1 \(Runner R1\) would fit .* but is carrying QA \(item QA\), which had no other option\./);
    }
    const qb = (await match(requests, runners)).results[1];
    assert.ok(alternative({ results: [qb] }, "QB", "R1").score.total < qb.score.total, "R1 really is the better pair for QB");
  });

  test("a runner gets at most one request; the other is unmatched with the reason", async () => {
    const result = await match([request("Q1"), request("Q2", { dropoff: [500, 150] })], [runner("R1")]);
    assert.deepEqual(pairs(result), { Q1: "R1", Q2: null });
    const q2 = byRequest(result, "Q2");
    assert.equal(q2.reasonCode, REASON.RUNNERS_ASSIGNED_ELSEWHERE);
    assert.equal(alternative(result, "Q2", "R1").assignedTo, "Q1");
    assert.match(q2.explanation, /No runner for Q2 .*every eligible runner is needed for another request\. R1 .* is carrying Q1/);
  });

  test("no eligible runner: every runner is listed with why", async () => {
    const runners = [
      runner("R1", { max: 3 }),
      runner("R2", { until: 12 }),
      runner("R3", { status: "offline" }),
      runner("R4", { departs: 90 })
    ];
    const result = await match([request("Q1")], runners);
    const q1 = byRequest(result, "Q1");
    assert.equal(q1.status, "unmatched");
    assert.equal(q1.reasonCode, REASON.NO_ELIGIBLE_RUNNER);
    assert.deepEqual(q1.alternatives.map(a => [a.runnerId, a.reasonCode]), [
      ["R1", REASON.DETOUR_EXCEEDS_MAX],
      ["R2", REASON.EXCEEDS_AVAILABILITY],
      ["R3", REASON.RUNNER_OFFLINE],
      ["R4", REASON.DEPARTS_TOO_LATE]
    ]);
    assert.match(q1.explanation, /R1 \(Runner R1\) rejected: 6\.1 min detour via Store S exceeds their 3 min limit\./);
    assert.match(q1.explanation, /R2 \(Runner R2\) rejected: trip would end at .*, 4\.1 min past their .* availability\./);
    assert.match(q1.explanation, /R3 \(Runner R3\) rejected: offline\./);
    assert.match(q1.explanation, /R4 \(Runner R4\) rejected: doesn't leave until .*, after the .* deadline\./);
  });

  test("each infeasible reason surfaces as the runner's rejection", async () => {
    const result = await match([request("Q1", { by: 10.5 })], [
      runner("R1", { max: 5 }),           // detour 6.1 > 5
      runner("R2"),                        // drop-off at +11 > +10.5
      runner("R3", { status: "busy" })
    ]);
    assert.equal(alternative(result, "Q1", "R1").reasonCode, REASON.DETOUR_EXCEEDS_MAX);
    assert.equal(alternative(result, "Q1", "R2").reasonCode, REASON.MISSES_DEADLINE);
    assert.equal(alternative(result, "Q1", "R3").reasonCode, REASON.RUNNER_BUSY);
    assert.match(alternative(result, "Q1", "R2").reasonText, /would arrive at .* via Store S, 0\.5 min after the .* deadline/);
    const avail = await match([request("Q1")], [runner("R1", { until: 15 })]);
    assert.equal(alternative(avail, "Q1", "R1").reasonCode, REASON.EXCEEDS_AVAILABILITY);
  });

  test("decline, then reassignment to the next best runner without touching other assignments", async () => {
    const runners = [
      laneRunner("R1", 1), laneRunner("R2", 2), laneRunner("R3", 3),
      laneRunner("R4", 1, { departs: 5 })   // backup for lane 1, ranked below R1 (less slack)
    ];
    const requests = [laneRequest("Q1", 1, { by: 25 }), laneRequest("Q2", 2), laneRequest("Q3", 3)];
    const first = await match(requests, runners);
    assert.deepEqual(pairs(first), { Q1: "R1", Q2: "R2", Q3: "R3" });
    assert.equal(byRequest(first, "Q1").alternatives[0].runnerId, "R4", "R4 is the ranked backup");

    const second = declineAssignment(first, "Q1", "R1");
    assert.deepEqual(pairs(second), { Q1: "R4", Q2: "R2", Q3: "R3" });
    assert.deepEqual(second.changes, [{ requestId: "Q1", from: "R1", to: "R4" }]);
    assert.equal(alternative(second, "Q1", "R1").reasonCode, REASON.DECLINED);
    assert.match(byRequest(second, "Q1").explanation, /R1 \(Runner R1\) rejected: declined this request\./);
  });

  test("decline moves another assignment only when that's the only way to cover the request", async () => {
    // Q1 can use R1 or R2; Q2 can use R2 or R3 (R3 leaves too late for Q1, R1's limit is too small for Q2).
    const runners = [runner("R1"), runner("R2"), runner("R3", { departs: 10 })];
    const requests = [onPath("Q1", { by: 12 }), request("Q2")];
    runners[0].maxDetourMinutes = 5.5;
    const first = await match(requests, runners);
    assert.deepEqual(pairs(first), { Q1: "R1", Q2: "R2" });

    const second = declineAssignment(first, "Q1", "R1");
    assert.deepEqual(pairs(second), { Q1: "R2", Q2: "R3" });
    assert.deepEqual(second.changes, [
      { requestId: "Q1", from: "R1", to: "R2" },
      { requestId: "Q2", from: "R2", to: "R3" }
    ]);
  });

  test("a runner freed by a decline doesn't reshuffle assignments that still work", async () => {
    // Initially Q1→R1 (15) + Q2→R2 (12.2) beats Q1→R2 (13) + Q2→R3 (15.2).
    // After R2 declines Q2, R2 would be better for Q1 than R1, but Q1 keeps R1.
    const runners = [runner("R1", { departs: 4, max: 5.5 }), runner("R2"), runner("R3", { departs: 20 })];
    const requests = [onPath("Q1", { by: 20 }), request("Q2", { by: 40 })];
    const first = await match(requests, runners);
    assert.deepEqual(pairs(first), { Q1: "R1", Q2: "R2" });
    assert.equal(byRequest(first, "Q1").score.total, 15);
    assert.equal(alternative(first, "Q1", "R2").score.total, 13);

    const second = declineAssignment(first, "Q2", "R2");
    assert.deepEqual(pairs(second), { Q1: "R1", Q2: "R3" });
    assert.deepEqual(second.changes, [{ requestId: "Q2", from: "R2", to: "R3" }]);
    assert.match(byRequest(second, "Q1").explanation, /R2 \(Runner R2\) is free and scores better .* kept to avoid reshuffling\./);
  });

  test("decline with no backup leaves the request unmatched and the rest alone", async () => {
    const runners = [laneRunner("R1", 1), laneRunner("R2", 2)];
    const first = await match([laneRequest("Q1", 1), laneRequest("Q2", 2)], runners);
    const second = declineAssignment(first, "Q1", "R1");
    assert.deepEqual(pairs(second), { Q1: null, Q2: "R2" });
    assert.equal(byRequest(second, "Q1").reasonCode, REASON.ALL_RUNNERS_DECLINED);
    assert.deepEqual(second.unmatched.map(u => u.requestId), ["Q1"]);
    assert.match(byRequest(second, "Q1").explanation, /^No runner for Q1 .*: no backup runner after declines\./);
    // Declines stack: the next decline keeps the first.
    const third = declineAssignment(second, "Q2", "R2");
    assert.deepEqual(pairs(third), { Q1: null, Q2: null });
  });

  test("declines can also be passed up front as exclusions", async () => {
    const result = await match([request("Q1")], [runner("R1"), runner("R2")], {
      exclusions: [{ requestId: "Q1", runnerId: "R1" }]
    });
    assert.equal(byRequest(result, "Q1").runnerId, "R2");
  });

  test("overlapping assignments are prevented; back-to-back windows are fine", async () => {
    // This request's window is pickup +8 → drop-off +11.
    const overlapping = runner("R1", { commitments: [{ requestId: "Q0", pickupAt: at(5), dropoffAt: at(9) }] });
    const backToBack = runner("R2", { commitments: [{ requestId: "Q9", pickupAt: at(11), dropoffAt: at(20) }] });
    const result = await match([request("Q1")], [overlapping, backToBack]);
    assert.equal(byRequest(result, "Q1").runnerId, "R2");
    const rejected = alternative(result, "Q1", "R1");
    assert.equal(rejected.reasonCode, REASON.OVERLAPPING_ASSIGNMENT);
    assert.equal(rejected.reasonDetail.commitmentRequestId, "Q0");
    assert.match(rejected.reasonText, /already carrying Q0 .* which overlaps this pickup-to-drop-off window/);
  });

  test("multi-store requests use the best store for each runner", async () => {
    // Drop-off halfway between the two runners' paths; each store sits near one path.
    // R1 via NEAR: +10.7 min (via FAR +16.4). R2 via FAR: +11.2 min (via NEAR +17.0).
    const q = request("Q1", { stores: [store("FAR", 500, 900), store("NEAR", 400, 50)], dropoff: [500, 500] });
    const result = await match([q], [runner("R1", { max: 30 }), runner("R2", { start: [0, 1000], dest: [1000, 1000], max: 30 })]);
    const r = byRequest(result, "Q1");
    assert.equal(r.runnerId, "R1");
    assert.equal(r.storeId, "NEAR");
    assert.equal(alternative(result, "Q1", "R2").storeName, "Store FAR", "R2's best store is the one near its own path");
    assert.deepEqual(r.estimate.storeCandidates.map(c => [c.storeId, c.addedDurationMin]), [["NEAR", 10.7], ["FAR", 16.4]]);
    assert.equal(alternative(result, "Q1", "R2").addedDurationMin, 11.2);
  });

  test("impossible deadline: already passed, or too soon for anyone", async () => {
    const provider = planarProvider();
    const passed = await match([request("Q1", { by: -5 })], [runner("R1"), runner("R2")], { provider });
    assert.equal(byRequest(passed, "Q1").reasonCode, REASON.DEADLINE_PASSED);
    assert.equal(provider.calls, 0, "no routing for a request that can't be served");
    assert.match(byRequest(passed, "Q1").explanation, /the deadline has already passed.*R1 .* rejected: the .* deadline has already passed\./);

    const tooSoon = await match([request("Q1", { by: 4 })], [runner("R1"), runner("R2")]);
    assert.equal(byRequest(tooSoon, "Q1").reasonCode, REASON.NO_ELIGIBLE_RUNNER);
    assert.ok(byRequest(tooSoon, "Q1").alternatives.every(a => a.reasonCode === REASON.MISSES_DEADLINE));
  });

  test("runner going offline: their request is reassigned, everything else stays", async () => {
    const runners = [laneRunner("R1", 1), laneRunner("R2", 2), laneRunner("R3", 1, { departs: 3 })];
    const first = await match([laneRequest("Q1", 1), laneRequest("Q2", 2)], runners);
    assert.deepEqual(pairs(first), { Q1: "R1", Q2: "R2" });
    const second = markRunnerOffline(first, "R1");
    assert.deepEqual(pairs(second), { Q1: "R3", Q2: "R2" });
    assert.deepEqual(second.changes, [{ requestId: "Q1", from: "R1", to: "R3" }]);
    assert.equal(alternative(second, "Q1", "R1").reasonCode, REASON.RUNNER_OFFLINE);
    // Going offline with no backup unmatches the request.
    const third = markRunnerOffline(second, "R2");
    assert.equal(byRequest(third, "Q2").reasonCode, REASON.NO_ELIGIBLE_RUNNER);
    assert.throws(() => markRunnerOffline(third, "NOPE"), /Unknown runner/);
  });

  test("runners who are offline at the start are never routed", async () => {
    const provider = planarProvider();
    await match([request("Q1")], [runner("R1", { status: "offline" }), runner("R2")], { provider });
    assert.equal(provider.calls, 1);
  });

  test("ranking: a detour that's a smaller share of the runner's trip wins; weights come from config", async () => {
    // Both add 5 min. R1's trip is 10 min (+50%), R2's is 30 min (+17%).
    const runners = [runner("R1"), runner("R2", { dest: [3000, 0], until: 90 })];
    const result = await match([onPath("Q1")], runners);
    assert.equal(byRequest(result, "Q1").runnerId, "R2");
    assert.equal(byRequest(result, "Q1").score.breakdown.relativeDetour.points, 1.67);

    // Without the relative factor they tie on score and added distance, so the runner id decides.
    const flat = await match([onPath("Q1")], runners, { config: { scoring: { relativeDetour: 0 } } });
    assert.equal(byRequest(flat, "Q1").runnerId, "R1");
  });

  test("ranking: less slack before the deadline is riskier", async () => {
    // Same detour; R2 leaves 6 min later, so it arrives with 9 min of slack instead of 15.
    const result = await match([request("Q1", { by: 26 })], [runner("R2", { departs: 6, until: 90 }), runner("R1")]);
    assert.equal(byRequest(result, "Q1").runnerId, "R1");
    const r2 = alternative(result, "Q1", "R2").score.breakdown.deadlineRisk;
    assert.deepEqual([r2.slackMinutes, r2.shortfallMinutes, r2.points], [9, 6, 3]);
  });

  test("ties break on added distance, then runner id (R2 before R10)", async () => {
    const result = await match([request("Q1")], [runner("R10"), runner("R2")]);
    assert.equal(byRequest(result, "Q1").runnerId, "R2");
    const e = (runnerId, total, addedDistanceM) => ({ runnerId, score: { total }, estimate: { addedDistanceM } });
    assert.ok(compareCandidates(e("R9", 5, 100), e("R1", 5, 200)) < 0, "shorter added distance first");
    assert.ok(compareCandidates(e("R2", 5, 100), e("R10", 5, 100)) < 0, "then numeric-aware id");
    assert.ok(compareCandidates(e("R9", 4, 900), e("R1", 5, 0)) < 0, "score first");
  });

  test("score total is the sum of its breakdown", async () => {
    const result = await match([request("Q1", { by: 20 })], [runner("R1")]);
    const { total, breakdown } = byRequest(result, "Q1").score;
    const sum = breakdown.addedDuration.points + breakdown.relativeDetour.points + breakdown.deadlineRisk.points;
    assert.ok(Math.abs(total - sum) < 0.011);
    assert.deepEqual(scorePair(byRequest(result, "Q1").estimate, request("Q1", { by: 20 })), { total, breakdown });
  });

  test("a routing failure rejects only that runner, with the error, never a made-up estimate", async () => {
    const result = await match([request("Q1")], [runner("R1"), runner("R2", { departs: 1 })], {
      provider: planarProvider({ failFor: ["R1"] })
    });
    assert.equal(byRequest(result, "Q1").runnerId, "R2");
    const r1 = alternative(result, "Q1", "R1");
    assert.equal(r1.reasonCode, REASON.ROUTING_ERROR);
    assert.match(r1.reasonText, /routing service unavailable for R1/);
    assert.deepEqual(result.errors, [{ requestId: "Q1", runnerId: "R1", message: "routing service unavailable for R1" }]);
  });

  test("a provider returning non-numeric legs is a routing error, not a hang or a fake estimate", async () => {
    const { createDetourProvider } = await import("../src/detour.js");
    const { planarRoute } = await import("./helpers.js");
    // Broken only for runner R1's own trip (start (0,0) → destination).
    const route = async (from, to) => (from.lng === 0 && from.lat === 0 && to.lng === 1000
      ? { distanceM: 1000, durationMin: undefined, geometry: [] }
      : planarRoute(from, to));
    const provider = createDetourProvider({ name: "partial", route });
    const result = await match([request("Q1")], [runner("R1"), runner("R2", { start: [0, 50] })], { provider });
    assert.equal(byRequest(result, "Q1").runnerId, "R2");
    assert.equal(alternative(result, "Q1", "R1").reasonCode, REASON.ROUTING_ERROR);
    assert.match(alternative(result, "Q1", "R1").reasonText, /route\(\) returned an invalid leg/);

    // A hand-written provider that skips createDetourProvider() is caught by matching too.
    const raw = { name: "raw", estimateDetour: async (r, q) => ({ ...(await planarProvider().estimateDetour(r, q, { now: NOW })), addedDurationMin: NaN }) };
    const guarded = await match([request("Q1")], [runner("R1")], { provider: raw });
    assert.equal(byRequest(guarded, "Q1").reasonCode, REASON.ROUTING_ERROR);
  });

  test("when every runner's routing fails, the request says so instead of 'nobody can'", async () => {
    const result = await match([request("Q1")], [runner("R1"), runner("R2")], {
      provider: planarProvider({ failFor: ["R1", "R2"] })
    });
    assert.equal(byRequest(result, "Q1").reasonCode, REASON.ROUTING_ERROR);
    assert.match(byRequest(result, "Q1").explanation, /no runner's route could be computed/);
  });

  test("request-level problems are reported even with no runners at all", async () => {
    const result = await match([request("Q1", { by: -1 }), request("Q2", { stores: [] }), request("Q3")], []);
    assert.deepEqual(result.results.map(r => r.reasonCode),
      [REASON.DEADLINE_PASSED, REASON.NO_STORE_OPTIONS, REASON.NO_ELIGIBLE_RUNNER]);
  });

  test("an overlapping commitment rules out a store, not the runner: another store can still work", async () => {
    // Via A the window is +8 → +11 and hits the commitment; via B (farther along) it's clear.
    const busyEarly = runner("R1", { max: 20, commitments: [{ requestId: "Q0", pickupAt: at(0), dropoffAt: at(10) }] });
    const q = request("Q1", { stores: [store("A", 500, 0), store("B", 900, 0)], dropoff: [950, 0] });
    const result = await match([q], [busyEarly]);
    const r = byRequest(result, "Q1");
    assert.equal(r.runnerId, "R1");
    assert.equal(r.storeId, "B");
    assert.deepEqual(r.estimate.storeCandidates.map(c => [c.storeId, c.reasonCode]),
      [["B", null], ["A", REASON.OVERLAPPING_ASSIGNMENT]]);
  });

  test("explanations only claim reasons the solver used", async () => {
    // Q1 can use R1 or R2; Q2 can use R1, R2 or R3. Neither had a single option, so the wording
    // must not claim one, and "fewer options" isn't a reason the solver uses.
    const runners = [runner("R1"), runner("R2", { departs: 2 }), runner("R3", { departs: 20, until: 120 })];
    const result = await match([onPath("Q1", { by: 14 }), request("Q2", { by: 60 })], runners);
    const all = result.results.flatMap(r => r.explanationLines).join("\n");
    assert.doesNotMatch(all, /no other option|fewer options/);
    assert.match(all, /because the combined assignment scores better that way/);
  });

  test("every request's explanation accounts for every runner exactly once", async () => {
    const runners = [runner("R1"), runner("R2", { max: 2 }), runner("R3", { status: "offline" }), runner("R4", { departs: 5 })];
    const result = await match([request("Q1"), onPath("Q2"), request("Q3", { by: -1 })], runners);
    for (const r of result.results) {
      const lines = r.explanationLines;
      const runnerLines = r.status === "assigned" ? lines : lines.slice(1);
      assert.equal(runnerLines.length, runners.length, r.requestId);
      for (const { id } of runners) {
        assert.equal(runnerLines.filter(line => line.startsWith(`${id} `)).length, 1, `${r.requestId} mentions ${id} once`);
      }
      assert.equal(r.explanation, lines.join(" "));
    }
  });

  test("result is plain data: re-solve context isn't serialized", async () => {
    const result = await match([request("Q1")], [runner("R1")]);
    assert.ok(result.context, "context is available for declineAssignment()");
    assert.equal("context" in JSON.parse(JSON.stringify(result)), false);
    assert.equal(result.provider.name, "planar");
    assert.equal(result.now, NOW);
  });

  test("rejects invalid input with a clear message", async () => {
    await assert.rejects(match([request("X")], [runner("X")]), /Duplicate id X/);
    await assert.rejects(match([request("Q1")], [runner("R1", { status: "asleep" })]), /Runner R1: status must be one of/);
    await assert.rejects(match([{ ...request("Q1"), deliverBy: "soon" }], [runner("R1")]), /Request Q1: deliverBy must be an ISO time/);
  });
});
