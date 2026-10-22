// Real detour provider: walking or cycling routes from OSRM, by default the free public servers at
// routing.openstreetmap.de (no key; light use only, so legs are cached and requests are limited).
//
// Only the route function lives here. Store selection, feasibility and the DetourEstimate shape all
// come from createDetourProvider() in detour.js, shared with the simulated provider.
//
// Failures always throw a RoutingError. Matching turns that into ROUTING_ERROR for the affected pair,
// so a routing problem never becomes a made-up estimate.

import { DEFAULT_CONFIG } from "../config.js";
import { createDetourProvider } from "../detour.js";

export const OSRM_DEFAULT_BASE_URL = "https://routing.openstreetmap.de";

// routing.openstreetmap.de runs one OSRM instance per profile.
export const OSRM_MODES = Object.freeze({
  foot: { path: "routed-foot/route/v1/foot", label: "walking" },
  bike: { path: "routed-bike/route/v1/bike", label: "cycling" }
});

export class RoutingError extends Error {
  /** @param {string} message @param {{ status?: number, code?: string, url?: string, cause?: unknown }} [info] */
  constructor(message, { status, code, url, cause } = {}) {
    super(message, cause ? { cause } : undefined);
    this.name = "RoutingError";
    this.status = status ?? null;
    this.code = code ?? null;
    this.url = url ?? null;
  }
}

const coord = point => `${point.lng.toFixed(6)},${point.lat.toFixed(6)}`;

/** The OSRM route URL for one leg. Coordinates are lng,lat, as OSRM expects. */
export function osrmUrl({ from, to, mode = "foot", baseUrl = OSRM_DEFAULT_BASE_URL, overview = "full" }) {
  const profile = OSRM_MODES[mode];
  if (!profile) throw new RangeError(`Unknown travel mode "${mode}" (use ${Object.keys(OSRM_MODES).join(" or ")})`);
  return `${baseUrl.replace(/\/$/, "")}/${profile.path}/${coord(from)};${coord(to)}?overview=${overview}&geometries=geojson&steps=false`;
}

/**
 * Turns an OSRM route response into a RouteLeg, or throws a RoutingError.
 * @returns {import("../contract.js").RouteLeg}
 */
export function parseOsrmRoute(body, url) {
  if (!body || typeof body !== "object") throw new RoutingError("routing service returned an empty response", { url });
  if (body.code !== "Ok") {
    throw new RoutingError(`routing service could not route this leg (${body.code ?? "no code"}${body.message ? `: ${body.message}` : ""})`, { code: body.code, url });
  }
  const route = body.routes?.[0];
  if (!route) throw new RoutingError("routing service returned no route", { code: body.code, url });
  const { distance, duration } = route;
  if (!Number.isFinite(distance) || !Number.isFinite(duration) || distance < 0 || duration < 0) {
    throw new RoutingError("routing service returned a route without a valid distance or duration", { url });
  }
  const coordinates = route.geometry?.coordinates;
  return freezeLeg({
    distanceM: distance,
    durationMin: duration / 60,
    geometry: Array.isArray(coordinates) ? coordinates.map(([lng, lat]) => ({ lat, lng })) : []
  });
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

function checkNonNegative(name, value) {
  if (!Number.isFinite(value) || value < 0) throw new RangeError(`${name} must be a number ≥ 0, got ${value}`);
}

/**
 * Runs at most `concurrency` tasks at once, in the order they were queued, starting each at least
 * `minIntervalMs` after the previous one started. A task whose `bypass()` is true when its turn
 * comes runs at once without using up a slot (for work that will fail fast without the network).
 */
export function createLimiter(concurrency, minIntervalMs = 0) {
  if (!(concurrency >= 1)) throw new RangeError("concurrency must be at least 1");
  checkNonNegative("minIntervalMs", minIntervalMs);
  let active = 0;
  let nextStartAt = 0;
  const queue = [];
  const next = () => {
    if (active >= concurrency || queue.length === 0) return;
    active++;
    const { task, resolve, reject, bypass } = queue.shift();
    const start = async () => {
      if (!bypass?.()) {
        // Spacing is measured from when tasks actually start, so a late timer (a busy machine)
        // can't let the next request follow straight on.
        for (let wait = nextStartAt - Date.now(); wait > 0; wait = nextStartAt - Date.now()) await sleep(wait);
        nextStartAt = Date.now() + minIntervalMs;
      }
      return task();
    };
    start().then(resolve, reject).finally(() => { active--; next(); });
  };
  return (task, { bypass } = {}) => new Promise((resolve, reject) => { queue.push({ task, resolve, reject, bypass }); next(); });
}

const RETRYABLE_STATUS = new Set([429, 502, 503, 504]);

const samePoint = (a, b) => coord(a) === coord(b);

/** Rejects if `promise` hasn't settled within `ms`, calling `onTimeout` first. */
function withTimeout(promise, ms, onTimeout) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => { onTimeout(); reject(new RoutingError(`routing service timed out after ${ms} ms`)); }, ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/**
 * A RouteFn backed by OSRM.
 *
 * Load on the free servers is kept low:
 * - every HTTP attempt, retries included, waits its turn in the limiter
 * - a leg that can't be routed (NoRoute and similar) is remembered for the run, not asked again
 * - after `breakerThreshold` refusals in a row (HTTP 403/429/5xx, network errors, timeouts) all
 *   routing stops for `breakerCooldownMs`, and every leg fails fast with a clear error
 *
 * @param {object} [options]
 * @param {"foot" | "bike"} [options.mode]
 * @param {string} [options.baseUrl]
 * @param {typeof fetch} [options.fetch]    Injected in tests (recorded responses) and the CLI
 * @param {Map<string, Promise<object>>} [options.cache]  Shared cache: identical legs are fetched once
 * @param {number} [options.concurrency]    Requests in flight at once (be gentle with the free servers)
 * @param {number} [options.minIntervalMs]  Minimum gap between request starts, retries included
 * @param {number} [options.retries]        Extra attempts after HTTP 429/502/503/504, with backoff
 * @param {number} [options.retryDelayMs]   First backoff; doubles each retry (Retry-After wins if sent)
 * @param {number} [options.maxRetryAfterMs]  A Retry-After longer than this fails the leg instead of waiting
 * @param {number} [options.timeoutMs]      For the whole request, including reading the body
 * @param {number} [options.breakerThreshold]   Consecutive refusals before routing pauses
 * @param {number} [options.breakerCooldownMs]  How long routing stays paused
 * @param {"full" | "simplified" | "false"} [options.overview]  Geometry detail
 * @param {Record<string, string>} [options.headers]  Not in browsers: custom headers would need a CORS preflight
 * @param {{ requests: number, cacheHits: number, failures: number }} [options.stats]
 * @returns {import("../contract.js").RouteFn}
 */
export function osrmRoute({
  mode = "foot",
  baseUrl = OSRM_DEFAULT_BASE_URL,
  fetch: fetchFn = globalThis.fetch,
  cache = new Map(),
  concurrency = 1,
  minIntervalMs = 1000,
  retries = 2,
  retryDelayMs = 2000,
  maxRetryAfterMs = 30000,
  timeoutMs = 15000,
  breakerThreshold = 3,
  breakerCooldownMs = 60000,
  overview = "full",
  headers,
  stats = { requests: 0, cacheHits: 0, failures: 0 }
} = {}) {
  if (typeof fetchFn !== "function") throw new TypeError("osrmRoute() needs a fetch implementation");
  if (!OSRM_MODES[mode]) throw new RangeError(`Unknown travel mode "${mode}" (use ${Object.keys(OSRM_MODES).join(" or ")})`);
  for (const [name, value] of Object.entries({ minIntervalMs, retries, retryDelayMs, maxRetryAfterMs, breakerCooldownMs })) {
    checkNonNegative(name, value);
  }
  if (!(timeoutMs > 0)) throw new RangeError(`timeoutMs must be positive, got ${timeoutMs}`);
  if (!(breakerThreshold >= 1)) throw new RangeError(`breakerThreshold must be at least 1, got ${breakerThreshold}`);
  const limit = createLimiter(concurrency, minIntervalMs);

  let consecutiveRefusals = 0;
  let pausedUntil = 0;

  function checkBreaker(url) {
    const wait = pausedUntil - Date.now();
    if (wait > 0) {
      throw new RoutingError(`routing paused for ${Math.ceil(wait / 1000)} s after ${breakerThreshold} failed requests in a row `
        + "(the routing service is refusing or unreachable)", { url, code: "PAUSED" });
    }
  }

  function noteOutcome(error) {
    if (!error) { consecutiveRefusals = 0; return; }
    if (!error.transient) return;  // a leg OSRM can't route says nothing about the service
    consecutiveRefusals++;
    if (consecutiveRefusals >= breakerThreshold) pausedUntil = Date.now() + breakerCooldownMs;
  }

  async function attempt(url) {
    checkBreaker(url);
    stats.requests++;
    const controller = typeof AbortController === "function" ? new AbortController() : null;
    const request = (async () => {
      let response;
      try {
        response = await fetchFn(url, { signal: controller?.signal, ...(headers ? { headers } : {}) });
      } catch (error) {
        throw Object.assign(new RoutingError(`could not reach the routing service (${error?.message ?? error})`, { url, cause: error }),
          { transient: true });
      }
      if (!response.ok) {
        throw Object.assign(new RoutingError(`routing service returned HTTP ${response.status}${response.status === 429 ? " (rate limited)" : ""}`,
          { status: response.status, url }), {
          transient: response.status === 403 || response.status === 429 || response.status >= 500,
          retryAfterSeconds: response.headers?.get?.("retry-after") ?? null
        });
      }
      let body;
      try {
        body = await response.json();
      } catch (error) {
        throw Object.assign(new RoutingError("routing service returned invalid JSON", { url, cause: error }), { transient: true });
      }
      return parseOsrmRoute(body, url);
    })();
    try {
      // The timer covers the body too: a response that starts but never finishes still fails.
      const leg = await withTimeout(request, timeoutMs, () => controller?.abort());
      noteOutcome(null);
      return leg;
    } catch (error) {
      if (!(error instanceof RoutingError)) throw error;
      if (/timed out/.test(error.message)) Object.assign(error, { transient: true, url });
      noteOutcome(error);
      throw error;
    }
  }

  async function fetchLeg(url) {
    for (let tries = 0; ; tries++) {
      try {
        // Each attempt queues separately, so retries respect the spacing between requests.
        return await limit(() => attempt(url), { bypass: () => pausedUntil > Date.now() });
      } catch (error) {
        if (tries >= retries || !RETRYABLE_STATUS.has(error.status)) throw error;
        const retryAfter = Number(error.retryAfterSeconds);
        const wait = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : retryDelayMs * 2 ** tries;
        if (wait > maxRetryAfterMs) {
          throw new RoutingError(`routing service is rate limiting; it asked to wait ${Math.ceil(wait / 1000)} s`, { status: error.status, url });
        }
        await sleep(wait);  // outside the limiter, so other legs aren't held up behind the backoff
      }
    }
  }

  return async (from, to) => {
    // Runners often start at the store: a zero-length leg needs no request.
    if (samePoint(from, to)) return freezeLeg({ distanceM: 0, durationMin: 0, geometry: [{ lat: from.lat, lng: from.lng }] });
    const url = osrmUrl({ from, to, mode, baseUrl, overview });
    if (cache.has(url)) {
      stats.cacheHits++;
      return cache.get(url);
    }
    const pending = fetchLeg(url).catch(error => {
      stats.failures++;
      // Service trouble may clear up, so a later call can retry. A leg OSRM can't route won't
      // change, so that failure stays cached for the run instead of being asked again.
      if (error.transient || error.code === "PAUSED" || error.status) cache.delete(url);
      throw error;
    });
    cache.set(url, pending);
    return pending;
  };
}

/** Cached legs are shared between callers, so nobody may change them. */
function freezeLeg(leg) {
  leg.geometry.forEach(Object.freeze);
  Object.freeze(leg.geometry);
  return Object.freeze(leg);
}

/**
 * The real DetourProvider. Same contract as createSimulatedProvider(), plus `stats` and `cache`.
 * Reuse one provider (or pass the same `cache`) across runs to avoid routing the same leg twice.
 *
 * @param {Parameters<typeof osrmRoute>[0] & { config?: typeof DEFAULT_CONFIG }} [options]
 */
export function createOsrmProvider({ config = DEFAULT_CONFIG, ...options } = {}) {
  const mode = options.mode ?? "foot";
  const stats = options.stats ?? { requests: 0, cacheHits: 0, failures: 0 };
  const cache = options.cache ?? new Map();
  const provider = createDetourProvider({
    name: "osrm",
    description: `OSRM ${OSRM_MODES[mode]?.label ?? mode} routes from ${options.baseUrl ?? OSRM_DEFAULT_BASE_URL}`,
    route: osrmRoute({ ...options, mode, stats, cache }),
    config
  });
  return Object.assign(provider, { mode, stats, cache });
}
