// Turns scenario JSON (places and stores referenced by key) into contract objects.
// Pure: no file system, so it also works in the browser. bin/ and test/ read the file themselves.

import { validateRequest, validateRunner } from "./contract.js";

/**
 * @param {object} data  Parsed scenario JSON (see scenarios/berkeley.json)
 * @returns {{ name: string, now: string, stores: import("./contract.js").Store[],
 *   runners: import("./contract.js").Runner[], requests: import("./contract.js").DeliveryRequest[] }}
 */
export function resolveScenario(data) {
  const places = data.places ?? {};
  const stores = (data.stores ?? []).map(s => ({ id: s.id, name: s.name, lat: s.lat, lng: s.lng }));
  const storesById = new Map(stores.map(s => [s.id, s]));

  const place = (ref, owner) => {
    if (ref && typeof ref === "object") return ref;
    const found = places[ref] ?? storesById.get(ref);
    if (!found) throw new TypeError(`${owner}: unknown place "${ref}"`);
    return { label: found.label ?? found.name, lat: found.lat, lng: found.lng };
  };

  const runners = (data.runners ?? []).map(r => validateRunner({
    id: r.id,
    name: r.name,
    start: place(r.start, `Runner ${r.id}`),
    destination: place(r.destination, `Runner ${r.id}`),
    departsAt: r.departsAt,
    availableUntil: r.availableUntil,
    maxDetourMinutes: r.maxDetourMinutes,
    status: r.status ?? "available",
    commitments: r.commitments ?? []
  }));

  const requests = (data.requests ?? []).map(q => validateRequest({
    id: q.id,
    item: q.item,
    storeOptions: (q.storeOptions ?? []).map(id => {
      const store = storesById.get(id);
      if (!store) throw new TypeError(`Request ${q.id}: unknown store "${id}"`);
      return store;
    }),
    dropoff: place(q.dropoff, `Request ${q.id}`),
    deliverBy: q.deliverBy
  }));

  return { name: data.name ?? "scenario", now: data.now, stores, runners, requests };
}
