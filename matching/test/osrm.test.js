import { describe, test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { REASON } from "../src/contract.js";
import { matchRequests } from "../src/match.js";
import {
  createLimiter, createOsrmProvider, osrmRoute, osrmUrl, parseOsrmRoute, RoutingError
} from "../src/providers/osrm.js";
import { createRecordingFetch, createReplayFetch } from "../src/providers/recording.js";
import { createSimulatedProvider } from "../src/providers/simulated.js";
import { resolveScenario } from "../src/scenario.js";

const MOFFITT = { lat: 37.8726, lng: -122.2607 };
const IDA_SPROUL = { lat: 37.8675, lng: -122.2547 };
const okBody = (distance, duration, coordinates = [[MOFFITT.lng, MOFFITT.lat], [IDA_SPROUL.lng, IDA_SPROUL.lat]]) =>
  ({ code: "Ok", routes: [{ distance, duration, geometry: { type: "LineString", coordinates } }] });

/** A fake fetch: `respond(url)` returns { status, body } or throws. Records every URL it sees. */
function fakeFetch(respond) {
  const fetch = async (url, init) => {
    fetch.urls.push(url);
    const { status = 200, body, headers = {} } = await respond(url, init);
    return {
      ok: status >= 200 && status < 300,
      status,
      headers: { get: name => headers[name.toLowerCase()] ?? null },
      json: async () => (typeof body === "string" ? JSON.parse(body) : body)
    };
  };
  fetch.urls = [];
  return fetch;
}

// No throttling in unit tests.
const fast = { minIntervalMs: 0, retryDelayMs: 1 };

const fixtureUrl = new URL("./fixtures/osrm-berkeley-foot.json", import.meta.url);
// Recorded with `node bin/record-routes.mjs`; required, so these tests fail (not skip) without it.
let recordingCache = null;
const loadRecording = () => (recordingCache ??= JSON.parse(fs.readFileSync(fixtureUrl, "utf8")));
const scenario = resolveScenario(JSON.parse(fs.readFileSync(new URL("../scenarios/berkeley.json", import.meta.url), "utf8")));
const replayProvider = () => {
  const recording = loadRecording();
  return createOsrmProvider({ fetch: createReplayFetch(recording), baseUrl: recording.baseUrl, ...fast, concurrency: 8 });
};

describe("OSRM routing provider", () => {
  test("builds walking and cycling URLs with lng,lat order", () => {
    assert.equal(
      osrmUrl({ from: MOFFITT, to: IDA_SPROUL }),
      "https://routing.openstreetmap.de/routed-foot/route/v1/foot/-122.260700,37.872600;-122.254700,37.867500?overview=full&geometries=geojson&steps=false"
    );
    assert.match(osrmUrl({ from: MOFFITT, to: IDA_SPROUL, mode: "bike", baseUrl: "http://localhost:5000/" }),
      /^http:\/\/localhost:5000\/routed-bike\/route\/v1\/bike\/-122\.260700,37\.872600;/);
    assert.throws(() => osrmUrl({ from: MOFFITT, to: IDA_SPROUL, mode: "car" }), /Unknown travel mode "car"/);
    assert.throws(() => createOsrmProvider({ mode: "car" }), /Unknown travel mode/);
  });

  test("parses a route: metres, seconds → minutes, GeoJSON [lng, lat] → { lat, lng }", () => {
    const leg = parseOsrmRoute(okBody(1030.4, 822));
    assert.equal(leg.distanceM, 1030.4);
    assert.equal(leg.durationMin, 13.7);
    assert.deepEqual(leg.geometry[0], MOFFITT);
    assert.deepEqual(leg.geometry[1], IDA_SPROUL);
  });

  test("a zero-length leg (runner already at the store) needs no request", async () => {
    const fetch = fakeFetch(() => { throw new Error("should not be called"); });
    const leg = await osrmRoute({ fetch, ...fast })(MOFFITT, { ...MOFFITT });
    assert.deepEqual([leg.distanceM, leg.durationMin], [0, 0]);
    assert.equal(fetch.urls.length, 0);
  });

  test("identical legs are fetched once per run, including concurrent requests", async () => {
    const fetch = fakeFetch(() => ({ body: okBody(1000, 720) }));
    const stats = { requests: 0, cacheHits: 0, failures: 0 };
    const route = osrmRoute({ fetch, stats, ...fast, concurrency: 4 });
    const legs = await Promise.all([route(MOFFITT, IDA_SPROUL), route(MOFFITT, IDA_SPROUL), route(MOFFITT, IDA_SPROUL)]);
    await route(MOFFITT, IDA_SPROUL);
    assert.equal(fetch.urls.length, 1);
    assert.deepEqual(stats, { requests: 1, cacheHits: 3, failures: 0 });
    assert.ok(legs.every(leg => leg.durationMin === 12));
    await route(IDA_SPROUL, MOFFITT);   // reverse direction is a different leg
    assert.equal(fetch.urls.length, 2);
  });

  test("a failed leg isn't cached, so a later call retries it", async () => {
    let calls = 0;
    const fetch = fakeFetch(() => (++calls === 1 ? { status: 500, body: {} } : { body: okBody(1000, 720) }));
    const route = osrmRoute({ fetch, ...fast, retries: 0 });
    await assert.rejects(route(MOFFITT, IDA_SPROUL), RoutingError);
    assert.equal((await route(MOFFITT, IDA_SPROUL)).durationMin, 12);
  });

  test("rate limiting (429) is retried with backoff, then reported if it persists", async () => {
    let calls = 0;
    const flaky = fakeFetch(() => (++calls < 3 ? { status: 429, body: {}, headers: { "retry-after": "0" } } : { body: okBody(500, 360) }));
    assert.equal((await osrmRoute({ fetch: flaky, ...fast, retries: 2 })(MOFFITT, IDA_SPROUL)).durationMin, 6);
    assert.equal(flaky.urls.length, 3);

    const limited = fakeFetch(() => ({ status: 429, body: {} }));
    await assert.rejects(osrmRoute({ fetch: limited, ...fast, retries: 1 })(MOFFITT, IDA_SPROUL),
      error => error instanceof RoutingError && error.status === 429 && /HTTP 429 \(rate limited\)/.test(error.message));
    assert.equal(limited.urls.length, 2);
  });

  test("every kind of failure is a clear RoutingError, never a made-up leg", async () => {
    const cases = [
      [() => ({ status: 503, body: {} }), /HTTP 503/],
      [() => ({ body: { code: "NoRoute", message: "Impossible route between points" } }), /could not route this leg \(NoRoute: Impossible route/],
      [() => ({ body: { code: "Ok", routes: [] } }), /returned no route/],
      [() => ({ body: { code: "Ok", routes: [{ distance: null, duration: 10 }] } }), /without a valid distance/],
      [() => ({ body: "{not json" }), /invalid JSON/],
      [() => { throw new TypeError("fetch failed"); }, /could not reach the routing service \(fetch failed\)/]
    ];
    for (const [respond, message] of cases) {
      await assert.rejects(osrmRoute({ fetch: fakeFetch(respond), ...fast, retries: 0 })(MOFFITT, IDA_SPROUL),
        error => error instanceof RoutingError && message.test(error.message), String(message));
    }
  });

  test("a request that hangs times out", async () => {
    const hanging = fakeFetch((url, { signal }) => new Promise((_, reject) => {
      signal.addEventListener("abort", () => reject(new Error("aborted")));
    }));
    await assert.rejects(osrmRoute({ fetch: hanging, ...fast, timeoutMs: 20 })(MOFFITT, IDA_SPROUL), /timed out after 20 ms/);
  });

  test("a response whose body never arrives still times out", async () => {
    const stalled = fakeFetch(() => ({ body: null }));
    const fetch = async (url, init) => ({ ...(await stalled(url, init)), json: () => new Promise(() => {}) });
    await assert.rejects(osrmRoute({ fetch, ...fast, timeoutMs: 30 })(MOFFITT, IDA_SPROUL), /timed out after 30 ms/);
  });

  test("after repeated refusals, routing pauses and fails fast instead of hammering the server", async () => {
    const refusing = fakeFetch(() => ({ status: 503, body: {} }));
    const route = osrmRoute({ fetch: refusing, ...fast, retries: 0, breakerThreshold: 3, breakerCooldownMs: 60000 });
    const legs = [[0.000, 0.001], [0.002, 0.003], [0.004, 0.005], [0.006, 0.007], [0.008, 0.009]]
      .map(([a, b]) => route({ lat: 37.87 + a, lng: -122.26 }, { lat: 37.87 + b, lng: -122.25 }).catch(e => e));
    const errors = await Promise.all(legs);
    assert.equal(refusing.urls.length, 3, "only 3 requests reach the server");
    assert.ok(errors.slice(0, 3).every(e => /HTTP 503/.test(e.message)));
    assert.ok(errors.slice(3).every(e => e instanceof RoutingError && /routing paused for \d+ s after 3 failed requests in a row/.test(e.message)));
  });

  test("the pause lifts after the cooldown, and a success resets the count", async () => {
    let refuse = true;
    const fetch = fakeFetch(() => (refuse ? { status: 503, body: {} } : { body: okBody(500, 360) }));
    const route = osrmRoute({ fetch, ...fast, retries: 0, breakerThreshold: 1, breakerCooldownMs: 20 });
    await assert.rejects(route(MOFFITT, IDA_SPROUL), /HTTP 503/);
    await assert.rejects(route(MOFFITT, IDA_SPROUL), /routing paused/);
    await new Promise(resolve => setTimeout(resolve, 30));
    refuse = false;
    assert.equal((await route(MOFFITT, IDA_SPROUL)).durationMin, 6);
  });

  test("a leg OSRM can't route is remembered for the run, not asked again", async () => {
    const fetch = fakeFetch(() => ({ body: { code: "NoRoute" } }));
    const route = osrmRoute({ fetch, ...fast });
    await assert.rejects(route(MOFFITT, IDA_SPROUL), /NoRoute/);
    await assert.rejects(route(MOFFITT, IDA_SPROUL), /NoRoute/);
    assert.equal(fetch.urls.length, 1);
  });

  test("a long Retry-After fails the leg instead of stalling the run", async () => {
    const fetch = fakeFetch(() => ({ status: 429, body: {}, headers: { "retry-after": "3600" } }));
    const started = Date.now();
    await assert.rejects(osrmRoute({ fetch, ...fast, maxRetryAfterMs: 30000 })(MOFFITT, IDA_SPROUL),
      /rate limiting; it asked to wait 3600 s/);
    assert.ok(Date.now() - started < 1000);
  });

  test("retries wait their turn too: every request, retry or not, is spaced", async () => {
    const starts = [];
    let first = true;
    const fetch = fakeFetch(url => {
      starts.push(Date.now());
      if (first && url.includes("-122.254700,37.867500")) { first = false; return { status: 503, body: {} }; }
      return { body: okBody(500, 360) };
    });
    const route = osrmRoute({ fetch, minIntervalMs: 40, retryDelayMs: 1 });
    await Promise.all([route(MOFFITT, IDA_SPROUL), route(IDA_SPROUL, MOFFITT)]);
    assert.equal(starts.length, 3);
    for (let i = 1; i < starts.length; i++) assert.ok(starts[i] - starts[i - 1] >= 35, `gap ${starts[i] - starts[i - 1]} ms`);
  });

  test("throttling settings are validated, so a typo can't switch throttling off", () => {
    assert.throws(() => osrmRoute({ fetch: async () => {}, minIntervalMs: Number("1.5s") }), /minIntervalMs must be a number ≥ 0/);
    assert.throws(() => osrmRoute({ fetch: async () => {}, minIntervalMs: -1 }), /minIntervalMs/);
    assert.throws(() => createLimiter(1, NaN), /minIntervalMs/);
    assert.throws(() => osrmRoute({ fetch: async () => {}, timeoutMs: 0 }), /timeoutMs/);
  });

  test("cached legs can't be changed by a caller", async () => {
    const route = osrmRoute({ fetch: fakeFetch(() => ({ body: okBody(1000, 720) })), ...fast });
    const leg = await route(MOFFITT, IDA_SPROUL);
    assert.throws(() => { leg.durationMin = 1; }, TypeError);
    assert.throws(() => leg.geometry.reverse(), TypeError);
    assert.equal((await route(MOFFITT, IDA_SPROUL)).durationMin, 12);
  });

  test("the limiter caps requests in flight and spaces their starts", async () => {
    const limit = createLimiter(2, 15);
    let active = 0;
    let peak = 0;
    const starts = [];
    const task = async () => {
      starts.push(Date.now());
      peak = Math.max(peak, ++active);
      await new Promise(resolve => setTimeout(resolve, 5));
      active--;
    };
    await Promise.all(Array.from({ length: 5 }, () => limit(task)));
    assert.ok(peak <= 2, `peak ${peak}`);
    for (let i = 1; i < starts.length; i++) assert.ok(starts[i] - starts[i - 1] >= 14, `starts are spaced (gap ${starts[i] - starts[i - 1]} ms)`);
  });

  test("a routing failure in matching rejects only the affected pairs, with the error", async () => {
    // Every leg ending at Unit 2 fails; everything else routes.
    const unit2 = "-122.255500,37.866000";
    const fetch = fakeFetch(url => (url.includes(`;${unit2}`) ? { status: 502, body: {} } : { body: okBody(400, 300) }));
    // The breaker is tested on its own above; here it's kept out of the way so only the bad legs fail.
    const result = await matchRequests({ ...scenario, provider: createOsrmProvider({ fetch, ...fast, retries: 0, concurrency: 8, breakerThreshold: 1000 }) });
    assert.ok(result.errors.length > 0);
    assert.ok(result.errors.every(e => /HTTP 502/.test(e.message)));
    for (const r of result.results) {
      for (const a of r.alternatives.filter(x => x.reasonCode === REASON.ROUTING_ERROR)) assert.match(a.reasonText, /HTTP 502/);
      if (r.status === "assigned") assert.ok(r.estimate.feasible);
    }
  });
});

describe("OSRM provider on recorded Berkeley routes (offline)", () => {
  test("the recording covers the whole scenario and nothing reaches the network", async () => {
    const realFetch = globalThis.fetch;
    globalThis.fetch = () => { throw new Error("network used"); };
    try {
      const result = await matchRequests({ ...scenario, provider: replayProvider() });
      assert.deepEqual(result.errors, []);
    } finally {
      globalThis.fetch = realFetch;
    }
  });

  test("estimates have exactly the shared contract's fields, same as the simulated provider", async () => {
    const [runner] = scenario.runners;
    const request = scenario.requests[0];
    const real = await replayProvider().estimateDetour(runner, request, { now: scenario.now });
    const simulated = await createSimulatedProvider().estimateDetour(runner, request, { now: scenario.now });
    assert.deepEqual(Object.keys(real).sort(), Object.keys(simulated).sort());
    assert.deepEqual(Object.keys(real.storeCandidates[0]).sort(), Object.keys(simulated.storeCandidates[0]).sort());
    assert.equal(real.storeCandidates.length, request.storeOptions.length);
    assert.ok(real.geometry.modified.length > simulated.geometry.modified.length, "real streets, not straight lines");
    assert.ok(real.modified.durationMin > 0 && real.original.distanceM > 0);
  });

  test("real routes: added = modified − original, and pickup/drop-off times follow the legs", async () => {
    const result = await matchRequests({ ...scenario, provider: replayProvider() });
    for (const r of result.results.filter(x => x.status === "assigned")) {
      const e = r.estimate;
      assert.ok(Math.abs(e.addedDurationMin - (e.modified.durationMin - e.original.durationMin)) <= 0.11, r.requestId);
      assert.ok(Math.abs(e.addedDistanceM - (e.modified.distanceM - e.original.distanceM)) <= 0.11, r.requestId);
      assert.ok(Date.parse(e.pickupAt) < Date.parse(e.dropoffAt) && Date.parse(e.dropoffAt) <= Date.parse(e.tripEndAt), "drop-off at the runner's own destination ends the trip");
    }
  });

  test("matching runs end to end and is deterministic; every request is assigned or explained", async () => {
    const a = await matchRequests({ ...scenario, provider: replayProvider() });
    const b = await matchRequests({ ...scenario, provider: replayProvider() });
    assert.deepEqual(JSON.parse(JSON.stringify(a)), JSON.parse(JSON.stringify(b)));
    assert.equal(a.provider.name, "osrm");
    for (const r of a.results) assert.ok(r.status === "assigned" || r.reasonCode, r.requestId);
    const used = a.assignments.map(x => x.runnerId);
    assert.equal(new Set(used).size, used.length);
  });

  test("real walking is slower than the straight-line estimate on campus", async () => {
    const [runner] = scenario.runners;
    const real = await replayProvider().estimateDetour(runner, scenario.requests[0], { now: scenario.now });
    const simulated = await createSimulatedProvider().estimateDetour(runner, scenario.requests[0], { now: scenario.now });
    assert.ok(real.original.distanceM > simulated.original.distanceM * 0.9);
  });

  test("record → replay round trip", async () => {
    const live = fakeFetch(() => ({ body: { ...okBody(800, 600), waypoints: [{ name: "dropped" }] } }));
    const recorder = createRecordingFetch(live);
    const provider = createOsrmProvider({ fetch: recorder.fetch, ...fast });
    await provider.estimateDetour(scenario.runners[1], scenario.requests[1], { now: scenario.now });
    const urls = Object.keys(recorder.responses);
    assert.equal(urls.length, live.urls.length);
    assert.equal(recorder.responses[urls[0]].waypoints, undefined, "recordings keep only what's needed");
    const replayed = createOsrmProvider({ fetch: createReplayFetch({ responses: recorder.responses }), ...fast });
    const again = await replayed.estimateDetour(scenario.runners[1], scenario.requests[1], { now: scenario.now });
    assert.equal(again.addedDurationMin, (await provider.estimateDetour(scenario.runners[1], scenario.requests[1], { now: scenario.now })).addedDurationMin);
    await assert.rejects(createReplayFetch({ responses: {} })("https://example.test/x"), /no recorded response/);
  });
});

describe("CLI provider switch", () => {
  const bin = fileURLToPath(new URL("../bin/run-matching.mjs", import.meta.url));
  const run = (...args) => execFileSync(process.execPath, [bin, ...args], { encoding: "utf8" });

  test("--provider simulated (default) and --provider osrm --replay use the same matching", () => {
    const simulated = run();
    assert.match(simulated, /Provider: simulated/);
    const real = run("--provider", "osrm", "--replay", fileURLToPath(fixtureUrl));
    assert.match(real, /Provider: osrm \(OSRM walking routes .*\), replaying osrm-berkeley-foot\.json/);
    assert.match(real, /Summary/);
    assert.match(real, /Routing calls: \d+ requests, \d+ cache hits, 0 failures/);
  });

  test("--mode bike changes the travel model", () => {
    assert.match(run("--mode", "bike"), /at 250 m\/min/);
    assert.throws(() => run("--provider", "teleport"), /--provider must be simulated or osrm/);
  });
});
