// Batch matching: requests × runners → one runner per request, with reasons for everything.
//
// 1. Ask the provider for a DetourEstimate per pair (skipping pairs ruled out without routing).
// 2. Decide eligibility per pair, recording a reason code for every rejection.
// 3. Score eligible pairs (scoring.js) and solve the whole assignment at once (assignment.js):
//    as many requests served as possible, then the lowest total score.
// 4. Explain every request's outcome (explain.js).
//
// declineAssignment() and markRunnerOffline() re-solve from the cached estimates, keeping every
// other assignment unless moving one is the only way to cover the affected request.

import { compareIds, REASON, validateRequest, validateRunner } from "./contract.js";
import { resolveConfig } from "./config.js";
import { solveAssignment } from "./assignment.js";
import { compareCandidates, scorePair } from "./scoring.js";
import { explainRequest, reasonText } from "./explain.js";
import { toMs } from "./time.js";

const pairKey = (requestId, runnerId) => `${requestId}\u0000${runnerId}`;

/** A request-level problem that no runner can fix. */
function requestProblem(request, now) {
  if (!request.storeOptions.length) return { reasonCode: REASON.NO_STORE_OPTIONS, reasonDetail: null };
  if (now && toMs(request.deliverBy) <= toMs(now)) {
    return { reasonCode: REASON.DEADLINE_PASSED, reasonDetail: { deliverBy: request.deliverBy } };
  }
  return null;
}

/** Problems known without routing. Status is checked at solve time because it can change. */
function staticRunnerProblem(request, runner) {
  if (toMs(runner.departsAt) > toMs(request.deliverBy)) {
    return {
      reasonCode: REASON.DEPARTS_TOO_LATE,
      reasonDetail: { departsAt: runner.departsAt, deliverBy: request.deliverBy }
    };
  }
  return null;
}

function statusProblem(runner) {
  if (runner.status === "offline") return { reasonCode: REASON.RUNNER_OFFLINE, reasonDetail: null };
  if (runner.status === "busy") return { reasonCode: REASON.RUNNER_BUSY, reasonDetail: null };
  return null;
}

async function estimatePairs({ requests, runners, provider, now }) {
  const estimates = new Map();
  const jobs = [];
  for (const request of requests) {
    if (requestProblem(request, now)) continue;
    for (const runner of runners) {
      // Runners who are offline or busy now aren't routed; markRunnerOffline() only removes runners.
      if (statusProblem(runner) || staticRunnerProblem(request, runner)) continue;
      jobs.push(
        provider.estimateDetour(runner, request, { now })
          .then(estimate => estimates.set(pairKey(request.id, runner.id), { estimate }))
          .catch(error => estimates.set(pairKey(request.id, runner.id), { error }))
      );
    }
  }
  await Promise.all(jobs);
  return estimates;
}

function evaluatePair(ctx, request, runner) {
  const base = { requestId: request.id, runnerId: runner.id, eligible: false, estimate: null, score: null };
  const reject = (problem, estimate = null) => ({ ...base, ...problem, estimate });

  const reqProblem = requestProblem(request, ctx.now);
  if (reqProblem) return reject(reqProblem);
  if (ctx.exclusions.has(pairKey(request.id, runner.id))) return reject({ reasonCode: REASON.DECLINED, reasonDetail: null });
  const status = statusProblem(runner);
  if (status) return reject(status);
  const late = staticRunnerProblem(request, runner);
  if (late) return reject(late);

  const cached = ctx.estimates.get(pairKey(request.id, runner.id));
  if (!cached) {
    // Only reachable if a runner became available after the batch was estimated.
    return reject({ reasonCode: REASON.ROUTING_ERROR, reasonDetail: { message: "no estimate for this pair" } });
  }
  if (cached.error) {
    return reject({ reasonCode: REASON.ROUTING_ERROR, reasonDetail: { message: cached.error.message ?? String(cached.error) } });
  }
  const { estimate } = cached;
  if (!estimate.feasible) return reject({ reasonCode: estimate.reasonCode, reasonDetail: estimate.reasonDetail }, estimate);

  // A provider not built with createDetourProvider() could still return unusable numbers.
  const score = scorePair(estimate, request, ctx.config);
  if (!Number.isFinite(score.total) || Number.isNaN(toMs(estimate.dropoffAt))) {
    return reject({ reasonCode: REASON.ROUTING_ERROR, reasonDetail: { message: "provider returned a non-numeric estimate" } });
  }

  return { ...base, eligible: true, reasonCode: null, reasonDetail: null, estimate, score };
}

function unmatchedReason(request, evaluations, now) {
  const problem = requestProblem(request, now);
  if (problem) return problem.reasonCode;
  if (evaluations.some(e => e.eligible)) return REASON.RUNNERS_ASSIGNED_ELSEWHERE;
  const codes = new Set(evaluations.map(e => e.reasonCode));
  if (codes.has(REASON.DECLINED)) return REASON.ALL_RUNNERS_DECLINED;
  // Every runner failed to route: an outage, not proof that nobody could do it.
  if (codes.size === 1 && codes.has(REASON.ROUTING_ERROR)) return REASON.ROUTING_ERROR;
  return REASON.NO_ELIGIBLE_RUNNER;
}

function solve(ctx) {
  const { requests, runners, config, previous } = ctx;
  const n = requests.length;
  const m = runners.length;

  // evaluations[i][j]: request i × runner j
  const evaluations = requests.map(request => runners.map(runner => evaluatePair(ctx, request, runner)));
  const ranked = evaluations.map(row => row.filter(e => e.eligible).sort(compareCandidates));

  // Integer costs: rounded score, with the candidate's rank as a tie-break that can never outweigh
  // a real score difference (ranks summed over all requests stay below one score unit).
  const tieScale = n * m + 1;
  const base = ranked.map(list => new Map(list.map((e, rank) => [
    e.runnerId,
    Math.round(e.score.total * config.scorePrecision) * tieScale + rank
  ])));

  // When re-solving, keeping an existing pair is worth more than any score improvement, but less
  // than covering one more request (solveAssignment's unassigned cost is always larger).
  let stability = 0;
  if (previous) {
    for (const costs of base) stability += Math.max(0, ...costs.values());
    stability = 2 * stability + 1;
  }

  const costs = requests.map((request, i) => runners.map(runner => {
    const cost = base[i].get(runner.id);
    if (cost === undefined) return null;
    return previous?.get(request.id) === runner.id ? cost - stability : cost;
  }));
  const columns = solveAssignment(costs);

  const assignedTo = new Map();  // runnerId → requestId
  columns.forEach((col, i) => { if (col >= 0) assignedTo.set(runners[col].id, requests[i].id); });

  const runnersById = new Map(runners.map(r => [r.id, r]));
  const requestsById = new Map(requests.map(q => [q.id, q]));
  const eligibleCounts = new Map(requests.map((q, i) => [q.id, ranked[i].length]));

  const results = requests.map((request, i) => {
    const chosen = columns[i] >= 0 ? ranked[i].find(e => e.runnerId === runners[columns[i]].id) : null;
    const eligible = ranked[i].filter(e => e !== chosen);
    const rejected = evaluations[i].filter(e => !e.eligible).sort((a, b) => compareIds(a.runnerId, b.runnerId));
    const reason = chosen ? null : unmatchedReason(request, evaluations[i], ctx.now);
    const lines = explainRequest({
      request, chosen, unmatchedReason: reason, eligible, rejected, assignedTo,
      requestsById, eligibleCounts, runnersById, config, previous
    });

    return {
      requestId: request.id,
      item: request.item,
      status: chosen ? "assigned" : "unmatched",
      runnerId: chosen?.runnerId ?? null,
      runnerName: chosen ? runnersById.get(chosen.runnerId).name ?? null : null,
      storeId: chosen?.estimate.storeId ?? null,
      storeName: chosen?.estimate.storeName ?? null,
      estimate: chosen?.estimate ?? null,
      score: chosen?.score ?? null,
      reasonCode: reason,
      alternatives: [
        ...eligible.map(e => ({
          runnerId: e.runnerId,
          runnerName: runnersById.get(e.runnerId).name ?? null,
          eligible: true,
          score: e.score,
          storeName: e.estimate.storeName,
          addedDurationMin: e.estimate.addedDurationMin,
          addedDistanceM: e.estimate.addedDistanceM,
          assignedTo: assignedTo.get(e.runnerId) ?? null
        })),
        ...rejected.map(e => ({
          runnerId: e.runnerId,
          runnerName: runnersById.get(e.runnerId).name ?? null,
          eligible: false,
          reasonCode: e.reasonCode,
          reasonDetail: e.reasonDetail,
          reasonText: reasonText(e, config)
        }))
      ],
      explanation: lines.join(" "),
      explanationLines: lines
    };
  });

  const changes = previous
    ? requests
      .map(q => ({ requestId: q.id, from: previous.get(q.id) ?? null, to: results.find(r => r.requestId === q.id).runnerId }))
      .filter(c => c.from !== c.to)
    : [];

  const result = {
    now: ctx.now ?? null,
    provider: { name: ctx.provider.name, description: ctx.provider.description ?? null },
    results,
    assignments: results.filter(r => r.status === "assigned")
      .map(r => ({ requestId: r.requestId, runnerId: r.runnerId, storeId: r.storeId })),
    unmatched: results.filter(r => r.status === "unmatched")
      .map(r => ({ requestId: r.requestId, reasonCode: r.reasonCode, explanation: r.explanation })),
    changes,
    errors: evaluations.flat()
      .filter(e => e.reasonCode === REASON.ROUTING_ERROR)
      .map(e => ({ requestId: e.requestId, runnerId: e.runnerId, message: e.reasonDetail.message }))
  };
  // Kept off the enumerable result so it doesn't show up in JSON output or deep-equality checks.
  Object.defineProperty(result, "context", { value: ctx, enumerable: false });
  return result;
}

function exclusionSet(exclusions) {
  return new Set(exclusions.map(({ requestId, runnerId }) => pairKey(requestId, runnerId)));
}

/**
 * @param {object} args
 * @param {import("./contract.js").DeliveryRequest[]} args.requests
 * @param {import("./contract.js").Runner[]} args.runners
 * @param {import("./contract.js").DetourProvider} args.provider
 * @param {string} [args.now]  ISO time; defaults to the current time
 * @param {object} [args.config]  Overrides merged onto DEFAULT_CONFIG
 * @param {{ requestId: string, runnerId: string }[]} [args.exclusions]  Pairs that must not match (declines)
 */
export async function matchRequests({ requests, runners, provider, now = new Date().toISOString(), config, exclusions = [] }) {
  requests.forEach(validateRequest);
  runners.forEach(validateRunner);
  const ids = new Set();
  for (const { id } of [...requests, ...runners]) {
    if (ids.has(id)) throw new TypeError(`Duplicate id ${id}: request and runner ids must be unique`);
    ids.add(id);
  }

  const resolved = resolveConfig(config);
  const estimates = await estimatePairs({ requests, runners, provider, now });
  return solve({ requests, runners, provider, now, config: resolved, exclusions: exclusionSet(exclusions), exclusionList: exclusions, estimates, previous: null });
}

function previousPairs(result) {
  return new Map(result.assignments.map(a => [a.requestId, a.runnerId]));
}

/**
 * The runner declined: never offer them this request again, and pick the next best runner.
 * Other assignments stay unless moving one is the only way to cover this request.
 */
export function declineAssignment(result, requestId, runnerId) {
  const ctx = result.context;
  if (!ctx) throw new TypeError("declineAssignment() needs a result returned by matchRequests()");
  const exclusionList = [...ctx.exclusionList, { requestId, runnerId }];
  return solve({ ...ctx, exclusionList, exclusions: exclusionSet(exclusionList), previous: previousPairs(result) });
}

/** The runner went offline: release whatever they held and reassign it the same way as a decline. */
export function markRunnerOffline(result, runnerId) {
  const ctx = result.context;
  if (!ctx) throw new TypeError("markRunnerOffline() needs a result returned by matchRequests()");
  if (!ctx.runners.some(r => r.id === runnerId)) throw new RangeError(`Unknown runner ${runnerId}`);
  const runners = ctx.runners.map(r => (r.id === runnerId ? { ...r, status: "offline" } : r));
  return solve({ ...ctx, runners, previous: previousPairs(result) });
}
