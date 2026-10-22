// The shared contract between routing (Rijul) and matching (Kanishk).
//
// Matching never computes routes. It asks a DetourProvider for one DetourEstimate per
// runner/request pair and decides only from those. Any provider that returns this shape can be
// swapped in: see createDetourProvider() in detour.js, which every provider should be built with
// so that store selection and feasibility rules stay in one place.
//
// Field names map onto the Supabase tables: Runner ≈ public.runs, Request ≈ public.requests,
// Store ≈ public.places where kind = 'store'. See README.md for the full mapping.

/**
 * @typedef {{ lat: number, lng: number }} LatLng
 *
 * @typedef {LatLng & { label?: string }} Place
 *
 * @typedef {object} Store
 * @property {string} id
 * @property {string} name
 * @property {number} lat
 * @property {number} lng
 *
 * @typedef {object} Commitment  A delivery the runner already holds.
 * @property {string} requestId
 * @property {string} pickupAt   ISO time
 * @property {string} dropoffAt  ISO time
 *
 * @typedef {"available" | "busy" | "offline"} RunnerStatus
 *
 * @typedef {object} Runner  One trip someone is already making.
 * @property {string} id
 * @property {string} name
 * @property {Place} start
 * @property {Place} destination
 * @property {string} departsAt        ISO time the trip starts (runs.created_at today)
 * @property {string} availableUntil   ISO time the trip must end by (runs.closes_at)
 * @property {number} maxDetourMinutes Extra minutes they accept (runs.max_added_minutes)
 * @property {RunnerStatus} status
 * @property {Commitment[]} [commitments]
 *
 * @typedef {object} DeliveryRequest
 * @property {string} id
 * @property {string} item
 * @property {Store[]} storeOptions  Any of these stores can supply the item. Extends the single
 *                                   requests.pickup_place_id ("any store" = several options).
 * @property {Place} dropoff
 * @property {string} deliverBy      ISO time
 *
 * @typedef {object} RouteLeg  What a routing function returns for one from → to leg.
 * @property {number} distanceM
 * @property {number} durationMin    Travel time only; handling time is added by detour.js
 * @property {LatLng[]} geometry     Polyline, for the map only
 *
 * @typedef {(from: LatLng, to: LatLng) => Promise<RouteLeg>} RouteFn
 *
 * @typedef {{ distanceM: number, durationMin: number }} RouteSummary
 *
 * @typedef {object} StoreCandidate  The detour through one store option.
 * @property {string} storeId
 * @property {string} storeName
 * @property {number} addedDistanceM
 * @property {number} addedDurationMin
 * @property {string} pickupAt
 * @property {string} dropoffAt
 * @property {string} tripEndAt
 * @property {boolean} feasible
 * @property {ReasonCode | null} reasonCode
 *
 * @typedef {object} DetourEstimate
 * @property {string} runnerId
 * @property {string} requestId
 * @property {string | null} storeId      Chosen store (null only when there were no options)
 * @property {string | null} storeName
 * @property {RouteSummary} original      start → destination
 * @property {RouteSummary | null} modified  start → store → drop-off → destination, incl. handling
 * @property {number | null} addedDistanceM
 * @property {number | null} addedDurationMin
 * @property {string | null} pickupAt     When the runner leaves the store with the item
 * @property {string | null} dropoffAt    When the requester has it
 * @property {string | null} tripEndAt    When the runner reaches their own destination
 * @property {boolean} feasible
 * @property {ReasonCode | null} reasonCode    First rule broken, in REASON order; null if feasible
 * @property {object | null} reasonDetail      Numbers behind reasonCode, for explanations
 * @property {{ original: LatLng[], modified: LatLng[] }} geometry
 * @property {StoreCandidate[]} storeCandidates  Every option, best first
 *
 * @typedef {object} DetourProvider
 * @property {string} name
 * @property {string} [description]
 * @property {(runner: Runner, request: DeliveryRequest, options?: { now?: string }) => Promise<DetourEstimate>} estimateDetour
 */

/** @typedef {typeof REASON[keyof typeof REASON]} ReasonCode */

/** Why a runner can't take a request, or why a request went unmatched. */
export const REASON = Object.freeze({
  // Feasibility, decided by detour.js from a DetourEstimate (checked in this order)
  DETOUR_EXCEEDS_MAX: "DETOUR_EXCEEDS_MAX",
  MISSES_DEADLINE: "MISSES_DEADLINE",
  EXCEEDS_AVAILABILITY: "EXCEEDS_AVAILABILITY",
  NO_STORE_OPTIONS: "NO_STORE_OPTIONS",

  // Eligibility, decided by match.js before or after asking the provider
  DEADLINE_PASSED: "DEADLINE_PASSED",
  RUNNER_OFFLINE: "RUNNER_OFFLINE",
  RUNNER_BUSY: "RUNNER_BUSY",
  DECLINED: "DECLINED",
  DEPARTS_TOO_LATE: "DEPARTS_TOO_LATE",
  OVERLAPPING_ASSIGNMENT: "OVERLAPPING_ASSIGNMENT",
  // The provider threw for this pair (e.g. routing service down). The pair is skipped, never guessed.
  ROUTING_ERROR: "ROUTING_ERROR",

  // Request-level outcomes when nobody is assigned
  NO_ELIGIBLE_RUNNER: "NO_ELIGIBLE_RUNNER",
  RUNNERS_ASSIGNED_ELSEWHERE: "RUNNERS_ASSIGNED_ELSEWHERE",
  ALL_RUNNERS_DECLINED: "ALL_RUNNERS_DECLINED"
});

export const RUNNER_STATUSES = Object.freeze(["available", "busy", "offline"]);

const idCollator = new Intl.Collator("en", { numeric: true });

/** Orders ids the same way on every machine, with numbers in order: R2 before R10. */
export const compareIds = (a, b) => idCollator.compare(a, b);

function fail(kind, id, message) {
  throw new TypeError(`${kind}${id ? ` ${id}` : ""}: ${message}`);
}

function checkPoint(kind, id, field, point) {
  if (!point || !Number.isFinite(point.lat) || !Number.isFinite(point.lng)) {
    fail(kind, id, `${field} needs numeric lat and lng`);
  }
}

function checkTime(kind, id, field, value) {
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) fail(kind, id, `${field} must be an ISO time`);
}

/** @param {Runner} runner */
export function validateRunner(runner) {
  const id = runner?.id;
  if (!id) fail("Runner", "", "missing id");
  checkPoint("Runner", id, "start", runner.start);
  checkPoint("Runner", id, "destination", runner.destination);
  checkTime("Runner", id, "departsAt", runner.departsAt);
  checkTime("Runner", id, "availableUntil", runner.availableUntil);
  if (!(runner.maxDetourMinutes >= 0)) fail("Runner", id, "maxDetourMinutes must be 0 or more");
  if (!RUNNER_STATUSES.includes(runner.status)) fail("Runner", id, `status must be one of ${RUNNER_STATUSES.join(", ")}`);
  for (const c of runner.commitments ?? []) {
    checkTime("Runner", id, "commitment pickupAt", c.pickupAt);
    checkTime("Runner", id, "commitment dropoffAt", c.dropoffAt);
  }
  return runner;
}

/** @param {DeliveryRequest} request */
export function validateRequest(request) {
  const id = request?.id;
  if (!id) fail("Request", "", "missing id");
  if (!Array.isArray(request.storeOptions)) fail("Request", id, "storeOptions must be an array of stores");
  request.storeOptions.forEach(store => checkPoint("Request", id, `store ${store?.id}`, store));
  checkPoint("Request", id, "dropoff", request.dropoff);
  checkTime("Request", id, "deliverBy", request.deliverBy);
  return request;
}
