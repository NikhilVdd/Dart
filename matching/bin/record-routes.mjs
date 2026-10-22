#!/usr/bin/env node
// Routes every leg a scenario needs through the live OSRM servers and saves the responses, so tests
// and offline demos can replay real routes without the network.
//
// Usage (from matching/, needs network):
//   node bin/record-routes.mjs                                   # foot, Berkeley → test/fixtures/osrm-berkeley-foot.json
//   node bin/record-routes.mjs --mode bike --out test/fixtures/osrm-berkeley-bike.json

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { matchRequests, resolveScenario } from "../src/index.js";
import { createOsrmProvider, OSRM_DEFAULT_BASE_URL } from "../src/providers/osrm.js";
import { createRecordingFetch } from "../src/providers/recording.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const { values: args } = parseArgs({
  options: {
    scenario: { type: "string", default: path.join(here, "../scenarios/berkeley.json") },
    mode: { type: "string", default: "foot" },
    out: { type: "string" },
    "base-url": { type: "string", default: OSRM_DEFAULT_BASE_URL },
    // The free servers block clients that go faster than about one request a second.
    "interval-ms": { type: "string", default: "1500" }
  }
});

const out = args.out ?? path.join(here, `../test/fixtures/osrm-berkeley-${args.mode}.json`);
const scenario = resolveScenario(JSON.parse(fs.readFileSync(args.scenario, "utf8")));
// The provider pauses itself after 3 refused requests in a row, so a blocked IP isn't hammered.
const recorder = createRecordingFetch();
const provider = createOsrmProvider({
  mode: args.mode,
  baseUrl: args["base-url"],
  fetch: recorder.fetch,
  minIntervalMs: Number(args["interval-ms"]),
  timeoutMs: 30000,
  headers: { "User-Agent": "dart-matching-prototype (route recording)" }
});

const result = await matchRequests({ ...scenario, provider });
if (result.errors.length) {
  console.error(`${result.errors.length} pairs failed to route; not saving a partial recording:`);
  for (const e of result.errors.slice(0, 5)) console.error(`  ${e.requestId} × ${e.runnerId}: ${e.message}`);
  process.exit(1);
}

const recording = {
  recordedAt: new Date().toISOString(),
  baseUrl: args["base-url"],
  mode: args.mode,
  scenario: path.basename(args.scenario),
  responses: Object.fromEntries(Object.entries(recorder.responses).sort(([a], [b]) => a.localeCompare(b)))
};
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, `${JSON.stringify(recording)}\n`);
console.log(`Recorded ${Object.keys(recording.responses).length} legs (${provider.stats.requests} requests, `
  + `${provider.stats.cacheHits} cache hits) → ${path.relative(process.cwd(), out)}`);
