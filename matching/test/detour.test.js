import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { REASON } from "../src/contract.js";
import { checkFeasibility, chooseStore } from "../src/detour.js";
import { at, NOW, planarProvider, request, runner, store } from "./helpers.js";

const estimate = (r, q, now = NOW) => planarProvider().estimateDetour(r, q, { now });

describe("detour estimate (shared rules)", () => {
  test("original and modified routes, added time and distance, handling time included", async () => {
    // Original (0,0)→(1000,0) = 1000 m. Modified: 500 + 100 + √(500²+100²) ≈ 1109.9 m, plus 3 + 2 min handling.
    const e = await estimate(runner("R1"), request("Q1"));
    assert.equal(e.runnerId, "R1");
    assert.equal(e.requestId, "Q1");
    assert.equal(e.storeId, "S");
    assert.deepEqual(e.original, { distanceM: 1000, durationMin: 10 });
    assert.deepEqual(e.modified, { distanceM: 1109.9, durationMin: 16.1 });
    assert.equal(e.addedDistanceM, 109.9);
    assert.equal(e.addedDurationMin, 6.1);
    assert.equal(e.feasible, true);
    assert.equal(e.reasonCode, null);
  });

  test("pickup, drop-off and trip end times follow the legs", async () => {
    const e = await estimate(runner("R1"), request("Q1"));
    assert.equal(e.pickupAt, at(5 + 3));          // 5 min to the store, 3 min shopping
    assert.equal(e.dropoffAt, at(8 + 1 + 2));     // 1 min to the drop-off, 2 min hand-off
    // Then √(500²+100²) ≈ 509.9 m to the runner's own destination.
    assert.ok(Math.abs(Date.parse(e.tripEndAt) - Date.parse(at(11 + 5.099))) < 1000);
  });

  test("a runner who already left starts from now; one leaving later starts then", async () => {
    const later = await estimate(runner("R1", { departs: 10 }), request("Q1"));
    assert.equal(later.pickupAt, at(10 + 8));
    const alreadyLeft = await estimate(runner("R1", { departs: -30 }), request("Q1"));
    assert.equal(alreadyLeft.pickupAt, at(8));
  });

  test("route geometry is returned for both routes", async () => {
    const e = await estimate(runner("R1"), request("Q1"));
    assert.deepEqual(e.geometry.original, [{ lat: 0, lng: 0 }, { lat: 0, lng: 1000 }]);
    assert.deepEqual(e.geometry.modified, [
      { lat: 0, lng: 0 }, { lat: 0, lng: 500 }, { lat: 100, lng: 500 }, { lat: 0, lng: 1000 }
    ]);
  });

  test("multi-store: picks the store with the smallest added duration and lists every option", async () => {
    const q = request("Q1", {
      stores: [store("FAR", 500, 900), store("NEAR", 400, 50), store("MID", 500, 400)],
      dropoff: [500, 100]
    });
    const e = await estimate(runner("R1", { max: 30 }), q);
    assert.equal(e.storeId, "NEAR");
    assert.deepEqual(e.storeCandidates.map(c => c.storeId), ["NEAR", "MID", "FAR"]);
    const added = e.storeCandidates.map(c => c.addedDurationMin);
    assert.deepEqual([...added].sort((a, b) => a - b), added);
    assert.equal(e.addedDurationMin, added[0]);
  });

  test("DETOUR_EXCEEDS_MAX when the added time is over the runner's limit", async () => {
    const e = await estimate(runner("R1", { max: 5 }), request("Q1"));
    assert.equal(e.feasible, false);
    assert.equal(e.reasonCode, REASON.DETOUR_EXCEEDS_MAX);
    assert.deepEqual(e.reasonDetail, { addedDurationMin: 6.1, maxDetourMinutes: 5 });
  });

  test("a detour exactly at the limit is allowed", async () => {
    // Store and drop-off on the path: only the 5 min of handling is added.
    const q = request("Q1", { stores: [store("S", 300, 0)], dropoff: [600, 0] });
    const e = await estimate(runner("R1", { max: 5 }), q);
    assert.equal(e.addedDurationMin, 5);
    assert.equal(e.feasible, true);
  });

  test("MISSES_DEADLINE when the drop-off lands after deliver-by", async () => {
    const e = await estimate(runner("R1"), request("Q1", { by: 10 }));   // drop-off at +11 min
    assert.equal(e.reasonCode, REASON.MISSES_DEADLINE);
    assert.equal(e.reasonDetail.lateByMin, 1);
    assert.equal(e.reasonDetail.deliverBy, at(10));
  });

  test("EXCEEDS_AVAILABILITY when the trip ends after the runner's availability", async () => {
    const e = await estimate(runner("R1", { until: 15 }), request("Q1"));  // trip ends at +16.1 min
    assert.equal(e.reasonCode, REASON.EXCEEDS_AVAILABILITY);
    assert.equal(e.reasonDetail.overByMin, 1.1);
  });

  test("rules are checked in order: detour, then deadline, then availability", async () => {
    const e = await estimate(runner("R1", { max: 1, until: 1 }), request("Q1", { by: 1 }));
    assert.equal(e.reasonCode, REASON.DETOUR_EXCEEDS_MAX);
    const f = await estimate(runner("R1", { until: 1 }), request("Q1", { by: 1 }));
    assert.equal(f.reasonCode, REASON.MISSES_DEADLINE);
  });

  test("NO_STORE_OPTIONS when the request lists no store", async () => {
    const e = await estimate(runner("R1"), request("Q1", { stores: [] }));
    assert.equal(e.feasible, false);
    assert.equal(e.reasonCode, REASON.NO_STORE_OPTIONS);
    assert.equal(e.storeId, null);
    assert.deepEqual(e.storeCandidates, []);
  });
});

describe("chooseStore / checkFeasibility", () => {
  const candidate = (storeId, addedDurationMin, addedDistanceM, feasible = true) =>
    ({ storeId, addedDurationMin, addedDistanceM, feasible });

  test("prefers feasible, then smallest added time, then distance, then store id", () => {
    assert.equal(chooseStore([candidate("A", 3, 100, false), candidate("B", 6, 100)]).storeId, "B");
    assert.equal(chooseStore([candidate("A", 6, 100), candidate("B", 5, 900)]).storeId, "B");
    assert.equal(chooseStore([candidate("A", 5, 200), candidate("B", 5, 100)]).storeId, "B");
    assert.equal(chooseStore([candidate("S10", 5, 100), candidate("S2", 5, 100)]).storeId, "S2");
    assert.equal(chooseStore([]), null);
  });

  test("with nothing feasible, returns the best infeasible option", () => {
    assert.equal(chooseStore([candidate("A", 9, 1, false), candidate("B", 4, 1, false)]).storeId, "B");
  });

  test("checkFeasibility returns null when every rule passes", () => {
    const r = runner("R1");
    const q = request("Q1");
    assert.equal(checkFeasibility(r, q, { addedDurationMin: 10, dropoffAt: at(60), tripEndAt: at(60) }), null);
  });
});
