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

/** @param {{ config?: typeof DEFAULT_CONFIG, mode?: "foot" | "bike" }} [options] */
export function createSimulatedProvider({ config = DEFAULT_CONFIG, mode = "foot" } = {}) {
  if (mode !== "foot" && mode !== "bike") throw new RangeError(`Unknown travel mode "${mode}" (use foot or bike)`);
  const { roadFactor } = config.travel;
  const metersPerMinute = mode === "bike" ? config.travel.bikeMetersPerMinute : config.travel.metersPerMinute;
  const provider = createDetourProvider({
    name: "simulated",
    description: `straight line × ${roadFactor} at ${metersPerMinute} m/min`,
    route: straightLineRoute({ roadFactor, metersPerMinute }),
    config
  });
  return Object.assign(provider, { mode });
}
