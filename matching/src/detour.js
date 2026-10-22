// Store selection and feasibility rules shared by every detour provider.
//
// A provider only has to supply a route function (from → to → RouteLeg). createDetourProvider()
// turns that into the DetourProvider contract: it routes the original and modified trips for each
// store option, adds handling time, chooses the best store and applies the feasibility rules.
// The simulated provider and the real routing provider are both built this way.

import { compareIds, REASON } from "./contract.js";
import { DEFAULT_CONFIG } from "./config.js";
import { addMinutes, minutesBetween, round1, toIso, toMs } from "./time.js";

/**
 * When the trip starts: the runner's departure, or now if they already left.
 * @param {import("./contract.js").Runner} runner
 * @param {string} [now]
 */
export function tripStartMs(runner, now) {
  const departs = toMs(runner.departsAt);
  return now ? Math.max(departs, toMs(now)) : departs;
}

/**
 * The rules, in order: detour within the runner's max, drop-off by the deadline, trip finished
 * before the runner's availability ends, and the pickup-to-drop-off window clear of the runner's
 * existing commitments. Returns the first rule broken, or null. Because store selection prefers
 * feasible stores, a store whose window overlaps a commitment loses to one that doesn't.
 * Values are compared at one-decimal precision, the same precision they're reported at.
 *
 * @param {import("./contract.js").Runner} runner
 * @param {import("./contract.js").DeliveryRequest} request
 * @param {{ addedDurationMin: number, pickupAt: string, dropoffAt: string, tripEndAt: string }} candidate
 * @returns {{ reasonCode: import("./contract.js").ReasonCode, reasonDetail: object } | null}
 */
export function checkFeasibility(runner, request, candidate) {
  const added = round1(candidate.addedDurationMin);
  if (added > runner.maxDetourMinutes) {
    return {
      reasonCode: REASON.DETOUR_EXCEEDS_MAX,
      reasonDetail: { addedDurationMin: added, maxDetourMinutes: runner.maxDetourMinutes }
    };
  }
  const lateBy = round1(minutesBetween(toMs(request.deliverBy), toMs(candidate.dropoffAt)));
  if (lateBy > 0) {
    return {
      reasonCode: REASON.MISSES_DEADLINE,
      reasonDetail: { dropoffAt: candidate.dropoffAt, deliverBy: request.deliverBy, lateByMin: lateBy }
    };
  }
  const overBy = round1(minutesBetween(toMs(runner.availableUntil), toMs(candidate.tripEndAt)));
  if (overBy > 0) {
    return {
      reasonCode: REASON.EXCEEDS_AVAILABILITY,
      reasonDetail: { tripEndAt: candidate.tripEndAt, availableUntil: runner.availableUntil, overByMin: overBy }
    };
  }
  const overlap = findOverlap(runner, candidate);
  if (overlap) {
    return {
      reasonCode: REASON.OVERLAPPING_ASSIGNMENT,
      reasonDetail: {
        commitmentRequestId: overlap.requestId,
        commitmentPickupAt: overlap.pickupAt,
        commitmentDropoffAt: overlap.dropoffAt,
        pickupAt: candidate.pickupAt,
        dropoffAt: candidate.dropoffAt
      }
    };
  }
  return null;
}

/**
 * The first commitment whose pickup-to-drop-off window overlaps the candidate's, if any.
 * Back-to-back windows (one ends exactly when the other starts) don't overlap.
 */
export function findOverlap(runner, candidate) {
  const start = toMs(candidate.pickupAt);
  const end = toMs(candidate.dropoffAt);
  return (runner.commitments ?? []).find(c => toMs(c.pickupAt) < end && start < toMs(c.dropoffAt)) ?? null;
}

/** Rejects legs a broken routing response could produce, so they surface as errors, not estimates. */
function checkLeg(leg, from, to) {
  if (!leg || !Number.isFinite(leg.distanceM) || !Number.isFinite(leg.durationMin) || leg.distanceM < 0 || leg.durationMin < 0) {
    throw new TypeError(`route() returned an invalid leg for (${from.lat}, ${from.lng}) → (${to.lat}, ${to.lng})`);
  }
  return leg;
}

/**
 * The detour through one store, from already-routed legs.
 *
 * @param {object} args
 * @param {import("./contract.js").Runner} args.runner
 * @param {import("./contract.js").DeliveryRequest} args.request
 * @param {import("./contract.js").Store} args.store
 * @param {import("./contract.js").RouteLeg} args.original   start → destination
 * @param {import("./contract.js").RouteLeg[]} args.legs     [start → store, store → drop-off, drop-off → destination]
 * @param {number} args.startMs
 * @param {typeof DEFAULT_CONFIG} [args.config]
 */
export function estimateForStore({ runner, request, store, original, legs, startMs, config = DEFAULT_CONFIG }) {
  const [toStore, toDropoff, toDestination] = legs;
  const { shopMinutes, handoffMinutes } = config.handling;

  const pickupMs = addMinutes(startMs, toStore.durationMin + shopMinutes);
  const dropoffMs = addMinutes(pickupMs, toDropoff.durationMin + handoffMinutes);
  const tripEndMs = addMinutes(dropoffMs, toDestination.durationMin);

  const modified = {
    distanceM: legs.reduce((sum, leg) => sum + leg.distanceM, 0),
    durationMin: legs.reduce((sum, leg) => sum + leg.durationMin, 0) + shopMinutes + handoffMinutes
  };
  const candidate = {
    storeId: store.id,
    storeName: store.name,
    modified,
    addedDistanceM: modified.distanceM - original.distanceM,
    addedDurationMin: modified.durationMin - original.durationMin,
    pickupAt: toIso(pickupMs),
    dropoffAt: toIso(dropoffMs),
    tripEndAt: toIso(tripEndMs),
    geometry: joinGeometry(legs)
  };
  const broken = checkFeasibility(runner, request, candidate);
  return {
    ...candidate,
    feasible: broken === null,
    reasonCode: broken?.reasonCode ?? null,
    reasonDetail: broken?.reasonDetail ?? null
  };
}

/**
 * Orders store candidates best first: feasible before infeasible, then smallest added duration,
 * then smallest added distance, then store id. The first one is the chosen store.
 */
export function compareStoreCandidates(a, b) {
  return (Number(b.feasible) - Number(a.feasible))
    || (round1(a.addedDurationMin) - round1(b.addedDurationMin))
    || (round1(a.addedDistanceM) - round1(b.addedDistanceM))
    || compareIds(a.storeId, b.storeId);
}

/** @returns {object | null} The best candidate, or null when there are none. */
export function chooseStore(candidates) {
  return candidates.length ? [...candidates].sort(compareStoreCandidates)[0] : null;
}

function joinGeometry(legs) {
  const points = [];
  for (const leg of legs) {
    for (const point of leg.geometry ?? []) {
      const last = points[points.length - 1];
      if (!last || last.lat !== point.lat || last.lng !== point.lng) points.push(point);
    }
  }
  return points;
}

const summary = route => ({ distanceM: round1(route.distanceM), durationMin: round1(route.durationMin) });

/**
 * Builds a DetourProvider from a route function.
 *
 * @param {object} args
 * @param {string} args.name
 * @param {string} [args.description]
 * @param {import("./contract.js").RouteFn} args.route
 * @param {typeof DEFAULT_CONFIG} [args.config]
 * @returns {import("./contract.js").DetourProvider}
 */
export function createDetourProvider({ name, description, route, config = DEFAULT_CONFIG }) {
  return {
    name,
    description,
    async estimateDetour(runner, request, { now } = {}) {
      const leg = async (from, to) => checkLeg(await route(from, to), from, to);
      const original = await leg(runner.start, runner.destination);
      const startMs = tripStartMs(runner, now);
      const base = {
        runnerId: runner.id,
        requestId: request.id,
        original: summary(original)
      };

      if (!request.storeOptions.length) {
        return {
          ...base,
          storeId: null,
          storeName: null,
          modified: null,
          addedDistanceM: null,
          addedDurationMin: null,
          pickupAt: null,
          dropoffAt: null,
          tripEndAt: null,
          feasible: false,
          reasonCode: REASON.NO_STORE_OPTIONS,
          reasonDetail: null,
          geometry: { original: original.geometry, modified: [] },
          storeCandidates: []
        };
      }

      const candidates = await Promise.all(request.storeOptions.map(async store => {
        const legs = await Promise.all([
          leg(runner.start, store),
          leg(store, request.dropoff),
          leg(request.dropoff, runner.destination)
        ]);
        return estimateForStore({ runner, request, store, original, legs, startMs, config });
      }));
      candidates.sort(compareStoreCandidates);
      const best = candidates[0];

      return {
        ...base,
        storeId: best.storeId,
        storeName: best.storeName,
        modified: summary(best.modified),
        addedDistanceM: round1(best.addedDistanceM),
        addedDurationMin: round1(best.addedDurationMin),
        pickupAt: best.pickupAt,
        dropoffAt: best.dropoffAt,
        tripEndAt: best.tripEndAt,
        feasible: best.feasible,
        reasonCode: best.reasonCode,
        reasonDetail: best.reasonDetail,
        geometry: { original: original.geometry, modified: best.geometry },
        storeCandidates: candidates.map(c => ({
          storeId: c.storeId,
          storeName: c.storeName,
          addedDistanceM: round1(c.addedDistanceM),
          addedDurationMin: round1(c.addedDurationMin),
          pickupAt: c.pickupAt,
          dropoffAt: c.dropoffAt,
          tripEndAt: c.tripEndAt,
          feasible: c.feasible,
          reasonCode: c.reasonCode
        }))
      };
    }
  };
}
