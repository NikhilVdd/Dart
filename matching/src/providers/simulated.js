// Deterministic, offline detour provider: straight-line distance × road factor at a fixed walking
// pace, the same model the Supabase matching functions use. For matching development and tests.

import { DEFAULT_CONFIG } from "../config.js";
import { createDetourProvider } from "../detour.js";
import { distanceM } from "../geo.js";

/**
 * @param {typeof DEFAULT_CONFIG["travel"]} [travel]
 * @returns {import("../contract.js").RouteFn}
 */
export function straightLineRoute({ roadFactor, metersPerMinute } = DEFAULT_CONFIG.travel) {
  return async (from, to) => {
    const meters = distanceM(from, to) * roadFactor;
    return {
      distanceM: meters,
      durationMin: meters / metersPerMinute,
      geometry: [{ lat: from.lat, lng: from.lng }, { lat: to.lat, lng: to.lng }]
    };
  };
}

/** @param {{ config?: typeof DEFAULT_CONFIG }} [options] */
export function createSimulatedProvider({ config = DEFAULT_CONFIG } = {}) {
  const { roadFactor, metersPerMinute } = config.travel;
  return createDetourProvider({
    name: "simulated",
    description: `straight line × ${roadFactor} at ${metersPerMinute} m/min`,
    route: straightLineRoute(config.travel),
    config
  });
}
