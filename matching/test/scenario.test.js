import { describe, test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DEFAULT_CONFIG } from "../src/config.js";
import { distanceM } from "../src/geo.js";
import { matchRequests } from "../src/match.js";
import { createSimulatedProvider, straightLineRoute } from "../src/providers/simulated.js";
import { resolveScenario } from "../src/scenario.js";

const raw = JSON.parse(fs.readFileSync(new URL("../scenarios/berkeley.json", import.meta.url), "utf8"));
const scenario = resolveScenario(raw);
const place = key => raw.places[key];

// Transcribed from supabase/migrations/20261011000003_rpc_and_matching.sql:
// detour_minutes(S, D, P = null, Q) for a runner at store S heading to D, delivering to Q,
// before SQL's final ceil() (we report to 0.1 min instead of rounding up to whole minutes).
function sqlDetourMinutesBeforeCeil(s, d, q) {
  const walk = m => (m * 1.3) / 80;
  return walk(distanceM(s, s) + distanceM(s, q) + distanceM(q, d) - distanceM(s, d)) + 3 + 2;
}

describe("simulated provider", () => {
  test("straight line × 1.3 at 80 m/min: Moffitt → Ida Sproul", async () => {
    const leg = await straightLineRoute()(place("moffitt"), place("idasproul"));
    const straight = distanceM(place("moffitt"), place("idasproul"));
    assert.ok(straight > 760 && straight < 790, `straight-line ${straight} m`);
    assert.equal(leg.distanceM, straight * 1.3);
    assert.equal(leg.durationMin, (straight * 1.3) / 80);
    assert.ok(leg.durationMin > 12 && leg.durationMin < 13);
  });

  test("agrees with the Supabase detour_minutes() on the same points", async () => {
    const provider = createSimulatedProvider();
    const cases = [["TARGET", "unit2", "durant"], ["CVS", "durant", "idasproul"], ["TRADERJOES", "bowditch", "evans"]];
    for (const [storeId, destination, dropoff] of cases) {
      const s = scenario.stores.find(x => x.id === storeId);
      const estimate = await provider.estimateDetour(
        {
          id: "R", start: s, destination: place(destination), departsAt: raw.now, availableUntil: raw.now,
          maxDetourMinutes: 60, status: "available"
        },
        { id: "Q", storeOptions: [s], dropoff: place(dropoff), deliverBy: raw.now },
        { now: raw.now }
      );
      const sql = sqlDetourMinutesBeforeCeil(s, place(destination), place(dropoff));
      assert.ok(Math.abs(estimate.addedDurationMin - sql) <= 0.05, `${storeId}: ${estimate.addedDurationMin} vs SQL ${sql}`);
    }
  });

  test("uses no network", async () => {
    const realFetch = globalThis.fetch;
    globalThis.fetch = () => { throw new Error("network used"); };
    try {
      const result = await matchRequests({ ...scenario, provider: createSimulatedProvider() });
      assert.ok(result.results.length > 0);
    } finally {
      globalThis.fetch = realFetch;
    }
  });

  test("config changes the travel model", async () => {
    const fast = createSimulatedProvider({ config: { ...DEFAULT_CONFIG, travel: { roadFactor: 1, metersPerMinute: 100 } } });
    assert.match(fast.description, /× 1 at 100 m\/min/);
  });
});

describe("Berkeley scenario", () => {
  test("has the required size and a multi-store request", () => {
    assert.ok(scenario.runners.length >= 10);
    assert.ok(scenario.requests.length >= 5);
    assert.ok(scenario.stores.length >= 6);
    assert.ok(scenario.requests.some(q => q.storeOptions.length >= 2));
    for (const p of [...scenario.stores, ...Object.values(raw.places)]) {
      assert.ok(p.lat > 37.85 && p.lat < 37.88 && p.lng > -122.28 && p.lng < -122.24, `${p.name ?? p.label} is near campus`);
    }
  });

  test("runs end to end: every request is assigned or has a reason, no runner used twice", async () => {
    const result = await matchRequests({ ...scenario, provider: createSimulatedProvider() });
    for (const r of result.results) {
      if (r.status === "assigned") assert.ok(r.runnerId && r.estimate.feasible && r.score);
      else assert.ok(r.reasonCode, `${r.requestId} has a reason`);
      assert.ok(r.explanation.length > 0);
    }
    const used = result.assignments.map(a => a.runnerId);
    assert.equal(new Set(used).size, used.length);
  });

  test("expected outcome", async () => {
    const result = await matchRequests({ ...scenario, provider: createSimulatedProvider() });
    const outcome = Object.fromEntries(result.results.map(r => [r.requestId, r.runnerId ?? r.reasonCode]));
    assert.deepEqual(outcome, {
      Q1: "R5",                      // charger: three stores, Target is best for Sam
      Q2: "R3",
      Q3: "R8",
      Q4: "R9",                      // Kai would fit but is mid-delivery (overlap)
      Q5: "R2",                      // Jordan is Q5's only option, so Q1/Q2 go to others
      Q6: "NO_ELIGIBLE_RUNNER"       // 15-minute deadline across town
    });
    const q1 = result.results.find(r => r.requestId === "Q1");
    assert.equal(q1.storeId, "TARGET");
    const kai = result.results.find(r => r.requestId === "Q4").alternatives.find(a => a.runnerId === "R11");
    assert.equal(kai.reasonCode, "OVERLAPPING_ASSIGNMENT");
  });

  test("is deterministic", async () => {
    const a = await matchRequests({ ...scenario, provider: createSimulatedProvider() });
    const b = await matchRequests({ ...scenario, provider: createSimulatedProvider() });
    assert.deepEqual(JSON.parse(JSON.stringify(a)), JSON.parse(JSON.stringify(b)));
  });

  test("unknown references fail loudly", () => {
    assert.throws(() => resolveScenario({ ...raw, requests: [{ ...raw.requests[0], storeOptions: ["NOPE"] }] }), /unknown store "NOPE"/);
    assert.throws(() => resolveScenario({ ...raw, runners: [{ ...raw.runners[0], start: "nowhere" }] }), /unknown place "nowhere"/);
  });
});
