// Record real routing responses once, then replay them offline (tests, demos, the browser page).
// A recording is { recordedAt, baseUrl, mode, responses: { [url]: OSRM body } }.

/** Keeps only what parseOsrmRoute() reads, so recordings stay small. */
function minimalBody(body) {
  return {
    code: body.code,
    ...(body.message ? { message: body.message } : {}),
    routes: (body.routes ?? []).slice(0, 1).map(r => ({ distance: r.distance, duration: r.duration, geometry: r.geometry }))
  };
}

/**
 * Wraps fetch so every successful response is also saved into `responses`.
 * @param {typeof fetch} [fetchFn]
 */
export function createRecordingFetch(fetchFn = globalThis.fetch) {
  const responses = {};
  const recordingFetch = async (url, init) => {
    const response = await fetchFn(url, init);
    if (!response.ok) return response;
    const body = await response.json();
    responses[url] = minimalBody(body);
    return { ok: true, status: response.status, json: async () => body };
  };
  return { fetch: recordingFetch, responses };
}

/**
 * A fetch that only answers from a recording. Anything not recorded fails, so code under test can
 * never reach the network.
 * @param {{ responses: Record<string, object> }} recording
 */
export function createReplayFetch(recording) {
  const responses = recording?.responses ?? {};
  return async url => {
    if (!Object.prototype.hasOwnProperty.call(responses, url)) throw new Error(`no recorded response for ${url}`);
    const body = JSON.parse(JSON.stringify(responses[url]));
    return { ok: true, status: 200, json: async () => body };
  };
}
