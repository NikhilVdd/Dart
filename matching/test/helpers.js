// Test fixtures on a flat grid, so expected numbers are easy to work out by hand:
// coordinates are metres ({ lat: y, lng: x }) and everyone walks 100 m per minute.
// Handling time is the default: 3 min at the store, 2 min at the drop-off.

import { createDetourProvider } from "../src/detour.js";
import { DEFAULT_CONFIG } from "../src/config.js";

export const NOW = "2026-10-21T17:00:00.000Z";
export const at = minutes => new Date(Date.parse(NOW) + minutes * 60000).toISOString();
export const pt = (x, y) => ({ lat: y, lng: x, label: `(${x}, ${y})` });

export const M_PER_MIN = 100;

/** @type {import("../src/contract.js").RouteFn} */
export async function planarRoute(from, to) {
  const distanceM = Math.hypot(to.lng - from.lng, to.lat - from.lat);
  return {
    distanceM,
    durationMin: distanceM / M_PER_MIN,
    geometry: [{ lat: from.lat, lng: from.lng }, { lat: to.lat, lng: to.lng }]
  };
}

/** A provider on the planar grid. `calls` counts estimateDetour() calls; `failFor` makes a runner's routes throw. */
export function planarProvider({ failFor = [] } = {}) {
  const inner = createDetourProvider({
    name: "planar",
    route: planarRoute,
    config: DEFAULT_CONFIG
  });
  const provider = {
    name: "planar",
    calls: 0,
    async estimateDetour(runner, request, options) {
      provider.calls += 1;
      if (failFor.includes(runner.id)) throw new Error(`routing service unavailable for ${runner.id}`);
      return inner.estimateDetour(runner, request, options);
    }
  };
  return provider;
}

export const store = (id, x, y) => ({ id, name: `Store ${id}`, lat: y, lng: x });

/**
 * Defaults: walks (0,0) → (1000,0), leaving now, free for 60 min, 10 min max detour.
 */
export function runner(id, overrides = {}) {
  const { start = [0, 0], dest = [1000, 0], departs = 0, until = 60, ...rest } = overrides;
  return {
    id,
    name: rest.name ?? `Runner ${id}`,
    start: pt(...start),
    destination: pt(...dest),
    departsAt: at(departs),
    availableUntil: at(until),
    maxDetourMinutes: rest.max ?? 10,
    status: rest.status ?? "available",
    commitments: rest.commitments ?? []
  };
}

/** Defaults: one store on the default runner's path at (500, 0), drop-off at (500, 100), due in 60 min. */
export function request(id, overrides = {}) {
  const { stores = [store("S", 500, 0)], dropoff = [500, 100], by = 60, ...rest } = overrides;
  return {
    id,
    item: rest.item ?? `item ${id}`,
    storeOptions: stores,
    dropoff: pt(...dropoff),
    deliverBy: at(by)
  };
}
