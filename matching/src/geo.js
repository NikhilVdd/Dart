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
