// Public entry point for the matching prototype.

export { compareIds, REASON, RUNNER_STATUSES, validateRequest, validateRunner } from "./contract.js";
export { DEFAULT_CONFIG, resolveConfig } from "./config.js";
export { distanceM } from "./geo.js";
export {
  checkFeasibility, chooseStore, compareStoreCandidates, createDetourProvider, estimateForStore, findOverlap, tripStartMs
} from "./detour.js";
export { createSimulatedProvider, straightLineRoute } from "./providers/simulated.js";
export { compareCandidates, scorePair } from "./scoring.js";
export { hungarian, solveAssignment } from "./assignment.js";
export { declineAssignment, markRunnerOffline, matchRequests } from "./match.js";
export { explainRequest, reasonText } from "./explain.js";
export { resolveScenario } from "./scenario.js";
