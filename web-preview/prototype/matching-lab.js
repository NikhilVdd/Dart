// Dev-only matching lab: one detour on a map, and full batch matching on the Berkeley scenario.
// Everything here calls the shared matching package (../../matching/src); nothing is re-implemented.

import L from "leaflet";
import "leaflet/dist/leaflet.css";
import "./matching-lab.css";
import {
  createOsrmProvider, createReplayFetch, createSimulatedProvider, declineAssignment, DEFAULT_CONFIG, distanceM,
  fmtClock, fmtMin, markRunnerOffline, matchRequests, parseLatLng, reasonText, REASON, resolveScenario
} from "../../matching/src/index.js";
import scenarioData from "../../matching/scenarios/berkeley.json";

const TZ = DEFAULT_CONFIG.timeZone;
const CAMPUS = { lat: 37.8715, lng: -122.2600 };
const scenario = resolveScenario(scenarioData);
const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const escapeHTML = value => String(value ?? "").replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]);
const clock = iso => fmtClock(iso, TZ);
const meters = m => (Math.abs(m) >= 1000 ? `${(m / 1000).toFixed(2)} km` : `${Math.round(m)} m`);
const signed = (value, unit) => `${value >= 0 ? "+" : "−"}${unit(Math.abs(value))}`;

const REASON_LABEL = {
  [REASON.DETOUR_EXCEEDS_MAX]: "Detour too long",
  [REASON.MISSES_DEADLINE]: "Misses the deadline",
  [REASON.EXCEEDS_AVAILABILITY]: "Runner not free that long",
  [REASON.OVERLAPPING_ASSIGNMENT]: "Overlaps another delivery",
  [REASON.NO_STORE_OPTIONS]: "No store selected",
  [REASON.NO_ELIGIBLE_RUNNER]: "No runner can make it",
  [REASON.RUNNERS_ASSIGNED_ELSEWHERE]: "Runners needed elsewhere",
  [REASON.ALL_RUNNERS_DECLINED]: "No backup after declines",
  [REASON.DEADLINE_PASSED]: "Deadline passed",
  [REASON.ROUTING_ERROR]: "Routing failed"
};

// ---------------------------------------------------------------------------
// Providers: one per routing/mode, kept for the session so OSM legs are cached across runs.
// ---------------------------------------------------------------------------

const providers = new Map();
// A glob (not a plain import) so the page still loads if the recording hasn't been made yet.
const recordings = import.meta.glob("../../matching/test/fixtures/osrm-berkeley-foot.json", { import: "default" });
let recordingPromise = null;

async function providerFor(kind, mode) {
  const key = `${kind}:${mode}`;
  if (providers.has(key)) return providers.get(key);
  let provider;
  if (kind === "simulated") {
    provider = createSimulatedProvider({ mode });
  } else if (kind === "osrm") {
    provider = createOsrmProvider({ mode });
  } else if (kind === "recorded") {
    if (mode !== "foot") throw new Error("Recorded routes are walking only. Choose Walking, or use live routing for cycling.");
    const load = Object.values(recordings)[0];
    if (!load) throw new Error("No recorded routes yet. Run `node bin/record-routes.mjs` in matching/, or choose live routing.");
    recordingPromise ??= load();
    const recording = await recordingPromise;
    provider = createOsrmProvider({ mode, baseUrl: recording.baseUrl, fetch: createReplayFetch(recording), minIntervalMs: 0, concurrency: 8 });
  } else {
    throw new Error(`Unknown routing option ${kind}`);
  }
  providers.set(key, provider);
  return provider;
}

// ---------------------------------------------------------------------------
// Map
// ---------------------------------------------------------------------------

const map = L.map("map", { zoomControl: true }).setView([CAMPUS.lat, CAMPUS.lng], 15);
L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
  maxZoom: 19,
  attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors · Routes: <a href="https://routing.openstreetmap.de/about.html">FOSSGIS OSRM</a>'
}).addTo(map);

const pointLayer = L.layerGroup().addTo(map);
const routeLayer = L.layerGroup().addTo(map);

const pinIcon = (kind, text, title) => L.divIcon({
  className: "",
  html: `<span class="pin pin-${kind} pin-map" title="${escapeHTML(title)}">${escapeHTML(text)}</span>`,
  iconSize: [28, 28],
  iconAnchor: [14, 14]
});

function marker(point, kind, text, title, options = {}) {
  // Stores sit underneath: a runner often starts right at one (BART is next to Target).
  const zIndexOffset = kind.startsWith("store") ? 0 : 1000;
  return L.marker([point.lat, point.lng], { icon: pinIcon(kind, text, title), keyboard: false, zIndexOffset, ...options })
    .bindTooltip(escapeHTML(title), { direction: "top", offset: [0, -14] });
}

const LEGEND_ROUTES = `<span><i class="line line-original"></i>Original route</span><span><i class="line line-modified"></i>With pickup and drop-off</span>`;
const LEGEND_OVERVIEW = `<span>Each colour is one runner's trip with the delivery.</span><span>Click a route or card to see it in detail.</span>`;
const setLegend = html => { $("#legend").innerHTML = html; };

function drawRoutes(estimate, { fit = true, layer = routeLayer, faded = false } = {}) {
  const original = estimate.geometry.original.map(p => [p.lat, p.lng]);
  const modified = estimate.geometry.modified.map(p => [p.lat, p.lng]);
  const lines = [];
  // Modified first, so the dashed original stays visible where both use the same street.
  if (modified.length > 1) {
    lines.push(L.polyline(modified, { className: "route-modified", color: "#f2620f", weight: faded ? 4 : 7, opacity: faded ? 0.45 : 0.9 }));
  }
  if (original.length > 1) {
    lines.push(L.polyline(original, { className: "route-original", color: "#3b6cff", weight: faded ? 2 : 4, opacity: faded ? 0.35 : 1, dashArray: "8 8" }));
  }
  lines.forEach(line => line.addTo(layer));
  if (fit && lines.length) map.fitBounds(L.featureGroup(lines).getBounds().pad(0.15));
  return lines;
}

// ---------------------------------------------------------------------------
// One detour
// ---------------------------------------------------------------------------

const presets = [
  ...Object.entries(scenarioData.places).map(([key, p]) => ({ key, label: p.label, lat: p.lat, lng: p.lng })),
  ...scenario.stores.map(s => ({ key: s.id, label: s.name, lat: s.lat, lng: s.lng }))
];
const presetByKey = new Map(presets.map(p => [p.key, p]));
// A default that shows all three store outcomes: Target is the smallest detour, CVS also fits,
// and Walgreens just misses a 10-minute limit.
const points = {
  start: { ...presetByKey.get("rumi") },
  destination: { ...presetByKey.get("idasproul") },
  dropoff: { ...presetByKey.get("sather") }
};
const POINT_NAMES = { start: "runner start", destination: "runner destination", dropoff: "drop-off" };
const selectedStores = new Set(["TARGET", "CVS", "WALGREENS"]);
let pickTarget = null;
let lastEstimate = null;

function renderPresets() {
  for (const box of $$(".loc")) {
    const key = box.dataset.point;
    const select = $(".loc-preset", box);
    const current = presets.find(p => p.lat === points[key].lat && p.lng === points[key].lng);
    select.innerHTML = `<option value="">Choose a place…</option>`
      + `<optgroup label="Campus">${presets.filter(p => scenarioData.places[p.key]).map(p => `<option value="${escapeHTML(p.key)}">${escapeHTML(p.label)}</option>`).join("")}</optgroup>`
      + `<optgroup label="Stores">${scenario.stores.map(s => `<option value="${escapeHTML(s.id)}">${escapeHTML(s.name)}</option>`).join("")}</optgroup>`;
    select.value = current?.key ?? "";
    const p = points[key];
    $(".loc-value", box).textContent = `${p.label ?? "Custom point"} · ${p.lat.toFixed(5)}, ${p.lng.toFixed(5)}`;
  }
}

function renderStoreOptions() {
  $("#store-options").innerHTML = scenario.stores.map(s => `
    <label class="check"><input type="checkbox" value="${escapeHTML(s.id)}" ${selectedStores.has(s.id) ? "checked" : ""} />
      <span>${escapeHTML(s.name)}</span></label>`).join("");
}

function drawPoints() {
  pointLayer.clearLayers();
  marker(points.start, "start", "S", `Runner start: ${points.start.label ?? "custom point"}`).addTo(pointLayer);
  marker(points.destination, "dest", "E", `Runner destination: ${points.destination.label ?? "custom point"}`).addTo(pointLayer);
  marker(points.dropoff, "drop", "D", `Drop-off: ${points.dropoff.label ?? "custom point"}`).addTo(pointLayer);
  const chosen = lastEstimate?.storeId;
  for (const store of scenario.stores.filter(s => selectedStores.has(s.id))) {
    const isChosen = store.id === chosen;
    marker(store, isChosen ? "store" : "store-option", "$", `${store.name}${isChosen ? " (chosen)" : " (option)"}`).addTo(pointLayer);
  }
}

function setPoint(key, point, label) {
  points[key] = { lat: point.lat, lng: point.lng, label };
  lastEstimate = null;
  routeLayer.clearLayers();
  renderPresets();
  drawPoints();
  $("#detour-result").innerHTML = "";
}

function setPickTarget(key) {
  pickTarget = key;
  const banner = $("#pick-banner");
  map.getContainer().classList.toggle("picking", Boolean(key));
  if (key) {
    banner.hidden = false;
    banner.innerHTML = `Click the map to set the <b>${POINT_NAMES[key]}</b> <button type="button" class="ghost" data-action="cancel-pick">Cancel</button>`;
  } else {
    banner.hidden = true;
  }
}

map.on("click", event => {
  if (!pickTarget) return;
  setPoint(pickTarget, { lat: event.latlng.lat, lng: event.latlng.lng }, "Picked on map");
  setPickTarget(null);
});

function geolocate(box) {
  const status = $(".loc-value", box);
  if (!("geolocation" in navigator)) {
    status.textContent = "This browser can't share your location. Choose a place, pick on the map, or type coordinates.";
    return;
  }
  status.textContent = "Asking for your location…";
  navigator.geolocation.getCurrentPosition(
    position => {
      const here = { lat: position.coords.latitude, lng: position.coords.longitude };
      setPoint("start", here, "Your location");
      const km = distanceM(here, CAMPUS) / 1000;
      if (km > 15) {
        $(".loc-value", box).textContent += ` · ${km.toFixed(0)} km from campus. The stores are in Berkeley, so routes will be long.`;
      }
    },
    error => {
      const why = error.code === error.PERMISSION_DENIED ? "Location permission was denied."
        : error.code === error.TIMEOUT ? "Finding your location timed out."
          : "Your location isn't available right now.";
      status.textContent = `${why} Choose a place, pick on the map, or type coordinates instead.`;
    },
    { enableHighAccuracy: true, timeout: 10000, maximumAge: 60000 }
  );
}

document.addEventListener("click", event => {
  const button = event.target.closest("button[data-action]");
  if (!button) return;
  const box = button.closest(".loc");
  if (button.dataset.action === "pick") setPickTarget(box.dataset.point);
  if (button.dataset.action === "geolocate") geolocate(box);
  if (button.dataset.action === "cancel-pick") setPickTarget(null);
});

document.addEventListener("keydown", event => { if (event.key === "Escape" && pickTarget) setPickTarget(null); });

for (const box of $$(".loc")) {
  $(".loc-preset", box).addEventListener("change", event => {
    const preset = presetByKey.get(event.target.value);
    if (preset) setPoint(box.dataset.point, preset, preset.label);
  });
  $(".loc-manual", box).addEventListener("submit", event => {
    event.preventDefault();
    const input = $("input", event.target);
    const point = parseLatLng(input.value);
    if (!point) {
      $(".loc-value", box).textContent = "Type coordinates as “latitude, longitude”, e.g. 37.8726, -122.2607.";
      input.setAttribute("aria-invalid", "true");
      return;
    }
    input.removeAttribute("aria-invalid");
    input.value = "";
    setPoint(box.dataset.point, point, "Typed coordinates");
  });
}

$("#store-options").addEventListener("change", event => {
  if (event.target.checked) selectedStores.add(event.target.value);
  else selectedStores.delete(event.target.value);
  lastEstimate = null;
  routeLayer.clearLayers();
  drawPoints();
});

const minutesInput = id => Math.max(0, Number($(id).value) || 0);

async function computeDetour() {
  const result = $("#detour-result");
  const button = $("#compute");
  const kind = $("#routing").value;
  const mode = $("#mode").value;
  const now = new Date();
  const runner = {
    id: "YOU",
    name: "You",
    start: points.start,
    destination: points.destination,
    departsAt: now.toISOString(),
    availableUntil: new Date(now.getTime() + minutesInput("#available-for") * 60000).toISOString(),
    maxDetourMinutes: minutesInput("#max-detour"),
    status: "available"
  };
  const request = {
    id: "REQUEST",
    item: "your item",
    storeOptions: scenario.stores.filter(s => selectedStores.has(s.id)),
    dropoff: points.dropoff,
    deliverBy: new Date(now.getTime() + minutesInput("#deliver-within") * 60000).toISOString()
  };

  button.disabled = true;
  button.textContent = kind === "osrm" ? "Routing on real streets…" : "Computing…";
  result.innerHTML = "";
  routeLayer.clearLayers();
  try {
    const provider = await providerFor(kind, mode);
    const estimate = await provider.estimateDetour(runner, request, { now: now.toISOString() });
    lastEstimate = estimate;
    drawPoints();
    if (estimate.geometry.original.length > 1) drawRoutes(estimate);
    result.innerHTML = renderEstimate(estimate, provider);
    result.scrollIntoView({ block: "nearest", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
  } catch (error) {
    lastEstimate = null;
    drawPoints();
    // A routing failure is shown as a failure. Nothing is drawn rather than a guessed route.
    result.innerHTML = `<div class="verdict bad"><strong>Routing failed</strong><p>${escapeHTML(error.message)}</p>
      <p class="quiet">Try again in a moment, or switch Routing to Simulated.</p></div>`;
  } finally {
    button.disabled = false;
    button.textContent = "Compute detour";
  }
}

function renderEstimate(e, provider) {
  if (e.reasonCode === REASON.NO_STORE_OPTIONS) {
    return `<div class="verdict bad"><strong>No store selected</strong><p>Tick at least one store that sells the item.</p></div>`;
  }
  const verdict = e.feasible
    ? `<div class="verdict good"><strong>Feasible</strong><p>Adds ${fmtMin(e.addedDurationMin)} min via ${escapeHTML(e.storeName)}; the drop-off is at ${clock(e.dropoffAt)}.</p></div>`
    : `<div class="verdict bad"><strong>Not feasible · ${escapeHTML(REASON_LABEL[e.reasonCode] ?? e.reasonCode)}</strong>
        <p>${escapeHTML(capitalize(reasonText({ reasonCode: e.reasonCode, reasonDetail: e.reasonDetail, estimate: e })))}.</p></div>`;
  return `${verdict}
    <table class="numbers">
      <thead><tr><th scope="col"></th><th scope="col">Distance</th><th scope="col">Time</th></tr></thead>
      <tbody>
        <tr><th scope="row"><i class="line line-original"></i>Original</th><td>${meters(e.original.distanceM)}</td><td>${fmtMin(e.original.durationMin)} min</td></tr>
        <tr><th scope="row"><i class="line line-modified"></i>With delivery</th><td>${meters(e.modified.distanceM)}</td><td>${fmtMin(e.modified.durationMin)} min</td></tr>
        <tr class="total"><th scope="row">Added</th><td>${signed(e.addedDistanceM, meters)}</td><td>+${fmtMin(e.addedDurationMin)} min</td></tr>
      </tbody>
    </table>
    <dl class="facts">
      <div><dt>Chosen store</dt><dd>${escapeHTML(e.storeName)}</dd></div>
      <div><dt>Leaves store</dt><dd>${clock(e.pickupAt)}</dd></div>
      <div><dt>Drop-off</dt><dd>${clock(e.dropoffAt)}</dd></div>
      <div><dt>Runner arrives</dt><dd>${clock(e.tripEndAt)}</dd></div>
    </dl>
    <h3 class="sub">Every store option</h3>
    <ol class="candidates">${e.storeCandidates.map(c => `
      <li class="${c.storeId === e.storeId ? "chosen" : ""}"><span>${escapeHTML(c.storeName)}</span>
        <span>+${fmtMin(c.addedDurationMin)} min</span>
        <span class="${c.feasible ? "ok" : "no"}">${c.feasible ? "fits" : escapeHTML(REASON_LABEL[c.reasonCode] ?? c.reasonCode)}</span></li>`).join("")}
    </ol>
    <p class="quiet">Includes ${DEFAULT_CONFIG.handling.shopMinutes} min shopping and ${DEFAULT_CONFIG.handling.handoffMinutes} min hand-off. ${escapeHTML(provider.description)}.</p>
    <details class="json"><summary>Show the structured output (DetourEstimate)</summary>
      <p class="quiet">This is exactly what <code>estimateDetour()</code> returns to the matching algorithm. Route geometry is shortened here.</p>
      <pre>${escapeHTML(JSON.stringify(summarizeForDisplay(e), null, 2))}</pre></details>`;
}

/** The estimate as matching receives it, with the long route polylines replaced by their size. */
function summarizeForDisplay(e) {
  const points = line => `[${line.length} points]`;
  return { ...e, geometry: { original: points(e.geometry.original), modified: points(e.geometry.modified) } };
}

const capitalize = text => text.charAt(0).toUpperCase() + text.slice(1);

$("#compute").addEventListener("click", computeDetour);

// ---------------------------------------------------------------------------
// Full matching
// ---------------------------------------------------------------------------

let matchState = null;   // { result, provider, selected }
const runnersById = new Map(scenario.runners.map(r => [r.id, r]));
const requestsById = new Map(scenario.requests.map(q => [q.id, q]));
const MATCH_COLORS = ["#f2620f", "#8b5cf6", "#0ea5a4", "#e11d74", "#ca8a04", "#2563eb"];

async function runMatching() {
  const kind = $("#match-routing").value;
  const mode = $("#match-mode").value;
  const progress = $("#match-progress");
  const button = $("#run-match");
  button.disabled = true;
  $("#match-result").innerHTML = "";
  let timer = null;
  try {
    const provider = await providerFor(kind, mode);
    if (provider.stats) {
      const start = { ...provider.stats };
      const tick = () => {
        const done = provider.stats.requests - start.requests;
        const cached = provider.stats.cacheHits - start.cacheHits;
        progress.textContent = `Routing… ${done} route requests, ${cached} reused from cache${provider.stats.failures > start.failures ? `, ${provider.stats.failures - start.failures} failed` : ""}`;
      };
      tick();
      timer = setInterval(tick, 400);
    } else {
      progress.textContent = "Matching…";
    }
    const result = await matchRequests({ ...scenario, provider });
    matchState = { result, provider, selected: null };
    const assigned = result.assignments.length;
    progress.textContent = `${assigned} of ${result.results.length} requests assigned · ${provider.description}`
      + (result.errors.length ? ` · ${result.errors.length} pairs couldn't be routed` : "");
    renderMatching();
  } catch (error) {
    progress.textContent = "";
    $("#match-result").innerHTML = `<div class="verdict bad"><strong>Matching failed</strong><p>${escapeHTML(error.message)}</p></div>`;
  } finally {
    clearInterval(timer);
    button.disabled = false;
  }
}

function renderMatching() {
  const { result, selected } = matchState;
  const changes = new Map(result.changes.map(c => [c.requestId, c]));
  $("#match-result").innerHTML = `<ol class="assignments">${result.results.map((r, i) => {
    const request = requestsById.get(r.requestId);
    const change = changes.get(r.requestId);
    const runner = r.runnerId ? runnersById.get(r.runnerId) : null;
    const body = r.status === "assigned"
      ? `<p class="who"><i class="swatch" style="background:${MATCH_COLORS[i % MATCH_COLORS.length]}"></i><b>${escapeHTML(r.runnerId)} ${escapeHTML(runner.name)}</b> via ${escapeHTML(r.storeName)}</p>
         <p class="stats">+${fmtMin(r.estimate.addedDurationMin)} min · ${signed(r.estimate.addedDistanceM, meters)} · drop-off ${clock(r.estimate.dropoffAt)} · score ${r.score.total.toFixed(2)}</p>`
      : `<p class="who unmatched">Unmatched · ${escapeHTML(REASON_LABEL[r.reasonCode] ?? r.reasonCode)}</p>`;
    return `<li class="assignment ${selected === r.requestId ? "selected" : ""} ${change ? "changed" : ""}">
      <button class="assignment-head" data-match="select" data-request="${escapeHTML(r.requestId)}" aria-pressed="${selected === r.requestId}">
        <span class="req">${escapeHTML(r.requestId)} · ${escapeHTML(r.item)}</span>
        <span class="to">→ ${escapeHTML(request.dropoff.label)} by ${clock(request.deliverBy)}</span>
        ${body}
        ${change ? `<p class="change">Changed: ${escapeHTML(change.from ?? "unassigned")} → ${escapeHTML(change.to ?? "unassigned")}</p>` : ""}
      </button>
      <details><summary>Why</summary><ul>${r.explanationLines.map(line => `<li>${escapeHTML(line)}</li>`).join("")}</ul></details>
      ${r.status === "assigned" ? `<div class="actions">
        <button class="ghost" data-match="decline" data-request="${escapeHTML(r.requestId)}" data-runner="${escapeHTML(r.runnerId)}">${escapeHTML(runner.name)} declines</button>
        <button class="ghost" data-match="offline" data-runner="${escapeHTML(r.runnerId)}">${escapeHTML(runner.name)} goes offline</button></div>` : ""}
    </li>`;
  }).join("")}</ol>`;
  drawMatching();
}

function drawMatching() {
  const { result, selected } = matchState;
  pointLayer.clearLayers();
  routeLayer.clearLayers();
  const focus = [];
  result.results.forEach((r, i) => {
    const request = requestsById.get(r.requestId);
    const isSelected = selected === r.requestId;
    const dim = selected && !isSelected;
    marker(request.dropoff, "drop", "D", `${r.requestId} drop-off: ${request.dropoff.label}`, { opacity: dim ? 0.4 : 1 }).addTo(pointLayer);
    if (r.status !== "assigned") return;
    const runner = runnersById.get(r.runnerId);
    const color = MATCH_COLORS[i % MATCH_COLORS.length];
    if (isSelected) {
      focus.push(...drawRoutes(r.estimate, { fit: false }));
      marker(runner.start, "start", "S", `${runner.id} ${runner.name} starts: ${runner.start.label}`).addTo(pointLayer);
      marker(runner.destination, "dest", "E", `${runner.id} ${runner.name} heading to: ${runner.destination.label}`).addTo(pointLayer);
      const store = scenario.stores.find(s => s.id === r.storeId);
      marker(store, "store", "$", `${store.name} (chosen)`).addTo(pointLayer);
    } else {
      const line = L.polyline(r.estimate.geometry.modified.map(p => [p.lat, p.lng]), { color, weight: 4, opacity: dim ? 0.25 : 0.85 })
        .bindTooltip(escapeHTML(`${r.requestId} ${r.item}: ${runner.name} via ${r.storeName}`), { sticky: true })
        .on("click", () => selectRequest(r.requestId));
      line.addTo(routeLayer);
      if (!selected) focus.push(line);
    }
  });
  setLegend(selected ? LEGEND_ROUTES : LEGEND_OVERVIEW);
  if (focus.length) map.fitBounds(L.featureGroup(focus).getBounds().pad(0.12));
}

function selectRequest(requestId) {
  matchState.selected = matchState.selected === requestId ? null : requestId;
  renderMatching();
}

$("#match-result").addEventListener("click", event => {
  const button = event.target.closest("button[data-match]");
  if (!button || !matchState) return;
  const action = button.dataset.match;
  if (action === "select") selectRequest(button.dataset.request);
  if (action === "decline") {
    matchState.result = declineAssignment(matchState.result, button.dataset.request, button.dataset.runner);
    renderMatching();
  }
  if (action === "offline") {
    matchState.result = markRunnerOffline(matchState.result, button.dataset.runner);
    renderMatching();
  }
});

$("#run-match").addEventListener("click", runMatching);
$("#match-routing").addEventListener("change", () => {
  const recorded = $("#match-routing").value === "recorded";
  $("#match-mode").value = recorded ? "foot" : $("#match-mode").value;
  $("#match-mode").disabled = recorded;
});
$("#match-mode").disabled = $("#match-routing").value === "recorded";

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------

function showTab(name) {
  for (const tab of $$("[role=tab]")) {
    const active = tab.id === `tab-${name}`;
    tab.setAttribute("aria-selected", String(active));
    tab.tabIndex = active ? 0 : -1;
    $(`#${tab.getAttribute("aria-controls")}`).hidden = !active;
  }
  setPickTarget(null);
  setLegend(LEGEND_ROUTES);
  if (name === "match" && matchState) {
    drawMatching();
  } else if (name === "detour") {
    routeLayer.clearLayers();
    drawPoints();
    if (lastEstimate?.geometry.original.length > 1) drawRoutes(lastEstimate);
  } else {
    pointLayer.clearLayers();
    routeLayer.clearLayers();
  }
}

$(".tabs").addEventListener("click", event => {
  const tab = event.target.closest("[role=tab]");
  if (tab) showTab(tab.id.replace("tab-", ""));
});
$(".tabs").addEventListener("keydown", event => {
  if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
  const tabs = $$("[role=tab]");
  const next = tabs[(tabs.indexOf(document.activeElement) + (event.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length];
  next.focus();
  showTab(next.id.replace("tab-", ""));
});

renderPresets();
renderStoreOptions();
drawPoints();
map.fitBounds(L.latLngBounds([points.start, points.destination, points.dropoff, ...scenario.stores].map(p => [p.lat, p.lng])).pad(0.1));
