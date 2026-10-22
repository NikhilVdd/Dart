// Every tunable number in the matcher lives here. README.md explains how each one is used.

export const DEFAULT_CONFIG = Object.freeze({
  // Same walking model as supabase/migrations/20261011000003_rpc_and_matching.sql (walk_minutes):
  // straight-line metres × 1.3 street-grid factor, at 80 m/min (≈ 4.8 km/h).
  travel: Object.freeze({
    roadFactor: 1.3,
    metersPerMinute: 80,
    bikeMetersPerMinute: 250  // ≈ 15 km/h, used when the simulated provider runs in "bike" mode
  }),

  // Fixed time spent at each stop, also matching detour_minutes() in SQL.
  handling: Object.freeze({
    shopMinutes: 3,    // finding and buying the item at the store
    handoffMinutes: 2  // meeting the requester at the drop-off
  }),

  // Ranking score, lower is better:
  //   addedMinutes × addedDuration
  // + relativeDetour × (addedDuration / originalDuration)
  // + slackPenalty × max(0, slackTargetMinutes − minutes of slack before the deadline)
  scoring: Object.freeze({
    addedMinutes: 1.0,      // main factor: each extra minute of the runner's time costs 1 point
    relativeDetour: 10,     // doubling someone's trip (+100%) costs 10 points
    slackPenalty: 0.5,      // each minute of slack below the target costs 0.5 points
    slackTargetMinutes: 15  // arriving 15+ min before the deadline carries no risk penalty
  }),

  // Scores are rounded to this many points per unit before assignment, so equal scores tie exactly
  // and the tie-breaks (added distance, then runner id) decide.
  scorePrecision: 1000,

  // Times in explanations are printed in the campus time zone, whatever the machine's zone is.
  timeZone: "America/Los_Angeles"
});

/** Shallow-merges overrides onto DEFAULT_CONFIG, one level deep. */
export function resolveConfig(overrides = {}) {
  const merged = { ...DEFAULT_CONFIG };
  for (const [key, value] of Object.entries(overrides)) {
    const base = DEFAULT_CONFIG[key];
    merged[key] = base && typeof base === "object" ? { ...base, ...value } : value;
  }
  return merged;
}
