// Plain-English sentences for every matching decision.

import { REASON } from "./contract.js";
import { DEFAULT_CONFIG } from "./config.js";
import { compareCandidates } from "./scoring.js";
import { fmtClock, fmtMin, minutesBetween, toMs } from "./time.js";

const who = runner => (runner.name ? `${runner.id} (${runner.name})` : runner.id);
const what = request => (request.item ? `${request.id} (${request.item})` : request.id);

/**
 * Why a runner can't take a request, as a clause: "18 min detour via CVS exceeds their 10 min limit".
 * @param {{ reasonCode: string, reasonDetail?: object, estimate?: object }} evaluation
 */
export function reasonText(evaluation, config = DEFAULT_CONFIG) {
  const d = evaluation.reasonDetail ?? {};
  const clock = iso => fmtClock(iso, config.timeZone);
  const via = evaluation.estimate?.storeName ? ` via ${evaluation.estimate.storeName}` : "";
  switch (evaluation.reasonCode) {
    case REASON.DETOUR_EXCEEDS_MAX:
      return `${fmtMin(d.addedDurationMin)} min detour${via} exceeds their ${fmtMin(d.maxDetourMinutes)} min limit`;
    case REASON.MISSES_DEADLINE:
      return `would arrive at ${clock(d.dropoffAt)}${via}, ${fmtMin(d.lateByMin)} min after the ${clock(d.deliverBy)} deadline`;
    case REASON.EXCEEDS_AVAILABILITY:
      return `trip would end at ${clock(d.tripEndAt)}, ${fmtMin(d.overByMin)} min past their ${clock(d.availableUntil)} availability`;
    case REASON.NO_STORE_OPTIONS:
      return "the request lists no store that sells the item";
    case REASON.DEADLINE_PASSED:
      return `the ${clock(d.deliverBy)} deadline has already passed`;
    case REASON.RUNNER_OFFLINE:
      return "offline";
    case REASON.RUNNER_BUSY:
      return "marked busy";
    case REASON.DECLINED:
      return "declined this request";
    case REASON.DEPARTS_TOO_LATE:
      return `doesn't leave until ${clock(d.departsAt)}, after the ${clock(d.deliverBy)} deadline`;
    case REASON.OVERLAPPING_ASSIGNMENT:
      return `already carrying ${d.commitmentRequestId} ${clock(d.commitmentPickupAt)}–${clock(d.commitmentDropoffAt)}, `
        + `which overlaps this pickup-to-drop-off window (${clock(d.pickupAt)}–${clock(d.dropoffAt)})`;
    case REASON.ROUTING_ERROR:
      return `route couldn't be computed (${d.message ?? "unknown error"})`;
    default:
      return evaluation.reasonCode ?? "not eligible";
  }
}

function arrival(estimate, request, config) {
  const early = Math.round(minutesBetween(toMs(estimate.dropoffAt), toMs(request.deliverBy)));
  const deadline = fmtClock(request.deliverBy, config.timeZone);
  return early > 0 ? `arrives ${early} min before the ${deadline} deadline` : `arrives right at the ${deadline} deadline`;
}

const fit = e => `adds ${fmtMin(e.estimate.addedDurationMin)} min via ${e.estimate.storeName}, score ${e.score.total.toFixed(2)}`;

/**
 * Why the runner holding another request isn't used here. Only states causes the solver actually
 * acted on: a single option, a pair kept from before a re-solve, or a better combined score.
 */
function elsewhereClause(otherRequest, otherEligibleCount, keptFromBefore) {
  if (otherEligibleCount === 1) return `${what(otherRequest)}, which had no other option`;
  if (keptFromBefore) return `${what(otherRequest)}, an existing assignment that was kept`;
  return `${what(otherRequest)}, because the combined assignment scores better that way`;
}

const UNMATCHED_LEAD = {
  [REASON.NO_ELIGIBLE_RUNNER]: "no runner can make it",
  [REASON.RUNNERS_ASSIGNED_ELSEWHERE]: "every eligible runner is needed for another request",
  [REASON.ALL_RUNNERS_DECLINED]: "no backup runner after declines",
  [REASON.DEADLINE_PASSED]: "the deadline has already passed",
  [REASON.NO_STORE_OPTIONS]: "no store options were given",
  [REASON.ROUTING_ERROR]: "no runner's route could be computed"
};

/**
 * One sentence per runner, chosen first.
 *
 * @param {object} args
 * @param {import("./contract.js").DeliveryRequest} args.request
 * @param {object | null} args.chosen       The chosen evaluation, or null
 * @param {string | null} args.unmatchedReason
 * @param {object[]} args.eligible          Ranked eligible evaluations, chosen excluded
 * @param {object[]} args.rejected          Rejected evaluations
 * @param {Map<string, string>} args.assignedTo        runnerId → requestId they hold in this solve
 * @param {Map<string, object>} args.requestsById
 * @param {Map<string, number>} args.eligibleCounts    requestId → number of eligible runners
 * @param {Map<string, object>} args.runnersById
 * @param {Map<string, string> | null} [args.previous]  requestId → runnerId before a re-solve
 */
export function explainRequest({ request, chosen, unmatchedReason, eligible, rejected, assignedTo,
  requestsById, eligibleCounts, runnersById, previous = null, config = DEFAULT_CONFIG }) {
  const lines = [];
  if (chosen) {
    lines.push(`${who(runnersById.get(chosen.runnerId))} chosen: ${fit(chosen)}; ${arrival(chosen.estimate, request, config)}.`);
  } else {
    lines.push(`No runner for ${what(request)}: ${UNMATCHED_LEAD[unmatchedReason] ?? unmatchedReason}.`);
  }

  const kept = (requestId, runnerId) => previous?.get(requestId) === runnerId;
  for (const e of eligible) {
    const runner = runnersById.get(e.runnerId);
    const holding = assignedTo.get(e.runnerId);
    if (holding && holding !== request.id) {
      const other = requestsById.get(holding);
      const clause = elsewhereClause(other, eligibleCounts.get(holding), kept(holding, e.runnerId));
      lines.push(`${who(runner)} would fit (${fit(e)}) but is carrying ${clause}.`);
    } else if (chosen && kept(request.id, chosen.runnerId) && compareCandidates(e, chosen) < 0) {
      lines.push(`${who(runner)} is free and scores better (${fit(e)}), but the existing assignment was kept to avoid reshuffling.`);
    } else {
      lines.push(`${who(runner)} also fits but ranks lower: ${fit(e)}.`);
    }
  }
  for (const e of rejected) {
    lines.push(`${who(runnersById.get(e.runnerId))} rejected: ${reasonText(e, config)}.`);
  }
  return lines;
}
