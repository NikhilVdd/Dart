#!/usr/bin/env node
// Runs batch matching on a scenario with the simulated detour provider and prints the result.
//
// Usage (from matching/):
//   node bin/run-matching.mjs                         # scenarios/berkeley.json
//   node bin/run-matching.mjs --decline Q1:R3         # then R3 declines Q1 (repeatable)
//   node bin/run-matching.mjs --offline R1            # then R1 goes offline (repeatable)
//   node bin/run-matching.mjs --scenario other.json --json

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import {
  createSimulatedProvider, declineAssignment, DEFAULT_CONFIG, markRunnerOffline, matchRequests, resolveScenario
} from "../src/index.js";
import { fmtClock, fmtMin } from "../src/time.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const { values: args } = parseArgs({
  options: {
    scenario: { type: "string", default: path.join(here, "../scenarios/berkeley.json") },
    decline: { type: "string", multiple: true, default: [] },
    offline: { type: "string", multiple: true, default: [] },
    json: { type: "boolean", default: false },
    help: { type: "boolean", short: "h", default: false }
  }
});

if (args.help) {
  console.log("Usage: node bin/run-matching.mjs [--scenario file.json] [--decline REQ:RUNNER]... [--offline RUNNER]... [--json]");
  process.exit(0);
}

const scenario = resolveScenario(JSON.parse(fs.readFileSync(args.scenario, "utf8")));
const provider = createSimulatedProvider();
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
console.log(`Provider: ${provider.name} (${provider.description})`);
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
  if (result.errors.length) console.log(`\nRouting errors: ${result.errors.length}`);
}

steps.forEach(printStep);
