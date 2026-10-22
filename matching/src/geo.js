// Same haversine as public.distance_m() in SQL, so both sides agree on distances.
const EARTH_RADIUS_M = 6371000;

/**
 * Great-circle distance in metres.
 * @param {import("./contract.js").LatLng} a
 * @param {import("./contract.js").LatLng} b
 */
export function distanceM(a, b) {
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad;
  const dLng = (b.lng - a.lng) * rad;
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Parses typed coordinates: "37.8726, -122.2607" (comma or spaces). Returns null if it isn't a
 * valid lat/lng pair, so callers can show their own message.
 * @param {string} text
 * @returns {import("./contract.js").LatLng | null}
 */
export function parseLatLng(text) {
  const parts = String(text ?? "").trim().split(/[\s,;]+/).filter(Boolean);
  if (parts.length !== 2) return null;
  const [lat, lng] = parts.map(Number);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return { lat, lng };
}
