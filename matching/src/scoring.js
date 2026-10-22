// Ranks feasible runner/request pairs. Lower is better. Weights live in config.js.

import { compareIds } from "./contract.js";
import { DEFAULT_CONFIG } from "./config.js";
import { minutesBetween, round1, toMs } from "./time.js";

const round = (x, places) => Math.round(x * 10 ** places) / 10 ** places;

/**
 * @param {import("./contract.js").DetourEstimate} estimate  A feasible estimate
 * @param {import("./contract.js").DeliveryRequest} request
 * @param {typeof DEFAULT_CONFIG} [config]
 * @returns {{ total: number, breakdown: object }}
 */
export function scorePair(estimate, request, config = DEFAULT_CONFIG) {
  const w = config.scoring;
  const added = estimate.addedDurationMin;
  // A trip of under a minute (start ≈ destination) is treated as one minute, so the ratio stays finite.
  const relative = added / Math.max(estimate.original.durationMin, 1);
  const slack = round1(minutesBetween(toMs(estimate.dropoffAt), toMs(request.deliverBy)));
  const shortfall = Math.max(0, w.slackTargetMinutes - slack);

  const breakdown = {
    addedDuration: { minutes: added, weight: w.addedMinutes, points: round(w.addedMinutes * added, 2) },
    relativeDetour: { ratio: round(relative, 3), weight: w.relativeDetour, points: round(w.relativeDetour * relative, 2) },
    deadlineRisk: {
      slackMinutes: slack,
      shortfallMinutes: round1(shortfall),
      weight: w.slackPenalty,
      points: round(w.slackPenalty * shortfall, 2)
    }
  };
  const total = round(
    breakdown.addedDuration.points + breakdown.relativeDetour.points + breakdown.deadlineRisk.points,
    2
  );
  return { total, breakdown };
}

/**
 * Orders eligible candidates best first: score, then added distance, then runner id.
 * @param {{ runnerId: string, score: { total: number }, estimate: { addedDistanceM: number } }} a
 * @param {typeof a} b
 */
export function compareCandidates(a, b) {
  return (a.score.total - b.score.total)
    || (a.estimate.addedDistanceM - b.estimate.addedDistanceM)
    || compareIds(a.runnerId, b.runnerId);
}
