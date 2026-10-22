#!/usr/bin/env node
// Runs batch matching on a scenario and prints the result. Matching code is the same for every
// provider; only the detour provider passed to matchRequests() changes.
//
// Usage (from matching/):
//   node bin/run-matching.mjs                         # scenarios/berkeley.json, simulated provider
//   node bin/run-matching.mjs --provider osrm         # real OSRM walking routes (network)
//   node bin/run-matching.mjs --provider osrm --replay test/fixtures/osrm-berkeley-foot.json   # recorded, offline
//   node bin/run-matching.mjs --mode bike             # cycling (simulated or osrm)
//   node bin/run-matching.mjs --decline Q1:R3         # then R3 declines Q1 (repeatable)
//   node bin/run-matching.mjs --offline R1            # then R1 goes offline (repeatable)
//   node bin/run-matching.mjs --scenario other.json --json

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import {
  createOsrmProvider, createReplayFetch, createSimulatedProvider, declineAssignment, DEFAULT_CONFIG,
  markRunnerOffline, matchRequests, resolveScenario
} from "../src/index.js";
import { fmtClock, fmtMin } from "../src/time.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const { values: args } = parseArgs({
  options: {
    scenario: { type: "string", default: path.join(here, "../scenarios/berkeley.json") },
    provider: { type: "string", default: "simulated" },
    mode: { type: "string", default: "foot" },
    replay: { type: "string" },
    decline: { type: "string", multiple: true, default: [] },
    offline: { type: "string", multiple: true, default: [] },
    json: { type: "boolean", default: false },
    help: { type: "boolean", short: "h", default: false }
  }
});

if (args.help) {
  console.log("Usage: node bin/run-matching.mjs [--scenario file.json] [--provider simulated|osrm] [--mode foot|bike]\n"
    + "                                [--replay recording.json] [--decline REQ:RUNNER]... [--offline RUNNER]... [--json]");
  process.exit(0);
}

function makeProvider() {
  if (args.provider === "simulated") {
    if (args.replay) throw new Error("--replay only applies to --provider osrm");
    return createSimulatedProvider({ mode: args.mode });
  }
  if (args.provider === "osrm") {
    if (!args.replay) {
      return createOsrmProvider({ mode: args.mode, headers: { "User-Agent": "dart-matching-prototype" } });
    }
    const recording = JSON.parse(fs.readFileSync(args.replay, "utf8"));
    if (recording.mode && recording.mode !== args.mode) {
      throw new Error(`${args.replay} was recorded for --mode ${recording.mode}, not ${args.mode}`);
    }
    // Replayed responses need no throttling.
    return createOsrmProvider({ mode: args.mode, baseUrl: recording.baseUrl, fetch: createReplayFetch(recording), minIntervalMs: 0, concurrency: 8 });
  }
  throw new Error(`--provider must be simulated or osrm, got "${args.provider}"`);
}

const scenario = resolveScenario(JSON.parse(fs.readFileSync(args.scenario, "utf8")));
const provider = makeProvider();
const clock = iso => fmtClock(iso, DEFAULT_CONFIG.timeZone);

let result = await matchRequests({ ...scenario, provider });
const steps = [{ title: "Initial assignment", result }];

for (const pair of args.decline) {
  const [requestId, runnerId] = pair.split(":");
  if (!requestId || !runnerId) throw new Error(`--decline expects REQ:RUNNER, got "${pair}"`);
  result = declineAssignment(result, requestId, runnerId);
  steps.push({ title: `${runnerId} declines ${requestId}`, result });
}
for (const runnerId of args.offline) {
  result = markRunnerOffline(result, runnerId);
  steps.push({ title: `${runnerId} goes offline`, result });
}

if (args.json) {
  console.log(JSON.stringify(steps.length === 1 ? result : steps, null, 2));
  process.exit(0);
}

const runnersById = new Map(scenario.runners.map(r => [r.id, r]));
const requestsById = new Map(scenario.requests.map(q => [q.id, q]));
const name = id => (runnersById.get(id)?.name ? `${id} ${runnersById.get(id).name}` : id);
const pad = (s, n) => String(s).padEnd(n);

console.log(`Dart matching · ${scenario.name} · now ${clock(scenario.now)}`);
console.log(`Provider: ${provider.name} (${provider.description})${args.replay ? `, replaying ${path.basename(args.replay)}` : ""}`);
console.log(`${scenario.runners.length} runners · ${scenario.requests.length} requests · ${scenario.stores.length} stores`);

function printStep({ title, result }, index) {
  console.log(`\n=== ${title} ${"=".repeat(Math.max(0, 70 - title.length))}`);
  if (index > 0) {
    if (result.changes.length === 0) console.log("No assignments changed.");
    for (const c of result.changes) {
      console.log(`Changed: ${c.requestId} ${c.from ? name(c.from) : "unassigned"} → ${c.to ? name(c.to) : "unassigned"}`);
    }
  }

  for (const r of result.results) {
    const request = requestsById.get(r.requestId);
    console.log(`\n${r.requestId} · ${r.item} → ${request.dropoff.label} by ${clock(request.deliverBy)}`);
    if (r.status === "assigned") {
      const e = r.estimate;
      console.log(`  ✓ ${name(r.runnerId)} via ${r.storeName}: +${fmtMin(e.addedDurationMin)} min, +${Math.round(e.addedDistanceM)} m, `
        + `pickup ${clock(e.pickupAt)}, drop-off ${clock(e.dropoffAt)} · score ${r.score.total.toFixed(2)}`);
      const b = r.score.breakdown;
      console.log(`    score = ${b.addedDuration.points} (added time) + ${b.relativeDetour.points} (relative detour) `
        + `+ ${b.deadlineRisk.points} (deadline risk)`);
    } else {
      console.log(`  ✗ unmatched: ${r.reasonCode}`);
    }
    for (const line of r.explanationLines) console.log(`    · ${line}`);
  }

  console.log("\nSummary");
  console.log(`  ${pad("Request", 26)}${pad("Runner", 14)}${pad("Store", 28)}${pad("+min", 7)}Score`);
  for (const r of result.results) {
    const label = `${r.requestId} ${r.item}`.slice(0, 25);
    if (r.status === "assigned") {
      console.log(`  ${pad(label, 26)}${pad(name(r.runnerId), 14)}${pad(r.storeName, 28)}${pad(fmtMin(r.estimate.addedDurationMin), 7)}${r.score.total.toFixed(2)}`);
    } else {
      console.log(`  ${pad(label, 26)}${pad("—", 14)}${r.reasonCode}`);
    }
  }
  if (result.errors.length) {
    console.log(`\nRouting errors: ${result.errors.length} pairs could not be routed (shown as ROUTING_ERROR above)`);
  }
}

steps.forEach(printStep);
if (provider.stats) {
  console.log(`\nRouting calls: ${provider.stats.requests} requests, ${provider.stats.cacheHits} cache hits, ${provider.stats.failures} failures`);
}
